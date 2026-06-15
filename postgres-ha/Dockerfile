# ---------------------------------------------------------------------------
# PostgreSQL HA Custom Image Template
# ---------------------------------------------------------------------------
# 이 Dockerfile은 GitHub Actions나 사내 CI/CD에서 커스텀 이미지를 만들 때 사용하는 예시이다.
# stack.yml은 docker stack deploy 1회 실행을 위해 사전 빌드된 bitnamilegacy/postgresql-repmgr:16 이미지를 직접 사용한다.
# 운영에서는 이 Dockerfile로 이미지를 빌드하고, 보안 스캔 후 registry에 push한 뒤 stack.yml의 image 값을 교체한다.
# ---------------------------------------------------------------------------

# repmgr가 포함된 PostgreSQL 16 이미지를 기반으로 사용한다.
# 직접 postgres:16에서 repmgr를 설치하는 방식보다 entrypoint와 repmgr daemon 연동이 검증되어 있다.
FROM bitnamilegacy/postgresql-repmgr:16

# root 권한은 진단 도구 설치에만 사용한다.
# 운영 이미지에서는 필요한 도구만 최소화해 이미지 공격면을 줄인다.
USER root

# 장애 분석과 네트워크 점검에 필요한 최소 도구를 추가한다.
# - ca-certificates: TLS 인증서 검증에 필요
# - curl: health endpoint나 외부 API 점검에 사용
# - iputils-ping: Swarm overlay network 확인에 사용
# - netcat-openbsd: 포트 연결 확인에 사용
# - procps: 프로세스 상태 확인에 사용
RUN install_packages \
        ca-certificates \
        curl \
        iputils-ping \
        netcat-openbsd \
        procps

# init.sql은 PostgreSQL 최초 초기화 시 실행된다.
# stack.yml에서는 Swarm config로 주입하지만, 커스텀 이미지 배포를 선택할 경우에도 동일한 SQL을 포함할 수 있다.
COPY init.sql /docker-entrypoint-initdb.d/01-init.sql

# Bitnami 계열 이미지는 비root 사용자 1001로 실행하는 것이 기본이다.
# root로 계속 실행하지 않아 컨테이너 권한을 낮춘다.
USER 1001

# PostgreSQL 표준 포트이다.
EXPOSE 5432
