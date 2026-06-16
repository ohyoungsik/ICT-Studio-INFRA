#!/usr/bin/env bash

# ---------------------------------------------------------------------------
# PostgreSQL 백업 스크립트
# ---------------------------------------------------------------------------
# 역할:
# 1. HAProxy PostgreSQL 엔드포인트에 접속한다.
# 2. ticketing 데이터베이스를 pg_dump로 SQL 파일로 만든다.
# 3. 생성된 dump 파일을 로컬 backup 디렉터리에 저장한다.
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
# 예: PGHOST=localhost PGPORT=5432 ./scripts/backup.sh
PGHOST="${PGHOST:-advancedproject}"
PGPORT="${PGPORT:-5432}"
PGDATABASE="${PGDATABASE:-ticketing}"
PGUSER="${PGUSER:-postgres}"
PGPASSWORD="${PGPASSWORD:-postgres_password}"

# 백업 파일을 저장할 로컬 디렉터리이다.
# 향후 S3 업로드를 추가하더라도 먼저 이 디렉터리에 dump 파일을 만든 뒤 업로드하면 된다.
BACKUP_DIR="${BACKUP_DIR:-${PROJECT_ROOT}/backup}"

# 파일명에 사용할 timestamp이다.
# 요구사항 형식: ticketing_YYYYMMDD_HHMMSS.sql
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
BACKUP_FILE="${BACKUP_DIR}/${PGDATABASE}_${TIMESTAMP}.sql"

# pg_dump 명령이 현재 실행 환경에 있는지 확인한다.
# pg_dump가 없다면 PostgreSQL 클라이언트 도구가 설치된 서버나 컨테이너에서 실행해야 한다.
if ! command -v pg_dump >/dev/null 2>&1; then
    echo "오류: pg_dump 명령을 찾을 수 없습니다."
    echo "PostgreSQL 클라이언트 도구가 설치된 환경에서 다시 실행하세요."
    exit 1
fi

# 백업 디렉터리가 없으면 생성한다.
mkdir -p "${BACKUP_DIR}"

echo "PostgreSQL 백업을 시작합니다."
echo "접속 대상: ${PGHOST}:${PGPORT}/${PGDATABASE}"
echo "백업 파일: ${BACKUP_FILE}"

# PGPASSWORD는 psql 계열 도구가 읽는 표준 환경 변수이다.
# 비밀번호를 명령 인자에 직접 넣지 않아 process list 노출을 줄인다.
export PGPASSWORD

# plain SQL 형식으로 dump를 생성한다.
# --clean과 --if-exists를 사용해 restore 시 기존 객체가 있으면 먼저 정리할 수 있게 한다.
# --no-owner는 다른 환경에서 복구할 때 role 소유권 문제를 줄인다.
pg_dump \
    --host="${PGHOST}" \
    --port="${PGPORT}" \
    --username="${PGUSER}" \
    --dbname="${PGDATABASE}" \
    --format=plain \
    --clean \
    --if-exists \
    --no-owner \
    --file="${BACKUP_FILE}"

echo "백업이 완료되었습니다."
echo "${BACKUP_FILE}"
