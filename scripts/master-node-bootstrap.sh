#!/bin/bash
# Docker Swarm manager bootstrap.
# Runs from Terraform user_data:
# install Docker -> initialize Swarm -> publish join info to SSM.

set -euo pipefail

exec > >(tee /var/log/master-node-bootstrap.log) 2>&1

NAME_PREFIX="${name_prefix}"
AWS_REGION="${aws_region}"
SSM_MANAGER_IP="/$${NAME_PREFIX}/swarm/manager-ip"
SSM_WORKER_TOKEN="/$${NAME_PREFIX}/swarm/worker-token"

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

init_swarm() {
  local token private_ip swarm_state node_id

  token="$(get_imds_token)"
  private_ip="$(curl -sf -H "X-aws-ec2-metadata-token: $token" \
    http://169.254.169.254/latest/meta-data/local-ipv4)"

  swarm_state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo inactive)"

  if [[ "$swarm_state" == "active" ]]; then
    log "Swarm already active on this node"
  else
    log "Initializing Docker Swarm on $private_ip"
    docker swarm init --advertise-addr "$private_ip"
  fi

  node_id="$(docker info --format '{{.Swarm.NodeID}}')"
  log "Setting manager availability to drain (manager-only node)"
  docker node update --availability drain "$node_id"

  log "Publishing Swarm join info to SSM"
  aws ssm put-parameter \
    --region "$AWS_REGION" \
    --name "$SSM_MANAGER_IP" \
    --value "$private_ip" \
    --type String \
    --overwrite

  aws ssm put-parameter \
    --region "$AWS_REGION" \
    --name "$SSM_WORKER_TOKEN" \
    --value "$(docker swarm join-token worker -q)" \
    --type SecureString \
    --overwrite

  log "Swarm manager bootstrap complete"
  docker node ls
}

log "Starting master node bootstrap"
install_docker
install_aws_cli
init_swarm
log "Master node bootstrap finished"
