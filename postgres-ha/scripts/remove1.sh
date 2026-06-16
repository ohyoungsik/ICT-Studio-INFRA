#!/usr/bin/env bash

# ---------------------------------------------------------------------------

# PostgreSQL 데이터 디렉터리 초기화 스크립트

# ---------------------------------------------------------------------------

# 목적

#

# Primary / Replica 노드의 bind mount 디렉터리를 모두 비운다.

#

# 사용 시점

#

# - Replication 구성이 꼬였을 때

# - 기존 데이터 때문에 Replica Clone이 수행되지 않을 때

# - Docker Stack을 처음부터 다시 배포할 때

#

# 주의

#

# 이 스크립트는 PostgreSQL 데이터를 영구 삭제한다.

# 운영 환경에서는 절대 사용하지 않는다.

# ---------------------------------------------------------------------------

set -euo pipefail

SSH_USER="${SSH_USER:-$(id -un)}"
SSH_OPTS="${SSH_OPTS:-}"

NODES=(
"projectmain:/data/postgres/primary"
"projectrep1:/data/postgres/replica1"
"advancedproject:/data/postgres/replica2"
)

echo
echo "========================================"
echo " PostgreSQL 데이터 디렉터리 초기화"
echo "========================================"
echo
echo "모든 PostgreSQL 데이터가 삭제됩니다."
echo

read -rp "계속 진행하시겠습니까? (yes 입력): " ANSWER

if [ "${ANSWER}" != "yes" ]; then
echo "작업 취소"
exit 0
fi

for item in "${NODES[@]}"; do

NODE="${item%%:*}"
DATA_DIR="${item#*:}"

echo
echo "----------------------------------------"
echo "노드 : ${NODE}"
echo "경로 : ${DATA_DIR}"
echo "----------------------------------------"

ssh ${SSH_OPTS} "${SSH_USER}@${NODE}" "
    sudo systemctl status docker >/dev/null 2>&1 || true

    echo '[INFO] 기존 데이터 확인'
    sudo ls -al ${DATA_DIR} || true

    echo '[INFO] PostgreSQL 데이터 삭제'
    sudo rm -rf ${DATA_DIR:?}/*

    echo '[INFO] 삭제 완료'
    sudo ls -al ${DATA_DIR}
"

done

echo
echo "========================================"
echo "모든 PostgreSQL 데이터 삭제 완료"
echo "========================================"
echo
echo "이후 순서"
echo
echo "1. docker stack rm postgres-ha"
echo "2. 데이터 디렉터리 비어있는지 확인"
echo "3. docker stack deploy -c stack.yml postgres-ha"
echo "4. Replica Clone 정상 수행 여부 확인"
echo
