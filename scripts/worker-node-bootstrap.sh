#!/bin/bash
# Docker Swarm worker bootstrap.
# Runs from ASG launch template user_data:
# install Docker -> start ALB test nginx -> fetch join info from SSM -> join Swarm.

set -euo pipefail

exec > >(tee /var/log/worker-node-bootstrap.log) 2>&1

NAME_PREFIX="${name_prefix}"
AWS_REGION="${aws_region}"
SSM_MANAGER_IP="/$${NAME_PREFIX}/swarm/manager-ip"
SSM_WORKER_TOKEN="/$${NAME_PREFIX}/swarm/worker-token"
MAX_RETRIES=60
RETRY_INTERVAL=10

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

join_swarm() {
  local swarm_state token private_ip instance_id az

  swarm_state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo inactive)"
  if [[ "$swarm_state" == "active" ]]; then
    log "Node is already part of a Swarm cluster"
    docker node ls 2>/dev/null || true
    return
  fi

  if ! fetch_swarm_join_info; then
    log "ERROR: Could not fetch Swarm join info from SSM"
    exit 1
  fi

  log "Joining Swarm cluster at $MANAGER_IP:2377"
  docker swarm join --token "$WORKER_TOKEN" "$MANAGER_IP:2377"

  token="$(get_imds_token)"
  instance_id="$(curl -sf -H "X-aws-ec2-metadata-token: $token" \
    http://169.254.169.254/latest/meta-data/instance-id)"
  private_ip="$(curl -sf -H "X-aws-ec2-metadata-token: $token" \
    http://169.254.169.254/latest/meta-data/local-ipv4)"
  az="$(curl -sf -H "X-aws-ec2-metadata-token: $token" \
    http://169.254.169.254/latest/meta-data/placement/availability-zone)"

  log "Swarm join complete (instance=$instance_id ip=$private_ip az=$az)"
}

setup_alb_test_service() {
  local token instance_id private_ip az

  token="$(get_imds_token)"
  instance_id="$(curl -sf -H "X-aws-ec2-metadata-token: $token" \
    http://169.254.169.254/latest/meta-data/instance-id)"
  private_ip="$(curl -sf -H "X-aws-ec2-metadata-token: $token" \
    http://169.254.169.254/latest/meta-data/local-ipv4)"
  az="$(curl -sf -H "X-aws-ec2-metadata-token: $token" \
    http://169.254.169.254/latest/meta-data/placement/availability-zone)"

  mkdir -p /opt/nginx-test

  cat > /opt/nginx-test/index.html <<EOF
<!doctype html>
<html lang="ko">
  <head>
    <meta charset="utf-8">
    <title>ICT Studio ALB Test</title>
    <style>
      body {
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
        font-family: Arial, "Noto Sans KR", sans-serif;
        background: #f4f7fb;
        color: #1f2937;
      }
      main {
        width: min(720px, calc(100% - 40px));
        padding: 32px;
        border: 1px solid #d8dee8;
        border-radius: 8px;
        background: #ffffff;
        box-shadow: 0 12px 32px rgba(15, 23, 42, 0.08);
      }
      h1 {
        margin: 0 0 20px;
        font-size: 32px;
      }
      p {
        margin: 10px 0;
        font-size: 18px;
        line-height: 1.6;
      }
      strong {
        color: #0f766e;
      }
    </style>
  </head>
  <body>
    <main>
      <h1>ICT Studio ALB Test</h1>
      <p>Swarm Worker - Private <strong>$private_ip</strong></p>
      <p>Instance ID: <strong>$instance_id</strong></p>
      <p>Availability Zone: <strong>$az</strong></p>
      <p>ALB routing test success</p>
    </main>
  </body>
</html>
EOF

  echo "ok" > /opt/nginx-test/health

  docker rm -f nginx-test || true
  docker run -d \
    --name nginx-test \
    --restart always \
    -p 80:80 \
    -v /opt/nginx-test:/usr/share/nginx/html:ro \
    nginx:alpine

  log "ALB test nginx container started on port 80"
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
    -p 8080:8080 \
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
setup_alb_test_service
install_aws_cli
join_swarm
setup_monitoring_agent
log "Worker node bootstrap finished"
