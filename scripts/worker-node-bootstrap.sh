#!/bin/bash
# Docker Swarm worker bootstrap.
# Runs from ASG launch template user_data:
# install Docker -> run Backend container -> fetch join info from SSM -> join Swarm.

set -euo pipefail

exec > >(tee /var/log/worker-node-bootstrap.log) 2>&1

NAME_PREFIX="${name_prefix}"
AWS_REGION="${aws_region}"
SSM_MANAGER_IP="/$${NAME_PREFIX}/swarm/manager-ip"
SSM_WORKER_TOKEN="/$${NAME_PREFIX}/swarm/worker-token"
SSM_REDIS_HOST="/$${NAME_PREFIX}/redis/host"
SSM_REDIS_PORT="/$${NAME_PREFIX}/redis/port"
SSM_REDIS_PASSWORD="/$${NAME_PREFIX}/redis/password"
SSM_DB_HOST="/$${NAME_PREFIX}/db/host"
SSM_DB_PORT="/$${NAME_PREFIX}/db/port"
SSM_DB_NAME="/$${NAME_PREFIX}/db/name"
SSM_DB_USER="/$${NAME_PREFIX}/db/user"
SSM_DB_PASSWORD="/$${NAME_PREFIX}/db/password"
MAX_RETRIES=60
RETRY_INTERVAL=10
JOIN_MAX_RETRIES=12
MANAGER_CONNECT_TIMEOUT=3
DB_CONNECT_TIMEOUT=3
BACKEND_IMAGE="ohyoungsik/ict-studio-be:latest"
BACKEND_IMAGE_S3_URI="${backend_image_s3_uri}"
BACKEND_CONTAINER_NAME="ict-studio-be"

log() {
  echo "[$(date -Is)] $*"
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker already installed: $(docker --version)"
    return
  fi

  log "Installing Docker Engine"
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io

  systemctl enable docker
  systemctl start docker
}

install_aws_cli() {
  if command -v aws >/dev/null 2>&1; then
    log "AWS CLI already installed: $(aws --version 2>&1 | head -n1)"
    return
  fi

  log "Installing AWS CLI"
  apt-get update -y
  apt-get install -y awscli
}

get_imds_token() {
  curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"
}

fetch_swarm_join_info() {
  local manager_ip="" worker_token="" attempt

  for attempt in $(seq 1 "$MAX_RETRIES"); do
    log "Fetching Swarm join info from SSM (attempt $attempt/$MAX_RETRIES)"

    manager_ip="$(aws ssm get-parameter \
      --region "$AWS_REGION" \
      --name "$SSM_MANAGER_IP" \
      --query 'Parameter.Value' \
      --output text 2>/dev/null || true)"

    worker_token="$(aws ssm get-parameter \
      --region "$AWS_REGION" \
      --name "$SSM_WORKER_TOKEN" \
      --with-decryption \
      --query 'Parameter.Value' \
      --output text 2>/dev/null || true)"

    if [[ -n "$manager_ip" && -n "$worker_token" && "$manager_ip" != "None" && "$worker_token" != "None" ]]; then
      MANAGER_IP="$manager_ip"
      WORKER_TOKEN="$worker_token"
      return 0
    fi

    sleep "$RETRY_INTERVAL"
  done

  return 1
}

fetch_redis_config() {
  local attempt host port password

  for attempt in $(seq 1 "$MAX_RETRIES"); do
    log "Fetching Redis config from SSM (attempt $attempt/$MAX_RETRIES)"

    host="$(aws ssm get-parameter \
      --region "$AWS_REGION" \
      --name "$SSM_REDIS_HOST" \
      --query 'Parameter.Value' \
      --output text 2>/dev/null || true)"

    port="$(aws ssm get-parameter \
      --region "$AWS_REGION" \
      --name "$SSM_REDIS_PORT" \
      --query 'Parameter.Value' \
      --output text 2>/dev/null || true)"

    password="$(aws ssm get-parameter \
      --region "$AWS_REGION" \
      --name "$SSM_REDIS_PASSWORD" \
      --with-decryption \
      --query 'Parameter.Value' \
      --output text 2>/dev/null || true)"

    if [[ -n "$host" && -n "$port" && -n "$password" && "$host" != "None" && "$port" != "None" && "$password" != "None" ]]; then
      REDIS_HOST="$host"
      REDIS_PORT="$port"
      REDIS_PASSWORD="$password"

      if redis_port_open; then
        log "Redis reachable at $REDIS_HOST:$REDIS_PORT"
        return 0
      fi

      log "Redis config found but $REDIS_HOST:$REDIS_PORT is not reachable yet"
    fi

    sleep "$RETRY_INTERVAL"
  done

  return 1
}

