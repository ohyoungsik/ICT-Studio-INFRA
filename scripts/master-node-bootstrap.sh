#!/bin/bash
# Docker Swarm Manager 노드 초기화 스크립트
# Terraform user_data로 실행되며, Docker 설치 → swarm init → SSM에 join 정보 저장

# -e: 명령 실패 시 즉시 종료
# -u: 선언되지 않은 변수 사용 시 오류
# -o pipefail: 파이프라인 중간 명령 실패도 전체 실패로 처리
set -euo pipefail

# 표준 출력/에러를 로그 파일과 콘솔에 동시 기록 (부팅 후 문제 추적용)
exec > >(tee /var/log/master-node-bootstrap.log) 2>&1

# Terraform templatefile이 치환하는 값 (예: prod-ict)
NAME_PREFIX="${name_prefix}"
# AWS 리전 (SSM API 호출 시 필요)
AWS_REGION="${aws_region}"
# SSM Parameter Store 경로 ($$는 Terraform에서 $로 escape)
SSM_MANAGER_IP="/$${NAME_PREFIX}/swarm/manager-ip"
SSM_WORKER_TOKEN="/$${NAME_PREFIX}/swarm/worker-token"

log() {
  # ISO8601 타임스탬프와 함께 로그 출력
  echo "[$(date -Is)] $*"
}

install_docker() {
  # docker 명령이 있으면 재설치하지 않음 (idempotent)
  if command -v docker >/dev/null 2>&1; then
    log "Docker already installed: $(docker --version)"
    return
  fi

  log "Installing Docker Engine"

  # apt 패키지 목록 갱신
  apt-get update -y
  # HTTPS apt 저장소 및 GPG 검증에 필요한 패키지 설치
  apt-get install -y ca-certificates curl gnupg

  # Docker GPG 키 저장 디렉터리 생성 (권한 755)
  install -m 0755 -d /etc/apt/keyrings
  # Docker 공식 GPG 키 다운로드 후 apt keyring 형식으로 저장
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  # 모든 사용자가 keyring 파일 읽기 가능하도록 설정
  chmod a+r /etc/apt/keyrings/docker.gpg

  # Docker 공식 apt 저장소 등록 (Ubuntu codename 자동 감지)
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -y
  # Docker Engine, CLI, containerd 런타임 설치
  apt-get install -y docker-ce docker-ce-cli containerd.io

  # 부팅 시 Docker 자동 시작 등록
  systemctl enable docker
  # Docker 데몬 즉시 시작
  systemctl start docker
}

install_aws_cli() {
  # aws 명령이 있으면 재설치하지 않음
  if command -v aws >/dev/null 2>&1; then
    log "AWS CLI already installed: $(aws --version 2>&1 | head -n1)"
    return
  fi

  log "Installing AWS CLI"
  apt-get update -y
  # SSM Parameter Store API 호출에 사용 (aws ssm put-parameter)
  apt-get install -y awscli
}

get_imds_token() {
  # EC2 Instance Metadata Service(IMDSv2) 세션 토큰 발급
  # 이후 metadata 조회 시 X-aws-ec2-metadata-token 헤더에 사용
  curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"
}

init_swarm() {
  local token private_ip swarm_state node_id

  token="$(get_imds_token)"
  # 이 인스턴스의 프라이빗 IP (swarm init advertise-addr에 사용)
  private_ip="$(curl -sf -H "X-aws-ec2-metadata-token: $token" \
    http://169.254.169.254/latest/meta-data/local-ipv4)"

  # 현재 노드의 Swarm 상태 확인 (inactive / active / pending 등)
  swarm_state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo inactive)"

  if [[ "$swarm_state" == "active" ]]; then
    # 재부팅·재실행 시 중복 init 방지
    log "Swarm already active on this node"
  else
    log "Initializing Docker Swarm on $private_ip"
    # 이 노드를 Swarm manager로 초기화 (클러스터 생성)
    docker swarm init --advertise-addr "$private_ip"
  fi

  # 현재 노드의 Swarm Node ID 조회
  node_id="$(docker info --format '{{.Swarm.NodeID}}')"
  log "Setting manager availability to drain (manager-only node)"
  # manager에서 컨테이너 워크로드 실행하지 않도록 drain 설정
  docker node update --availability drain "$node_id"

  log "Publishing Swarm join info to SSM"
  # worker가 join할 manager IP를 SSM에 저장 (평문 String)
  aws ssm put-parameter \
    --region "$AWS_REGION" \
    --name "$SSM_MANAGER_IP" \
    --value "$private_ip" \
    --type String \
    --overwrite

  # worker join token을 SSM에 암호화 저장 (SecureString)
  aws ssm put-parameter \
    --region "$AWS_REGION" \
    --name "$SSM_WORKER_TOKEN" \
    --value "$(docker swarm join-token worker -q)" \
    --type SecureString \
    --overwrite

  log "Swarm manager bootstrap complete"
  # 클러스터 노드 목록 출력 (부트스트랩 결과 확인)
  docker node ls
}

log "Starting master node bootstrap"
install_docker
install_aws_cli
init_swarm
log "Master node bootstrap finished"
