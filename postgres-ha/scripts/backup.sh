#!/usr/bin/env bash

# ---------------------------------------------------------------------------
# PostgreSQL 컨테이너 기반 백업 스크립트
# ---------------------------------------------------------------------------
# 역할:
# 1. Swarm의 PostgreSQL 서비스 컨테이너를 순회한다.
# 2. 컨테이너 내부에서 pg_is_in_recovery()가 false인 Active Primary를 찾는다.
# 3. Active Primary 컨테이너 내부에서 pg_dump를 실행한다.
# 4. 생성된 dump 파일을 로컬 backup 디렉터리에 저장한다.
#
# 기본 실행:
#   ./scripts/backup.sh
#
# 생성 예시:
#   backup/ticketing_20260615_120000.sql
#
# 운영 확장 방향:
# - 현재는 로컬 backup 디렉터리에 저장한다.
# - 향후 Terraform으로 AWS S3 Bucket과 IAM Role을 만든 뒤,
#   이 스크립트 마지막 단계에 aws s3 cp 명령을 추가하면 된다.
# ---------------------------------------------------------------------------

set -euo pipefail

# 스크립트 위치와 프로젝트 루트 경로를 계산한다.
# 어느 디렉터리에서 실행해도 postgres-ha/backup 아래에 파일이 생성되도록 하기 위함이다.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# PostgreSQL 접속 정보이다.
# 필요하면 실행 시 환경 변수로 덮어쓸 수 있다.
# 예: PGDATABASE=ticketing PGUSER=postgres ./scripts/backup.sh
PGPORT="${PGPORT:-5432}"
PGDATABASE="${PGDATABASE:-ticketing}"
PGUSER="${PGUSER:-postgres}"
PGPASSWORD="${PGPASSWORD:-postgres_password}"

# Docker Swarm stack 이름과 PostgreSQL 서비스 목록이다.
# 서비스명은 stack.yml의 services 키와 일치해야 한다.
STACK_NAME="${STACK_NAME:-postgres-ha}"
POSTGRES_SERVICES=(
    primary
    replica1
    replica2
)

# SSH 접속 사용자이다.
# Active Primary가 현재 VM이 아닌 다른 Swarm 노드에 있으면 SSH로 해당 노드에 접속해 docker exec를 실행한다.
SSH_USER="${SSH_USER:-$(id -un)}"
SSH_OPTS="${SSH_OPTS:-}"

# 백업 파일을 저장할 로컬 디렉터리이다.
# 향후 S3 업로드를 추가하더라도 먼저 이 디렉터리에 dump 파일을 만든 뒤 업로드하면 된다.
BACKUP_DIR="${BACKUP_DIR:-${PROJECT_ROOT}/backup}"

# 파일명에 사용할 timestamp이다.
# 요구사항 형식: ticketing_YYYYMMDD_HHMMSS.sql
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
BACKUP_FILE="${BACKUP_DIR}/${PGDATABASE}_${TIMESTAMP}.sql"

# docker 명령은 Swarm 서비스와 컨테이너 위치를 찾고 docker exec를 실행하는 데 필요하다.
if ! command -v docker >/dev/null 2>&1; then
    echo "오류: docker 명령을 찾을 수 없습니다."
    echo "Docker Swarm manager 또는 Docker CLI 사용 가능 VM에서 실행하세요."
    exit 1
fi

# 현재 VM의 Swarm 노드명이다.
# docker service ps의 Node 값과 비교해 로컬 docker exec 또는 SSH docker exec를 선택한다.
LOCAL_DOCKER_NODE="$(docker info --format '{{.Name}}' 2>/dev/null || hostname)"

build_ssh_target() {
    local node="$1"

    # SSH_USER가 비어 있으면 user@host 형식이 아니라 host만 사용한다.
    if [ -n "${SSH_USER}" ]; then
        printf '%s@%s' "${SSH_USER}" "${node}"
    else
        printf '%s' "${node}"
    fi
}

run_on_node() {
    local node="$1"
    shift

    # 대상 노드가 현재 VM이면 SSH 없이 바로 실행한다.
    if [ "${node}" = "${LOCAL_DOCKER_NODE}" ] || [ "${node}" = "$(hostname)" ]; then
        "$@"
        return
    fi

    local ssh_target
    local remote_command=""
    local quoted_arg

    ssh_target="$(build_ssh_target "${node}")"

    # 원격 shell에서 안전하게 실행되도록 각 인자를 shell escaping한다.
    for arg in "$@"; do
        printf -v quoted_arg '%q' "${arg}"
        remote_command="${remote_command} ${quoted_arg}"
    done

    ssh ${SSH_OPTS} "${ssh_target}" "${remote_command}"
}