redis_port_open() {
  timeout "$MANAGER_CONNECT_TIMEOUT" bash -c 'cat < /dev/null > /dev/tcp/"$1"/"$2"' _ "$REDIS_HOST" "$REDIS_PORT" >/dev/null 2>&1
}

fetch_db_config() {
  local attempt host port name user password

  for attempt in $(seq 1 "$MAX_RETRIES"); do
    log "Fetching DB config from SSM (attempt $attempt/$MAX_RETRIES)"

    host="$(aws ssm get-parameter \
      --region "$AWS_REGION" \
      --name "$SSM_DB_HOST" \
      --query 'Parameter.Value' \
      --output text 2>/dev/null || true)"

    port="$(aws ssm get-parameter \
      --region "$AWS_REGION" \
      --name "$SSM_DB_PORT" \
      --query 'Parameter.Value' \
      --output text 2>/dev/null || true)"

    name="$(aws ssm get-parameter \
      --region "$AWS_REGION" \
      --name "$SSM_DB_NAME" \
      --query 'Parameter.Value' \
      --output text 2>/dev/null || true)"

    user="$(aws ssm get-parameter \
      --region "$AWS_REGION" \
      --name "$SSM_DB_USER" \
      --query 'Parameter.Value' \
      --output text 2>/dev/null || true)"

    password="$(aws ssm get-parameter \
      --region "$AWS_REGION" \
      --name "$SSM_DB_PASSWORD" \
      --with-decryption \
      --query 'Parameter.Value' \
      --output text 2>/dev/null || true)"

    if [[ -n "$host" && -n "$port" && -n "$name" && -n "$user" && -n "$password" \
      && "$host" != "None" && "$port" != "None" && "$name" != "None" \
      && "$user" != "None" && "$password" != "None" ]]; then
      DB_HOST="$host"
      DB_PORT="$port"
      DB_NAME="$name"
      DB_USER="$user"
      DB_PASSWORD="$password"
      return 0
    fi

    sleep "$RETRY_INTERVAL"
  done

  return 1
}

db_port_open() {
  timeout "$DB_CONNECT_TIMEOUT" bash -c 'cat < /dev/null > /dev/tcp/"$1"/"$2"' _ "$DB_HOST" "$DB_PORT" >/dev/null 2>&1
}

cleanup_swarm_state() {
  local swarm_state

  swarm_state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo inactive)"

  if [[ "$swarm_state" == "active" ]]; then
    log "Node is already part of a Swarm cluster"
    docker node ls 2>/dev/null || true
    return 0
  fi

  if [[ "$swarm_state" == "error" || "$swarm_state" == "pending" ]]; then
    log "Broken swarm state detected: $swarm_state. Leaving first."
    docker swarm leave --force || true
    sleep 3
  fi

  return 1
}

manager_port_open() {
  local manager_ip="$1"

  timeout "$MANAGER_CONNECT_TIMEOUT" bash -c 'cat < /dev/null > /dev/tcp/"$1"/2377' _ "$manager_ip" >/dev/null 2>&1
}

log_join_metadata() {
  local token private_ip instance_id az

  token="$(get_imds_token)"
  instance_id="$(curl -sf -H "X-aws-ec2-metadata-token: $token" \
    http://169.254.169.254/latest/meta-data/instance-id)"
  private_ip="$(curl -sf -H "X-aws-ec2-metadata-token: $token" \
    http://169.254.169.254/latest/meta-data/local-ipv4)"
  az="$(curl -sf -H "X-aws-ec2-metadata-token: $token" \
    http://169.254.169.254/latest/meta-data/placement/availability-zone)"

  log "Swarm join complete (instance=$instance_id ip=$private_ip az=$az)"
}

