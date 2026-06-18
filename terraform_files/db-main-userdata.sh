#!/bin/bash
set -e

# db_main은 PostgreSQL HA용 Docker Swarm manager 및 HAProxy 배치 노드이다.
# 기존 단일 PostgreSQL 컨테이너(postgres-main)는 더 이상 실행하지 않는다.
hostnamectl set-hostname "${hostname}"

cat >/etc/hosts.tmp <<EOF
127.0.0.1 localhost
127.0.1.1 ${hostname}
EOF

grep -vE '^(127\.0\.0\.1|127\.0\.1\.1)\s' /etc/hosts >>/etc/hosts.tmp || true
mv /etc/hosts.tmp /etc/hosts

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

# postgres-ha stack 파일과 Docker runtime이 사용할 기본 디렉터리를 준비한다.
mkdir -p /opt/postgres-ha /data/postgres
chown -R 1001:1001 /data/postgres
chmod 700 /data/postgres

# 모니터링 대상에 포함시키기 위해 node-exporter를 자동으로 실행한다.
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

# 모니터링 대상에 포함시키기 위해 cAdvisor를 자동으로 실행한다.
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
