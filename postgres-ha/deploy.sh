#!/usr/bin/env bash

# PostgreSQL HA 데이터 초기화 후 Docker Swarm stack을 배포하는 스크립트.
# 직접 실행할 수 있고, 나중에 Ansible task로 옮기기 쉽도록 단계별 함수로 분리했다.

set -euo pipefail

# 환경변수로 값을 넘기면 기본값을 덮어쓸 수 있다.
# 예: STACK_NAME=my-stack STACK_FILE=prod-stack.yml ./deploy.sh
STACK_NAME="${STACK_NAME:-postgres-ha}"
STACK_FILE="${STACK_FILE:-stack.yml}"

# 이 스크립트가 있는 디렉터리를 기준으로 reset-data.sh와 stack.yml을 찾는다.
# 다른 경로에서 실행해도 파일 경로가 꼬이지 않게 하기 위한 처리다.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
    printf '[%s] %s
' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

reset_data() {
    # 기존 PostgreSQL 컨테이너와 bind mount 데이터를 정리한다.
    # 실제 삭제 로직은 reset-data.sh에 있다.
    log "Running data reset script."
    "${SCRIPT_DIR}/reset-data.sh"
}

deploy_stack() {
    # stack.yml을 사용해서 Docker Swarm stack을 배포한다.
    # 이미 같은 이름의 stack이 있으면 Docker가 변경분을 반영한다.
    log "Deploying Docker stack: ${STACK_NAME}"
    docker stack deploy -c "${SCRIPT_DIR}/${STACK_FILE}" "${STACK_NAME}"
}

show_services() {
    # 배포 명령 이후 현재 Swarm service 목록을 보여준다.
    # 서비스가 완전히 healthy 상태가 되었는지는 별도 확인이 필요하다.
    log "Current Docker services:"
    docker service ls
}

main() {
    # 전체 실행 순서:
    # 1. 기존 stack과 PostgreSQL 데이터를 초기화
    # 2. stack.yml로 다시 배포
    # 3. service 목록 출력
    log "Starting PostgreSQL HA deployment."
    reset_data
    deploy_stack
    show_services
    log "PostgreSQL HA deployment command completed."
}

main "$@"
