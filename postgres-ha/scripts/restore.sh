#!/usr/bin/env bash

# ---------------------------------------------------------------------------
# PostgreSQL 복구 스크립트
# ---------------------------------------------------------------------------
# 역할:
# 1. 사용자가 지정한 dump 파일을 확인한다.
# 2. HAProxy PostgreSQL 엔드포인트에 접속한다.
# 3. SQL dump 파일이면 psql로 복구한다.
# 4. custom/tar/directory dump 파일이면 pg_restore로 복구한다.
#
# 기본 실행:
#   ./scripts/restore.sh backup/ticketing_20260615_120000.sql
#
# 주의:
# - 복구는 현재 Primary에 쓰기 작업을 수행한다.
# - 운영 환경에서는 복구 전에 반드시 최신 백업과 점검 시간을 확보해야 한다.
# ---------------------------------------------------------------------------

set -euo pipefail

# 복구할 dump 파일 경로가 인자로 전달되었는지 확인한다.
if [ "$#" -ne 1 ]; then
    echo "사용법: $0 backup/<dump-file>"
    echo "예시: $0 backup/ticketing_20260615_120000.sql"
    exit 1
fi

DUMP_FILE="$1"

# 지정한 파일이 실제로 존재하는지 확인한다.
if [ ! -f "${DUMP_FILE}" ]; then
    echo "오류: dump 파일을 찾을 수 없습니다: ${DUMP_FILE}"
    exit 1
fi

# PostgreSQL 접속 정보이다.
# 필요하면 실행 시 환경 변수로 덮어쓸 수 있다.
# 예: PGHOST=localhost PGPORT=5432 ./scripts/restore.sh backup/file.sql
PGHOST="${PGHOST:-advancedproject}"
PGPORT="${PGPORT:-5432}"
PGDATABASE="${PGDATABASE:-ticketing}"
PGUSER="${PGUSER:-postgres}"
PGPASSWORD="${PGPASSWORD:-postgres_password}"

# psql 명령은 plain SQL dump 복구에 필요하다.
if ! command -v psql >/dev/null 2>&1; then
    echo "오류: psql 명령을 찾을 수 없습니다."
    echo "PostgreSQL 클라이언트 도구가 설치된 환경에서 다시 실행하세요."
    exit 1
fi

echo "PostgreSQL 복구를 시작합니다."
echo "접속 대상: ${PGHOST}:${PGPORT}/${PGDATABASE}"
echo "복구 파일: ${DUMP_FILE}"

# PGPASSWORD는 psql/pg_restore가 읽는 표준 환경 변수이다.
# 비밀번호를 명령 인자에 직접 넣지 않아 process list 노출을 줄인다.
export PGPASSWORD

# 파일 확장자가 .sql이면 plain SQL dump로 보고 psql을 사용한다.
# 그 외 형식은 pg_dump -Fc 같은 custom 형식일 수 있으므로 pg_restore를 사용한다.
case "${DUMP_FILE}" in
    *.sql)
        psql \
            --host="${PGHOST}" \
            --port="${PGPORT}" \
            --username="${PGUSER}" \
            --dbname="${PGDATABASE}" \
            --file="${DUMP_FILE}"
        ;;
    *)
        if ! command -v pg_restore >/dev/null 2>&1; then
            echo "오류: pg_restore 명령을 찾을 수 없습니다."
            echo "custom/tar/directory dump 복구에는 pg_restore가 필요합니다."
            exit 1
        fi

        pg_restore \
            --host="${PGHOST}" \
            --port="${PGPORT}" \
            --username="${PGUSER}" \
            --dbname="${PGDATABASE}" \
            --clean \
            --if-exists \
            --no-owner \
            "${DUMP_FILE}"
        ;;
esac

echo "복구가 완료되었습니다."
