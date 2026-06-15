#!/bin/bash
# Docker Swarm worker bootstrap.
# Runs from ASG launch template user_data:
# install Docker -> run React container -> configure Nginx proxy -> fetch join info from SSM -> join Swarm.

set -euo pipefail

exec > >(tee /var/log/worker-node-bootstrap.log) 2>&1

NAME_PREFIX="${name_prefix}"
AWS_REGION="${aws_region}"
SSM_MANAGER_IP="/$${NAME_PREFIX}/swarm/manager-ip"
SSM_WORKER_TOKEN="/$${NAME_PREFIX}/swarm/worker-token"
MAX_RETRIES=60
RETRY_INTERVAL=10
JOIN_MAX_RETRIES=12
MANAGER_CONNECT_TIMEOUT=3
REACT_IMAGE="ohyoungsik/ict-studio-fe:latest"
REACT_CONTAINER_NAME="ict-studio-fe"

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

setup_react_app() {
  log "Installing host Nginx"
  apt-get update -y
  apt-get install -y nginx
  systemctl enable nginx

  log "Starting React container"
  docker rm -f nginx-test || true
  docker pull "$REACT_IMAGE"
  docker rm -f "$REACT_CONTAINER_NAME" || true
  docker run -d \
    --name "$REACT_CONTAINER_NAME" \
    --restart always \
    -p 8080:80 \
    "$REACT_IMAGE"

  cat > /etc/nginx/sites-available/default <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    location = /health {
        access_log off;
        add_header Content-Type text/plain;
        return 200 "ok\n";
    }

    location /api/ {
        proxy_pass http://127.0.0.1:8000/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

  nginx -t
  systemctl restart nginx
  log "React app is running on container port 80 via host port 8080, proxied by Nginx on port 80"
setup_alb_fallback_service() {
  log "Starting temporary nginx health responder on port 80"

  mkdir -p /opt/nginx-test
  echo "ok" > /opt/nginx-test/health
  echo "bootstrap in progress" > /opt/nginx-test/index.html

  docker rm -f nginx-test ict-studio-be || true
  docker run -d \
    --name nginx-test \
    --restart always \
    -p 80:80 \
    -v /opt/nginx-test:/usr/share/nginx/html:ro \
    nginx:alpine

  log "Temporary nginx health responder started on port 80"
}

setup_backend_service() {
  local repo_dir="/opt/ict-studio-be"
  local image_name="ict-studio-be:local"

  log "Deploying ICT-Studio-BE FastAPI backend"

  apt-get install -y git

  if [[ -d "$repo_dir/.git" ]]; then
    log "Updating backend repository in $repo_dir"
    git -C "$repo_dir" fetch --depth 1 origin "${backend_repo_branch}"
    git -C "$repo_dir" checkout "${backend_repo_branch}"
    git -C "$repo_dir" reset --hard "origin/${backend_repo_branch}"
  else
    log "Updating backend repository in $repo_dir"
    rm -rf "$repo_dir"
    git clone --depth 1 --branch "${backend_repo_branch}" "${backend_repo_url}" "$repo_dir"
  fi

  if [[ ! -f "$repo_dir/Dockerfile" ]]; then
    log "ERROR: Dockerfile not found in ${backend_repo_url} (${backend_repo_branch})"
    log "Keeping nginx fallback on port 80 until backend image is available"
    return 1
  fi

  if ! docker build -t "$image_name" "$repo_dir"; then
    log "ERROR: Docker build failed for ICT-Studio-BE"
    log "Keeping nginx fallback on port 80"
    return 1
  fi

  docker rm -f ict-studio-be nginx-test || true
  docker run -d \
    --name ict-studio-be \
    --restart always \
    -p 80:8000 \
    -e PYTHONUNBUFFERED=1 \
    "$image_name"

  log "ICT-Studio-BE container started on port 80"
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
setup_react_app
setup_alb_fallback_service
setup_backend_service || true
install_aws_cli
join_swarm
setup_monitoring_agent
log "Worker node bootstrap finished"
