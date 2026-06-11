#!/bin/bash
# Docker Swarm Manager 노드에서 Portainer 스택 배포 스크립트
# 사용 시점: master-node-bootstrap 완료 후, worker 노드가 Swarm에 join된 뒤 실행
#
# 예시 (Bastion 경유 SSH):
#   sudo bash /path/to/portainer-init.sh

set -euo pipefail

exec > >(tee /var/log/portainer-init.log) 2>&1

STACK_NAME="${STACK_NAME:-portainer}"
STACK_DIR="/opt/portainer"
STACK_FILE="${STACK_DIR}/portainer-agent-stack.yml"
# manager bootstrap에서 drain 설정된 상태에서도 Portainer가 스케줄되도록 잠시 active로 전환
RESTORE_MANAGER_DRAIN="${RESTORE_MANAGER_DRAIN:-true}"
# worker join 대기 (agent global 배포를 위해 최소 1대 권장)
WAIT_FOR_WORKERS="${WAIT_FOR_WORKERS:-true}"
MAX_WORKER_WAIT_RETRIES="${MAX_WORKER_WAIT_RETRIES:-30}"
WORKER_WAIT_INTERVAL="${WORKER_WAIT_INTERVAL:-10}"
MAX_SERVICE_WAIT_RETRIES="${MAX_SERVICE_WAIT_RETRIES:-30}"
SERVICE_WAIT_INTERVAL="${SERVICE_WAIT_INTERVAL:-10}"
PORTAINER_VERSION="${PORTAINER_VERSION:-2.21.5}"

log() {
  echo "[$(date -Is)] $*"
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log "ERROR: This script must be run as root (e.g. sudo bash portainer-init.sh)"
    exit 1
  fi
}

require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log "ERROR: Docker is not installed. Run master-node-bootstrap.sh first."
    exit 1
  fi

  if ! systemctl is-active --quiet docker; then
    log "Starting Docker daemon"
    systemctl start docker
  fi
}

require_swarm_manager() {
  local swarm_state control_available

  swarm_state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo inactive)"
  if [[ "$swarm_state" != "active" ]]; then
    log "ERROR: This node is not part of an active Swarm cluster"
    exit 1
  fi

  control_available="$(docker info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null || echo false)"
  if [[ "$control_available" != "true" ]]; then
    log "ERROR: This node is not a Swarm manager"
    exit 1
  fi
}

get_manager_node_id() {
  docker info --format '{{.Swarm.NodeID}}'
}

ensure_manager_active_for_portainer() {
  local node_id availability

  node_id="$(get_manager_node_id)"
  availability="$(docker node inspect "$node_id" --format '{{.Spec.Availability}}')"

  if [[ "$availability" == "active" ]]; then
    log "Manager node already active"
    return
  fi

  log "Setting manager availability to active for Portainer scheduling (was: $availability)"
  docker node update --availability active "$node_id"
}

restore_manager_drain_if_needed() {
  local node_id

  if [[ "$RESTORE_MANAGER_DRAIN" != "true" ]]; then
    log "Skipping manager drain restore (RESTORE_MANAGER_DRAIN=false)"
    return
  fi

  node_id="$(get_manager_node_id)"
  log "Restoring manager availability to drain"
  docker node update --availability drain "$node_id"
}

wait_for_workers() {
  local attempt worker_count

  if [[ "$WAIT_FOR_WORKERS" != "true" ]]; then
    log "Skipping worker wait (WAIT_FOR_WORKERS=false)"
    return
  fi

  for attempt in $(seq 1 "$MAX_WORKER_WAIT_RETRIES"); do

    worker_count=$(
      docker node ls \
      --format '{{.Status}} {{.Availability}} {{.ManagerStatus}}' |
      awk '
        $3 == "" && $1 == "Ready" && $2 == "Active" { count++ }
        END { print count+0 }
      '
    )

    if [[ "$worker_count" -ge 1 ]]; then
      log "Found $worker_count Ready worker node(s)"
      return
    fi

    log "Waiting for Ready worker nodes ($attempt/$MAX_WORKER_WAIT_RETRIES)"
    sleep "$WORKER_WAIT_INTERVAL"
  done

  log "WARNING: No Ready worker nodes detected. Continuing deployment."
}

