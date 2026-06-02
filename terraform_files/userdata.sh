#!/bin/bash
set -e

# Docker와 docker-compose 설치
apt update -y
apt install -y docker.io docker-compose-plugin

# Docker 활성화 및 시작
systemctl enable docker
systemctl start docker

# 애플리케이션 디렉토리 생성
mkdir -p /opt/app
cd /opt/app

# 기존 서비스 우아한 종료 (멱등성 보장)
# 서비스가 없어도 계속 진행
docker compose down || true

# 최신 이미지 다운로드
docker compose pull || true

# 백그라운드 모드로 서비스 시작
docker compose up -d

echo "애플리케이션 배포 완료"