get_service_node() {
    local service_name="$1"

    # Swarm service의 실행 중 task가 배치된 노드를 찾는다.
    docker service ps \
        --filter desired-state=running \
        --format '{{.Node}}' \
        "${service_name}" 2>/dev/null | sed -n '1p'
}

get_container_name() {
    local node="$1"
    local service_name="$2"

    # 해당 노드에서 service label을 가진 실행 중 컨테이너 이름을 찾는다.
    run_on_node "${node}" \
        docker ps \
            --filter "label=com.docker.swarm.service.name=${service_name}" \
            --filter "status=running" \
            --format '{{.Names}}' | sed -n '1p'
}

query_recovery_state() {
    local node="$1"
    local container_name="$2"

    # PostgreSQL 컨테이너 내부 psql로 현재 노드가 recovery 중인지 조회한다.
    # false이면 쓰기 가능한 Primary이고 true이면 Replica이다.
    run_on_node "${node}" \
        docker exec \
            -e "PGPASSWORD=${PGPASSWORD}" \
            "${container_name}" \
            psql \
                --host=127.0.0.1 \
                --port="${PGPORT}" \
                --username="${PGUSER}" \
                --dbname=postgres \
                --tuples-only \
                --no-align \
                --command="SELECT CASE WHEN pg_is_in_recovery() THEN 'true' ELSE 'false' END;"
}

find_active_primary() {
    local service
    local service_name
    local node
    local container_name
    local recovery_state

    for service in "${POSTGRES_SERVICES[@]}"; do
        service_name="${STACK_NAME}_${service}"
        node="$(get_service_node "${service_name}")"

        if [ -z "${node}" ]; then
            echo "경고: 실행 중인 Swarm task를 찾지 못했습니다: ${service_name}" >&2
            continue
        fi

        container_name="$(get_container_name "${node}" "${service_name}")"

        if [ -z "${container_name}" ]; then
            echo "경고: 실행 중인 컨테이너를 찾지 못했습니다: ${service_name} on ${node}" >&2
            continue
        fi

        if ! recovery_state="$(query_recovery_state "${node}" "${container_name}" 2>/dev/null)"; then
            echo "경고: recovery 상태 조회 실패: ${service_name} on ${node}" >&2
            continue
        fi

        recovery_state="$(printf '%s' "${recovery_state}" | tr -d '[:space:]')"

        if [ "${recovery_state}" = "false" ]; then
            printf '%s:%s:%s\n' "${service_name}" "${node}" "${container_name}"
            return 0
        fi
    done

    return 1
}

# 백업 디렉터리가 없으면 생성한다.
mkdir -p "${BACKUP_DIR}"

if ! ACTIVE_PRIMARY="$(find_active_primary)"; then
    echo "오류: Active Primary PostgreSQL 컨테이너를 찾지 못했습니다."
    echo "repmgr failover 완료 여부와 docker service 상태를 확인하세요."
    exit 1
fi

PRIMARY_SERVICE="$(printf '%s' "${ACTIVE_PRIMARY}" | cut -d ':' -f 1)"
PRIMARY_NODE="$(printf '%s' "${ACTIVE_PRIMARY}" | cut -d ':' -f 2)"
PRIMARY_CONTAINER="$(printf '%s' "${ACTIVE_PRIMARY}" | cut -d ':' -f 3)"

echo "PostgreSQL 백업을 시작합니다."
echo "Active Primary 서비스: ${PRIMARY_SERVICE}"
echo "Active Primary 노드: ${PRIMARY_NODE}"
echo "Active Primary 컨테이너: ${PRIMARY_CONTAINER}"
echo "백업 파일: ${BACKUP_FILE}"

# Active Primary 컨테이너 내부의 pg_dump를 실행하고 stdout을 로컬 backup 파일로 저장한다.
# --clean과 --if-exists를 사용해 restore 시 기존 객체가 있으면 먼저 정리할 수 있게 한다.
# --no-owner는 다른 환경에서 복구할 때 role 소유권 문제를 줄인다.
run_on_node "${PRIMARY_NODE}" \
    docker exec \
        -e "PGPASSWORD=${PGPASSWORD}" \
        "${PRIMARY_CONTAINER}" \
        pg_dump \
            --host=127.0.0.1 \
            --port="${PGPORT}" \
            --username="${PGUSER}" \
            --dbname="${PGDATABASE}" \
            --format=plain \
            --clean \
            --if-exists \
            --no-owner \
    > "${BACKUP_FILE}"

echo "백업이 완료되었습니다."
echo "${BACKUP_FILE}"