join_swarm() {
  local attempt

  if cleanup_swarm_state; then
    return
  fi

  for attempt in $(seq 1 "$JOIN_MAX_RETRIES"); do
    if ! fetch_swarm_join_info; then
      log "ERROR: Could not fetch Swarm join info from SSM"
      exit 1
    fi

    if ! manager_port_open "$MANAGER_IP"; then
      log "Manager $MANAGER_IP:2377 is not reachable (attempt $attempt/$JOIN_MAX_RETRIES)"
      sleep "$RETRY_INTERVAL"
      continue
    fi

    log "Joining Swarm cluster at $MANAGER_IP:2377 (attempt $attempt/$JOIN_MAX_RETRIES)"
    if docker swarm join --token "$WORKER_TOKEN" "$MANAGER_IP:2377"; then
      log_join_metadata
      return
    fi

    log "Swarm join failed. Leaving any partial state before retry."
    docker swarm leave --force || true
    sleep "$RETRY_INTERVAL"
  done

  log "ERROR: Swarm join failed after $JOIN_MAX_RETRIES attempts"
  exit 1
}

load_backend_image() {
  if [[ -n "$BACKEND_IMAGE_S3_URI" ]]; then
    log "Loading Backend image from S3 ($BACKEND_IMAGE_S3_URI)"
    if aws s3 cp "$BACKEND_IMAGE_S3_URI" /tmp/backend-image.tar.gz \
      && gunzip -c /tmp/backend-image.tar.gz | docker load; then
      return
    fi

    log "WARNING: Failed to load backend image from S3; falling back to Docker Hub image $BACKEND_IMAGE"
  fi

  log "Pulling Backend image from Docker Hub"
  docker pull "$BACKEND_IMAGE"
}

setup_backend_app() {
  local -a redis_env=() db_env=()
  local backend_health_ok=false redis_health_ok=false

  if ! fetch_redis_config; then
    log "ERROR: Redis config is not available or reachable from SSM; refusing to start backend without Redis env"
    exit 1
  fi

  if fetch_db_config; then
    db_env=(
      -e "DB_HOST=$DB_HOST"
      -e "DB_PORT=$DB_PORT"
      -e "DB_NAME=$DB_NAME"
      -e "DB_USER=$DB_USER"
      -e "DB_PASSWORD=$DB_PASSWORD"
    )

    if db_port_open; then
      log "DB endpoint reachable at $DB_HOST:$DB_PORT"
    else
      log "DB config found but $DB_HOST:$DB_PORT is not reachable yet; backend container will retry via Docker restart policy"
    fi
  else
    log "DB config is not available from SSM yet; starting backend without DB env"
  fi

  log "Redis reachable at $REDIS_HOST:$REDIS_PORT"
  redis_env=(
    -e "REDIS_HOST=$REDIS_HOST"
    -e "REDIS_PORT=$REDIS_PORT"
    -e "REDIS_DB=0"
    -e "REDIS_PASSWORD=$REDIS_PASSWORD"
    -e "REDIS_CONNECT_TIMEOUT=2"
    -e "REDIS_SOCKET_TIMEOUT=2"
  )

  log "Starting Backend container"
  load_backend_image
  docker rm -f "$BACKEND_CONTAINER_NAME" || true
  docker run -d \
    --name "$BACKEND_CONTAINER_NAME" \
    --restart always \
    -p 8000:8000 \
    -e PYTHONUNBUFFERED=1 \
    "$${redis_env[@]}" \
    "$${db_env[@]}" \
    "$BACKEND_IMAGE"

  for attempt in $(seq 1 "$MAX_RETRIES"); do
    if curl -fsS http://127.0.0.1:8000/health >/dev/null 2>&1; then
      log "Backend health check passed"
      backend_health_ok=true
      break
    fi

    log "Waiting for Backend health check (attempt $attempt/$MAX_RETRIES)"
    sleep "$RETRY_INTERVAL"
  done

  for attempt in $(seq 1 "$MAX_RETRIES"); do
    if curl -fsS http://127.0.0.1:8000/api/health/redis >/dev/null 2>&1; then
      log "Backend Redis health check passed"
      redis_health_ok=true
      break
    fi

    log "Waiting for Backend Redis health check (attempt $attempt/$MAX_RETRIES)"
    sleep "$RETRY_INTERVAL"
  done

  if [[ "$backend_health_ok" == "true" && "$redis_health_ok" == "true" ]]; then
    return
  fi

  log "WARNING: Backend did not become fully healthy during bootstrap; leaving container under --restart always"
  docker inspect "$BACKEND_CONTAINER_NAME" --format '{{range .Config.Env}}{{println .}}{{end}}' \
    | grep -E '^(REDIS_HOST|REDIS_PORT|REDIS_DB|REDIS_CONNECT_TIMEOUT|REDIS_SOCKET_TIMEOUT|DB_HOST|DB_PORT|DB_NAME|DB_USER)=' || true
  docker logs "$BACKEND_CONTAINER_NAME" || true
}

