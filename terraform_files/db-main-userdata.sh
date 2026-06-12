#!/bin/bash
set -e

# Docker 공식 리포지토리 등록 및 설치
apt-get update -y
apt-get install -y ca-certificates curl gnupg

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io

systemctl enable docker
systemctl start docker

# PostgreSQL 데이터 디렉토리 생성
mkdir -p /opt/postgres/data

# PostgreSQL 15 컨테이너 실행
docker run -d \
  --name postgres-main \
  --restart unless-stopped \
  -e POSTGRES_DB=${db_name} \
  -e POSTGRES_USER=${db_user} \
  -e POSTGRES_PASSWORD=${db_password} \
  -v /opt/postgres/data:/var/lib/postgresql/data \
  -p 5432:5432 \
  postgres:15

# 모니터링 에이전트 설정
mkdir -p /opt/monitoring-agent

TOKEN=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
PRIVATE_IP=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/local-ipv4)

cat > /opt/monitoring-agent/.env <<EOF
HOST_ROLE=${host_role}
HOST_NAME=$INSTANCE_ID
HOST_IP=$PRIVATE_IP
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

# 모니터링 대상에 포함시키기 위해 ec2생성시 node-exporter가 자동으로 켜지는 설정 추가
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
  run --storage.path=/var/lib/alloy/data \
  /etc/alloy/config.alloy

cd /opt/monitoring
docker compose up -d