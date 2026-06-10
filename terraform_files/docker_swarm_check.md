# Docker Swarm 클러스터 확인 (간단)

## 1. 로컬 PC — 접속 준비

```bash
cd /home/ubuntu/ICT-Studio-INFRA/terraform_files
chmod 600 ict-project-key.pem

export BASTION_IP=$(terraform output -raw bastion_public_ip)
export MASTER_IP=$(terraform state show aws_instance.master_node | grep 'private_ip ' | awk -F'"' '{print $2}')
export SSH_KEY="$(pwd)/ict-project-key.pem"

# Bastion 경유 SSH
ssh_private() {
  ssh -i "$SSH_KEY" \
    -o "ProxyCommand=ssh -i ${SSH_KEY} -W %h:%p ubuntu@${BASTION_IP}" \
    "$@"
}
```

## 2. Swarm 클러스터 확인 (핵심)

```bash
# Master에서 노드 목록 확인
ssh_private ubuntu@${MASTER_IP} 'sudo docker node ls'
```

**성공 예시:**

```
ID         HOSTNAME           STATUS   AVAILABILITY   MANAGER STATUS
xxx... *   ip-172-16-20-xxx   Ready    Drain          Leader      ← manager
yyy...     ip-172-16-21-xxx   Ready    Active                     ← worker
```

| 확인 | 성공 기준 |
|------|-----------|
| manager 1줄 | `Leader`, `Drain`, `Ready` |
| worker 1줄 이상 | `Active`, `Ready`, MANAGER STATUS 없음 |

## 3. (선택) ALB까지 확인

```bash
export ALB_DNS=$(terraform output -raw alb_dns_name)
curl -s "http://${ALB_DNS}/health"   # ok
```

## 4. Portainer 외부 접속 (ALB 경유)

Master는 프라이빗 서브넷이지만, ALB `:9000` 리스너가 Manager의 Portainer(HTTP)로 프록시합니다.

```bash
export PORTAINER_URL=$(terraform output -raw portainer_url)
echo "$PORTAINER_URL"

# Health check (Portainer 기동 후)
curl -s "http://${ALB_DNS}:9000/api/status"
```

브라우저에서 `terraform output -raw portainer_url` 주소로 접속합니다.

| 경로 | 용도 |
|------|------|
| ALB `:9000` | 외부 직접 접속 (권장) |
| Bastion SSH 터널 | ALB 없이 관리자 로컬 접속 |