setup_monitoring_agent() {
  local token instance_id private_ip

  token="$(get_imds_token)"
  instance_id="$(curl -sf -H "X-aws-ec2-metadata-token: $token" \
    http://169.254.169.254/latest/meta-data/instance-id)"
  private_ip="$(curl -sf -H "X-aws-ec2-metadata-token: $token" \
    http://169.254.169.254/latest/meta-data/local-ipv4)"

  mkdir -p /opt/monitoring-agent

  cat > /opt/monitoring-agent/.env <<EOF
HOST_ROLE=${host_role}
HOST_NAME=$instance_id
HOST_IP=$private_ip
LOKI_PUSH_URL=${loki_push_url}
EOF

  cat > /opt/monitoring-agent/config.alloy <<'EOF'
loki.write "default" {
  endpoint {
    url = env("LOKI_PUSH_URL")
  }
}

local.file_match "system_logs" {
  path_targets = [
    {
      __path__   = "/var/log/syslog",
      job        = "system",
      role       = env("HOST_ROLE"),
      instance   = env("HOST_NAME"),
      private_ip = env("HOST_IP"),
    },
    {
      __path__   = "/var/log/auth.log",
      job        = "auth",
      role       = env("HOST_ROLE"),
      instance   = env("HOST_NAME"),
      private_ip = env("HOST_IP"),
    },
    {
      __path__   = "/var/log/*.log",
      job        = "varlog",
      role       = env("HOST_ROLE"),
      instance   = env("HOST_NAME"),
      private_ip = env("HOST_IP"),
    },
  ]
}

loki.source.file "system_logs" {
  targets    = local.file_match.system_logs.targets
  forward_to = [loki.write.default.receiver]
}

local.file_match "docker_logs" {
  path_targets = [
    {
      __path__   = "/var/lib/docker/containers/*/*.log",
      job        = "docker",
      role       = env("HOST_ROLE"),
      instance   = env("HOST_NAME"),
      private_ip = env("HOST_IP"),
    },
  ]
}

loki.source.file "docker_logs" {
  targets    = local.file_match.docker_logs.targets
  forward_to = [loki.process.docker_logs.receiver]
}

loki.process "docker_logs" {
  stage.json {
    expressions = {
      output = "log",
      stream = "stream",
      time   = "time",
    }
  }

  stage.timestamp {
    source = "time"
    format = "RFC3339Nano"
  }

  stage.labels {
    values = {
      stream = "",
    }
  }

  stage.output {
    source = "output"
  }

  forward_to = [loki.write.default.receiver]
}
EOF

  docker rm -f node-exporter || true
  docker run -d \
    --name node-exporter \
    --restart always \
    --pid="host" \
    -p 9100:9100 \
    -v /proc:/host/proc:ro \
    -v /sys:/host/sys:ro \
    -v /:/rootfs:ro \
    prom/node-exporter:v1.11.1 \
    --path.procfs=/host/proc \
    --path.sysfs=/host/sys \
    --path.rootfs=/rootfs \
    --collector.filesystem.mount-points-exclude='^/(sys|proc|dev|host|etc)($|/)'

  docker rm -f cadvisor || true
  docker run -d \
    --name cadvisor \
    --restart always \
    -p 8081:8080 \
    -v /:/rootfs:ro \
    -v /var/run:/var/run:ro \
    -v /sys:/sys:ro \
    -v /var/lib/docker/:/var/lib/docker:ro \
    gcr.io/cadvisor/cadvisor:v0.55.1

  docker rm -f alloy || true
  docker run -d \
    --name alloy \
    --restart always \
    --env-file /opt/monitoring-agent/.env \
    -v /opt/monitoring-agent/config.alloy:/etc/alloy/config.alloy:ro \
    -v /var/log:/var/log:ro \
    -v /var/lib/docker/containers:/var/lib/docker/containers:ro \
    -v alloy-data:/var/lib/alloy/data \
    grafana/alloy:v1.16.2 \
    run /etc/alloy/config.alloy \
    --storage.path=/var/lib/alloy/data

  log "Monitoring agent started"
}

log "Starting worker node bootstrap"
install_docker
setup_monitoring_agent
install_aws_cli
setup_backend_app
join_swarm
log "Worker node bootstrap finished"
