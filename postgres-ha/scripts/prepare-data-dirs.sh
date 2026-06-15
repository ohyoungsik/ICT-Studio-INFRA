#!/usr/bin/env bash

# ---------------------------------------------------------------------------
# PostgreSQL bind mount 데이터 디렉터리 준비 스크립트
# ---------------------------------------------------------------------------
# 역할:
# 1. PostgreSQL이 배치될 각 Swarm 노드에 접속한다.
# 2. bind mount에 사용할 host path를 생성한다.
# 3. Bitnami PostgreSQL 컨테이너 사용자(1001)가 쓸 수 있도록 소유권과 권한을 설정한다.
#
# 기본 실행:
#   ./scripts/prepare-data-dirs.sh
#
# 기본 대상:
#   projectmain      -> /data/postgres/primary
#   projectrep1      -> /data/postgres/replica1
#   advancedproject  -> /data/postgres/replica2
#
# 실행 전제:
# - 이 스크립트를 실행하는 서버에서 각 노드로 SSH 접속이 가능해야 한다.
# - 원격 노드에서 sudo 명령을 실행할 수 있어야 한다.
# - 현재 실행 중인 서버가 대상 노드와 같으면 SSH 없이 로컬에서 실행한다.
# ---------------------------------------------------------------------------

set -euo pipefail

# Bitnami PostgreSQL 컨테이너는 기본적으로 uid/gid 1001 사용자를 사용한다.
POSTGRES_UID="${POSTGRES_UID:-1001}"
POSTGRES_GID="${POSTGRES_GID:-1001}"

# sudo 명령이 필요 없는 환경이면 SUDO="" 로 실행할 수 있다.
# 예: SUDO="" ./scripts/prepare-data-dirs.sh
SUDO="${SUDO:-sudo}"

# SSH 접속 사용자이다.
# 기본값은 현재 로컬 사용자이며, 필요하면 SSH_USER로 변경한다.
# 예: SSH_USER=ubuntu ./scripts/prepare-data-dirs.sh
SSH_USER="${SSH_USER:-$(id -un)}"

# ssh 옵션이 필요하면 문자열로 전달한다.
# 예: SSH_OPTS="-i ~/.ssh/key.pem" ./scripts/prepare-data-dirs.sh
SSH_OPTS="${SSH_OPTS:-}"

# 현재 호스트 이름이다.
# 대상 노드와 같으면 SSH 대신 로컬 명령으로 실행한다.
LOCAL_HOSTNAME="$(hostname)"
LOCAL_FQDN="$(hostname -f 2>/dev/null || hostname)"

# 노드와 데이터 디렉터리 매핑이다.
# stack.yml의 placement constraint 및 bind mount 경로와 반드시 일치해야 한다.
NODES=(
    "projectmain:/data/postgres/primary"
    "projectrep1:/data/postgres/replica1"
    "advancedproject:/data/postgres/replica2"
)

run_prepare_command() {
    local data_dir="$1"

    # 디렉터리를 만들고 PostgreSQL 컨테이너 사용자에게 소유권을 부여한다.
    # chmod 700은 DB 데이터 디렉터리를 다른 사용자에게 노출하지 않기 위한 기본 권한이다.
    ${SUDO} mkdir -p "${data_dir}"
    ${SUDO} chown -R "${POSTGRES_UID}:${POSTGRES_GID}" "${data_dir}"
    ${SUDO} chmod 700 "${data_dir}"
}

run_remote_prepare_command() {
    local node="$1"
    local data_dir="$2"
    local ssh_target

    if [ -n "${SSH_USER}" ]; then
        ssh_target="${SSH_USER}@${node}"
    else
        ssh_target="${node}"
    fi

    # 원격 서버에서 실행할 명령이다.
    # 경로 값은 이 스크립트의 고정 매핑에서만 오므로 그대로 사용한다.
    ssh ${SSH_OPTS} "${ssh_target}" \
        "${SUDO} mkdir -p '${data_dir}' && ${SUDO} chown -R '${POSTGRES_UID}:${POSTGRES_GID}' '${data_dir}' && ${SUDO} chmod 700 '${data_dir}'"
}

echo "PostgreSQL bind mount 데이터 디렉터리 준비를 시작합니다."

for item in "${NODES[@]}"; do
    node="${item%%:*}"
    data_dir="${item#*:}"

    echo "대상 노드: ${node}"
    echo "데이터 디렉터리: ${data_dir}"

    if [ "${node}" = "${LOCAL_HOSTNAME}" ] || [ "${node}" = "${LOCAL_FQDN}" ]; then
        echo "현재 호스트와 대상 노드가 같아 로컬에서 실행합니다."
        run_prepare_command "${data_dir}"
    else
        echo "SSH로 대상 노드에 접속해 실행합니다."
        run_remote_prepare_command "${node}" "${data_dir}"
    fi

    echo "완료: ${node}:${data_dir}"
done

echo "모든 PostgreSQL 데이터 디렉터리 준비가 완료되었습니다."
