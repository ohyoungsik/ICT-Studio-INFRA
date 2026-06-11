#!/bin/bash
# Docker Swarm Worker 노드 초기화 스크립트
# ASG launch template user_data로 실행: Docker 설치 → SSM에서 join 정보 조회 → swarm join → ALB 테스트 nginx

set -euo pipefail

# 부트스트랩 전체 로그를 파일과 콘솔에 동시 기록
exec > >(tee /var/log/worker-node-bootstrap.log) 2>&1

NAME_PREFIX="${name_prefix}"
AWS_REGION="${aws_region}"
SSM_MANAGER_IP="/$${NAME_PREFIX}/swarm/manager-ip"
SSM_WORKER_TOKEN="/$${NAME_PREFIX}/swarm/worker-token"
# master가 SSM에 값을 쓸 때까지 최대 30회(약 5분) 대기
MAX_RETRIES=30
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
  # SSM Parameter Store에서 join 정보 조회에 사용 (aws ssm get-parameter)
  apt-get install -y awscli
}

get_imds_token() {
  # IMDSv2 토큰 발급 (EC2 메타데이터 접근용)
  curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"
}

fetch_swarm_join_info() {
  local manager_ip="" worker_token="" attempt

  for attempt in $(seq 1 "$MAX_RETRIES"); do
    log "Fetching Swarm join info from SSM (attempt $attempt/$MAX_RETRIES)"

    # SSM에서 manager 프라이빗 IP 조회
    manager_ip="$(aws ssm get-parameter \
      --region "$AWS_REGION" \
      --name "$SSM_MANAGER_IP" \
      --query 'Parameter.Value' \
      --output text 2>/dev/null || true)"

    # SSM에서 worker join token 조회 (SecureString이므로 --with-decryption 필요)
    worker_token="$(aws ssm get-parameter \
      --region "$AWS_REGION" \
      --name "$SSM_WORKER_TOKEN" \
      --with-decryption \
      --query 'Parameter.Value' \
      --output text 2>/dev/null || true)"

    # 두 값이 모두 있으면 조회 성공
    if [[ -n "$manager_ip" && -n "$worker_token" && "$manager_ip" != "None" && "$worker_token" != "None" ]]; then
      MANAGER_IP="$manager_ip"
      WORKER_TOKEN="$worker_token"
      return 0
    fi

    # master bootstrap 완료 전이면 10초 후 재시도
    sleep "$RETRY_INTERVAL"
  done

  return 1
}

join_swarm() {
  local swarm_state token private_ip instance_id az

  swarm_state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo inactive)"
  if [[ "$swarm_state" == "active" ]]; then
    # 이미 클러스터에 속해 있으면 join 생략
    log "Node is already part of a Swarm cluster"
    docker node ls 2>/dev/null || true
    return
  fi

  if ! fetch_swarm_join_info; then
    log "ERROR: Could not fetch Swarm join info from SSM"
    exit 1
  fi

  log "Joining Swarm cluster at $MANAGER_IP:2377"
  # worker token으로 manager:2377에 Swarm 클러스터 합류
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

  # ALB health check 및 테스트 페이지용 정적 파일 디렉터리
  mkdir -p /opt/nginx-test

  # 인스턴스 정보가 포함된 테스트 HTML 생성
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

  # ALB target group health check 경로 (/health)용 응답 파일
  echo "ok" > /opt/nginx-test/health

  # 동일 이름 컨테이너가 있으면 제거 후 재생성
  docker rm -f nginx-test || true
  # nginx 컨테이너: 호스트 80 → 컨테이너 80, 정적 파일 read-only 마운트
  docker run -d \
    --name nginx-test \
    --restart always \
    -p 80:80 \
    -v /opt/nginx-test:/usr/share/nginx/html:ro \
    nginx:alpine

  log "ALB test nginx container started on port 80"
}
# monitoring agent 추가
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
