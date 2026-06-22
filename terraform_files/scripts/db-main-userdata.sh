#!/bin/bash
set -euo pipefail

exec > >(tee /var/log/db-main-userdata.log) 2>&1

log() {
  echo "[$(date -Is)] $*"
}

log "Starting DB main bootstrap"

# db_main is the PostgreSQL HA Docker Swarm manager and HAProxy placement node.
# It must not run the old single postgres-main container because HAProxy uses 5432.
hostnamectl set-hostname "${hostname}"

cat >/etc/hosts.tmp <<EOF
127.0.0.1 localhost
127.0.1.1 ${hostname}
EOF

grep -vE '^(127\.0\.0\.1|127\.0\.1\.1)\s' /etc/hosts >>/etc/hosts.tmp || true
mv /etc/hosts.tmp /etc/hosts

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

mkdir -p /opt/postgres-ha /data/postgres
chown -R 1001:1001 /data/postgres
chmod 700 /data/postgres

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

log "DB main bootstrap finished"
