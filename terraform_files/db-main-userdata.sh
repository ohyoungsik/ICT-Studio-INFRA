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