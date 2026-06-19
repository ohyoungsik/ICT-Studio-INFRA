#!/bin/bash
set -euo pipefail

exec > >(tee /var/log/db-main-userdata.log) 2>&1

NAME_PREFIX="${name_prefix}"
AWS_REGION="${aws_region}"
DB_NAME="${db_name}"
DB_USER="${db_user}"
DB_PASSWORD="${db_password}"
SSM_DB_HOST="/$${NAME_PREFIX}/db/host"
SSM_DB_PORT="/$${NAME_PREFIX}/db/port"
SSM_DB_NAME="/$${NAME_PREFIX}/db/name"
SSM_DB_USER="/$${NAME_PREFIX}/db/user"
SSM_DB_PASSWORD="/$${NAME_PREFIX}/db/password"

log() {
  echo "[$(date -Is)] $*"
}

get_imds_token() {
  curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"
}

install_aws_cli() {
  if command -v aws >/dev/null 2>&1; then
    return
  fi
  apt-get update -y
  apt-get install -y awscli
}

publish_db_ssm() {
  local private_ip token

  token="$(get_imds_token)"
  private_ip="$(curl -sf -H "X-aws-ec2-metadata-token: $token" \
    http://169.254.169.254/latest/meta-data/local-ipv4)"

  log "Publishing DB connection info to SSM (host=$private_ip db=$DB_NAME user=$DB_USER)"

  aws ssm put-parameter \
    --region "$AWS_REGION" \
    --name "$SSM_DB_HOST" \
    --value "$private_ip" \
    --type String \
    --overwrite

  aws ssm put-parameter \
    --region "$AWS_REGION" \
    --name "$SSM_DB_PORT" \
    --value "5432" \
    --type String \
    --overwrite

  aws ssm put-parameter \
    --region "$AWS_REGION" \
    --name "$SSM_DB_NAME" \
    --value "$DB_NAME" \
    --type String \
    --overwrite

  aws ssm put-parameter \
    --region "$AWS_REGION" \
    --name "$SSM_DB_USER" \
    --value "$DB_USER" \
    --type String \
    --overwrite

  aws ssm put-parameter \
    --region "$AWS_REGION" \
    --name "$SSM_DB_PASSWORD" \
    --value "$DB_PASSWORD" \
    --type SecureString \
    --overwrite
}

log "Starting DB main bootstrap"

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

install_aws_cli

mkdir -p /opt/postgres/data
cat > /opt/postgres/init.sql <<'DBINIT'
${db_init_sql}
DBINIT

if docker ps -a --format '{{.Names}}' | grep -qx postgres-main; then
  log "PostgreSQL container already exists"
  if ! docker ps --format '{{.Names}}' | grep -qx postgres-main; then
    docker start postgres-main
  fi
else
  log "Starting PostgreSQL container"
  docker run -d \
    --name postgres-main \
    --restart unless-stopped \
    -e POSTGRES_DB="$DB_NAME" \
    -e POSTGRES_USER="$DB_USER" \
    -e POSTGRES_PASSWORD="$DB_PASSWORD" \
    -v /opt/postgres/data:/var/lib/postgresql/data \
    -v /opt/postgres/init.sql:/docker-entrypoint-initdb.d/01-init.sql:ro \
    -p 5432:5432 \
    postgres:15
fi

for attempt in $(seq 1 60); do
  if docker exec postgres-main pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
    log "PostgreSQL is ready"
    break
  fi
  sleep 2
done

publish_db_ssm

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

log "DB main bootstrap finished"
