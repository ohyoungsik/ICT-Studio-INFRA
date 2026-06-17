#!/usr/bin/env bash

# PostgreSQL HA bind mount 데이터 초기화 스크립트.
# Docker Swarm stack을 내린 뒤, 각 노드의 PostgreSQL 데이터 디렉터리를 삭제하고 다시 만든다.
# 직접 실행할 수 있고, 나중에 Ansible task로 옮기기 쉽도록 단계별 함수로 분리했다.

set -euo pipefail

# 환경변수로 값을 넘기면 기본값을 덮어쓸 수 있다.
# 예: STACK_NAME=my-stack DATA_ROOT=/mnt/postgres ./reset-data.sh
STACK_NAME="${STACK_NAME:-postgres-ha}"
DATA_ROOT="${DATA_ROOT:-/data/postgres}"

# 컨테이너 안의 postgres 프로세스가 사용하는 UID/GID에 맞춰 host 디렉터리 소유권을 설정한다.
POSTGRES_UID="${POSTGRES_UID:-1001}"
POSTGRES_GID="${POSTGRES_GID:-1001}"

# sudo 명령이 필요 없는 환경이면 SUDO="" ./reset-data.sh 처럼 실행할 수 있다.
SUDO="${SUDO:-sudo}"

# 원격 노드에 SSH로 접속할 때 사용할 사용자.
# sudo로 실행한 경우에는 원래 사용자(SUDO_USER)를 우선 사용한다.
SSH_USER="${SSH_USER:-${SUDO_USER:-$(id -un)}}"

# SSH 옵션이 필요하면 넘길 수 있다.
# 예: SSH_OPTS="-i ~/.ssh/id_rsa -o StrictHostKeyChecking=no"
SSH_OPTS="${SSH_OPTS:-}"

# docker stack rm 이후 service가 사라질 때까지 기다리는 최대 시간과 확인 주기.
SERVICE_WAIT_TIMEOUT="${SERVICE_WAIT_TIMEOUT:-120}"
SERVICE_WAIT_INTERVAL="${SERVICE_WAIT_INTERVAL:-3}"

# 현재 실행 중인 노드 이름을 확인해서 로컬/원격 처리 방식을 나눈다.
LOCAL_HOSTNAME="$(hostname)"
LOCAL_FQDN="$(hostname -f 2>/dev/null || hostname)"

# 초기화할 데이터 디렉터리 목록.
# 형식: swarm-node-hostname:host-data-dir
# 왼쪽의 노드 이름은 Docker Swarm 노드 hostname과 맞아야 한다.
DATA_DIRS=(
    "projectmain:${DATA_ROOT}/primary"
    "projectrep1:${DATA_ROOT}/replica1"
    "advancedproject:${DATA_ROOT}/replica2"
)

log() {
    printf '[%s] %s
' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

is_local_node() {
    local node="$1"

    # DATA_DIRS의 노드명이 현재 hostname 또는 FQDN과 같으면 로컬 노드로 판단한다.
    [ "${node}" = "${LOCAL_HOSTNAME}" ] || [ "${node}" = "${LOCAL_FQDN}" ]
}

stack_exists() {
    local stack_name="$1"

    # 지정한 이름의 Docker stack이 현재 존재하는지 확인한다.
    docker stack ls --format '{{.Name}}' | grep -Fxq "${stack_name}"
}

stack_services() {
    local stack_name="$1"

    # Docker stack에 속한 service만 label 기준으로 조회한다.
    docker service ls         --filter "label=com.docker.stack.namespace=${stack_name}"         --format '{{.Name}}'
}

remove_stack() {
    if stack_exists "${STACK_NAME}"; then
        # docker stack rm은 비동기로 동작한다.
        # 명령이 끝나도 task/container/network 정리가 아직 진행 중일 수 있다.
        log "Removing Docker stack: ${STACK_NAME}"
        docker stack rm "${STACK_NAME}"
    else
        log "Docker stack not found, skipping removal: ${STACK_NAME}"
    fi
}

wait_for_services_to_stop() {
    local elapsed=0
    local services

    # stack 삭제 이후 service 목록이 완전히 사라질 때까지 기다린다.
    # 데이터 디렉터리를 지우기 전에 컨테이너가 내려갔는지 확인하기 위한 단계다.
    log "Waiting for stack services to stop: ${STACK_NAME}"

    while true; do
        services="$(stack_services "${STACK_NAME}")"

        if [ -z "${services}" ]; then
            log "All stack services are stopped."
            return 0
        fi

        if [ "${elapsed}" -ge "${SERVICE_WAIT_TIMEOUT}" ]; then
            # timeout이 나면 아직 남아 있는 service 이름을 출력하고 실패 처리한다.
            log "Timed out waiting for services to stop:"
            printf '%s
' "${services}"
            return 1
        fi

        log "Still stopping services: ${services//$'
'/, }"
        sleep "${SERVICE_WAIT_INTERVAL}"
        elapsed=$((elapsed + SERVICE_WAIT_INTERVAL))
    done
}

reset_local_data_dir() {
    local data_dir="$1"

    # 로컬 노드의 PostgreSQL 데이터 디렉터리를 삭제 후 재생성한다.
    # rm -rf가 들어 있으므로 DATA_ROOT/DATA_DIRS 값을 바꿀 때는 특히 주의해야 한다.
    log "Resetting local data directory: ${data_dir}"
    ${SUDO} rm -rf "${data_dir}"
    ${SUDO} mkdir -p "${data_dir}"

    # PostgreSQL 컨테이너가 새 디렉터리에 쓸 수 있도록 소유권을 맞춘다.
    ${SUDO} chown -R "${POSTGRES_UID}:${POSTGRES_GID}" "${DATA_ROOT}"
}

reset_remote_data_dir() {
    local node="$1"
    local data_dir="$2"
    local ssh_target

    # SSH_USER가 비어 있지 않으면 user@node 형태로 접속한다.
    if [ -n "${SSH_USER}" ]; then
        ssh_target="${SSH_USER}@${node}"
    else
        ssh_target="${node}"
    fi

    # 원격 노드에서도 로컬과 같은 작업을 SSH로 실행한다.
    # 원격 명령에도 rm -rf가 포함되어 있으므로 DATA_DIRS 값이 정확해야 한다.
    log "Resetting remote data directory: ${node}:${data_dir}"
    ssh ${SSH_OPTS} "${ssh_target}"         "${SUDO} rm -rf '${data_dir}' && ${SUDO} mkdir -p '${data_dir}' && ${SUDO} chown -R '${POSTGRES_UID}:${POSTGRES_GID}' '${DATA_ROOT}'"
}

reset_data_dirs() {
    local item
    local node
    local data_dir

    log "Resetting PostgreSQL bind mount directories."

    # DATA_DIRS 목록을 순회하면서 현재 노드는 직접 처리하고,
    # 다른 노드는 SSH로 접속해서 처리한다.
    for item in "${DATA_DIRS[@]}"; do
        node="${item%%:*}"
        data_dir="${item#*:}"

        if is_local_node "${node}"; then
            reset_local_data_dir "${data_dir}"
        else
            reset_remote_data_dir "${node}" "${data_dir}"
        fi
    done
}

main() {
    # 전체 실행 순서:
    # 1. 기존 Docker stack 삭제 요청
    # 2. stack service가 사라질 때까지 대기
    # 3. 각 노드의 PostgreSQL 데이터 디렉터리 초기화
    log "Starting PostgreSQL HA data reset."
    remove_stack
    wait_for_services_to_stop
    reset_data_dirs
    log "PostgreSQL HA data reset completed."
}

main "$@"