write_stack_file() {
  mkdir -p "$STACK_DIR"

  cat > "$STACK_FILE" <<EOF
version: '3.2'

services:
  agent:
    image: portainer/agent:${PORTAINER_VERSION}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    networks:
      - agent_network
    deploy:
      mode: global
      placement:
        constraints: [node.platform.os == linux]

  portainer:
    image: portainer/portainer-ce:${PORTAINER_VERSION}
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    ports:
      - "9443:9443"
      - "9000:9000"
      - "8000:8000"
    volumes:
      - portainer_data:/data
    networks:
      - agent_network
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints: [node.role == manager]

networks:
  agent_network:
    driver: overlay
    attachable: true

volumes:
  portainer_data:
EOF

  log "Wrote stack file to $STACK_FILE (version=${PORTAINER_VERSION})"
}

deploy_portainer_stack() {
  if docker stack ls --format '{{.Name}}' | grep -Fxq "$STACK_NAME"; then
    log "Updating existing stack: $STACK_NAME"
  else
    log "Deploying new stack: $STACK_NAME"
  fi

  docker stack deploy --compose-file "$STACK_FILE" --with-registry-auth "$STACK_NAME"
}

wait_for_service_replicas() {
  local service="$1" expected="$2" attempt replicas

  for attempt in $(seq 1 "$MAX_SERVICE_WAIT_RETRIES"); do
    replicas="$(docker service ls --filter "name=${STACK_NAME}_${service}" --format '{{.Replicas}}' 2>/dev/null || true)"
    if [[ "$replicas" == "$expected" ]]; then
      log "Service ${STACK_NAME}_${service} is ready ($replicas)"
      return 0
    fi

    log "Waiting for ${STACK_NAME}_${service} ($attempt/$MAX_SERVICE_WAIT_RETRIES, current=$replicas, expected=$expected)"
    sleep "$SERVICE_WAIT_INTERVAL"
  done

  log "ERROR: Service ${STACK_NAME}_${service} did not reach expected replicas ($expected)"
  docker service ps "${STACK_NAME}_${service}" --no-trunc || true
  return 1
}

wait_for_portainer_services() {
  local node_count expected_agent_replicas

  node_count=$(
    docker node ls \
    --format '{{.Status}} {{.Availability}}' |
    awk '
      $1 == "Ready" && $2 == "Active" { count++ }
      END { print count+0 }
    '
  )

  expected_agent_replicas="${node_count}/${node_count}"

  wait_for_service_replicas "portainer" "1/1"
  wait_for_service_replicas "agent" "$expected_agent_replicas"
}

print_summary() {
  local private_ip token

  token="$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || true)"
  if [[ -n "$token" ]]; then
    private_ip="$(curl -sf -H "X-aws-ec2-metadata-token: $token" \
      http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || true)"
  else
    private_ip="$(hostname -I | awk '{print $1}')"
  fi

  log "Portainer deployment complete"
  log "Stack status:"
  docker stack services "$STACK_NAME"
  log "Access Portainer UI (SSH tunnel via bastion recommended):"
  log "  HTTPS: https://${private_ip}:9443"
  log "  HTTP:  http://${private_ip}:9000"
  log "Edge agent tunnel port: ${private_ip}:8000"
}

log "Starting Portainer init on Swarm manager"
require_root
require_docker
require_swarm_manager
wait_for_workers
ensure_manager_active_for_portainer
write_stack_file
deploy_portainer_stack
wait_for_portainer_services
restore_manager_drain_if_needed
print_summary
log "Portainer init finished"
