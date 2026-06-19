# ICT Studio Infra

ICT Studio 서비스의 AWS 인프라를 Terraform으로 관리하는 저장소입니다.

이 프로젝트는 백엔드 API 서버, Redis 대기열, 모니터링, ALB, Auto Scaling Group, DB 서버를 AWS 위에 구성합니다.

## 전체 구조

```text
사용자
  -> ALB
  -> Auto Scaling Group의 app 서버
  -> Redis 대기열 / DB 서버

운영자
  -> Bastion
  -> Grafana / Prometheus / Loki
  -> Portainer
```

## 주요 구성 요소

```text
VPC
- public subnet
- private app subnet
- db subnet
- NAT Gateway

ALB
- HTTP 80: 백엔드 API로 라우팅
- HTTP 9000: Portainer UI로 라우팅

App Server
- Auto Scaling Group으로 관리
- Docker 컨테이너로 백엔드 실행
- Redis 설정은 SSM Parameter Store에서 조회

Master Node
- Docker Swarm manager
- Redis 실행
- Redis exporter 실행
- Redis queue length를 CloudWatch metric으로 발행

Bastion
- Grafana
- Prometheus
- Loki
- Alertmanager

DB
- PostgreSQL 컨테이너 기반 DB 서버
```

## 디렉터리 구조

```text
bootstrap/
  Terraform backend용 S3 bucket을 준비하는 코드

terraform_files/
  실제 AWS 인프라를 생성하는 Terraform 코드

scripts/
  EC2 초기화, Docker/Redis/Portainer 설정 스크립트

docs/
  테스트, 개선안, 운영 참고 문서
```

## 배포 순서

처음 배포할 때는 backend bucket을 먼저 준비합니다.

```powershell
.\scripts\init-backend.ps1
```

그 다음 Terraform을 실행합니다.

```powershell
terraform -chdir=terraform_files init
terraform -chdir=terraform_files plan
terraform -chdir=terraform_files apply
```

## 주요 출력값

배포 후 아래 정보를 확인합니다.

```powershell
terraform -chdir=terraform_files output
```

자주 보는 값:

```text
alb_dns_name
portainer_url
bastion_public_ip
master_node_private_ip
asg_name
app_instance_private_ips
```

## 모니터링

```text
Grafana    : http://BASTION_PUBLIC_IP:3000
Prometheus : http://BASTION_PUBLIC_IP:9090
Portainer  : http://ALB_DNS:9000
```

Prometheus는 EC2 service discovery로 app, db, redis exporter를 수집합니다.

## 오토스케일링

현재 app 서버 ASG는 두 가지 기준을 사용합니다.

```text
1. CPU 기반
   - ASGAverageCPUUtilization 70%

2. Redis 큐 길이 기반
   - CloudWatch custom metric: ICT/Queue
   - Metric: QueueLengthPerInstanceForAsg
   - Target: 3000
```

큐 길이 기반 오토스케일링 흐름:

```text
k6 요청 증가
-> Redis 대기열 길이 증가
-> master node의 queue metric publisher가 CloudWatch에 metric 발행
-> ASG target tracking policy가 감지
-> app 인스턴스 scale-out
```

Scale-In 검증은 선택형 queue consumer로 진행합니다.

```text
enable_queue_consumer = false
```

기본값은 비활성화입니다. Scale-out을 먼저 확인한 뒤, scale-in 검증 시에만 켜는 것을 권장합니다.
consumer는 master node에서 `/api/queue/worker`를 주기적으로 호출해 Redis queue length를 감소시킵니다.

Scale-Out 검증 순서:

```text
1. enable_queue_consumer = false 유지
2. k6로 /api/queue/join 요청 증가
3. Redis queue length 증가 확인
4. CloudWatch QueueLengthPerInstanceForAsg metric 증가 확인
5. ASG desired capacity / in-service instance 증가 확인
```

Scale-In 검증 순서:

```text
1. Scale-out 확인 후 enable_queue_consumer = true 적용
2. master node의 queue consumer가 /api/queue/worker 주기 호출
3. Redis queue length 감소 확인
4. CloudWatch QueueLengthPerInstanceForAsg metric 감소 확인
5. ASG cooldown 이후 desired capacity 감소 확인
```

자세한 검증 기록과 명령어는 `docs/queue-autoscaling-validation.md`를 참고합니다.

확인 명령:

```powershell
aws cloudwatch get-metric-statistics `
  --namespace ICT/Queue `
  --metric-name QueueLengthPerInstanceForAsg `
  --statistics Average `
  --period 60 `
  --start-time 2026-06-17T08:20:00Z `
  --end-time 2026-06-17T08:50:00Z `
  --region ap-northeast-2
```

```powershell
aws autoscaling describe-scaling-activities `
  --auto-scaling-group-name prod-ict-app-asg `
  --region ap-northeast-2 `
  --max-items 10
```

## 부하 테스트 참고

백엔드 k6 스크립트는 별도 백엔드 저장소에 있습니다.

[ohyoungsik/ICT-Studio-BE](https://github.com/ohyoungsik/ICT-Studio-BE)

실행 예시:

```powershell
k6 run --vus 500 --duration 3m `
  -e BASE_URL=http://ALB_DNS `
  .\k6\ticketing-load-test.js
```

대기열 초과 정책에서는 `429`가 정상 응답일 수 있습니다.
따라서 k6 결과는 `server_errors`, `checks`, 상태 코드 분포를 함께 봐야 합니다.

## 주의 사항

```text
terraform destroy는 EC2, Redis, DB, 모니터링 데이터를 삭제할 수 있습니다.
테스트 데이터 보존이 필요 없다면 destroy 후 재배포가 가능하지만,
운영 데이터가 있으면 apply 중심으로 변경하는 것이 안전합니다.
```

```text
ASG에서 새 인스턴스가 생겼다고 모두 scale-out은 아닙니다.
Cause가 ELB health check failure 또는 instance refresh면 교체 작업입니다.
진짜 scale-out은 desired capacity가 증가해야 합니다.
```

## PostgreSQL HA DB Layer 자동화

DB Layer는 `postgres-ha` 구현을 재사용해 PostgreSQL 데이터 노드 3대와 HAProxy/Swarm manager 노드 1대로 배포합니다. PostgreSQL 노드는 Stateful 서비스이므로 ASG나 Launch Template 기반 자동 증설 대상이 아닙니다.

```text
db_main           - Docker Swarm manager, HAProxy endpoint
postgres-primary  - Docker Swarm worker, PostgreSQL primary
postgres-replica1 - Docker Swarm worker, PostgreSQL replica1
postgres-replica2 - Docker Swarm worker, PostgreSQL replica2
```

### AWS Credential 준비

```bash
aws configure
```

CI에서는 AWS credential을 GitHub Actions secret 또는 OIDC 방식으로 제공합니다.

### SSH Key 준비

Terraform이 EC2 key pair와 로컬 pem 파일을 생성합니다.

```bash
cd terraform_files
terraform apply
ls -l ict-project-key.pem
```

### Terraform 실행

```bash
cd terraform_files
terraform init
terraform plan
terraform apply
```

주요 출력값:

```bash
terraform output postgres_primary_private_ip
terraform output postgres_replica1_private_ip
terraform output postgres_replica2_private_ip
terraform output postgres_ha_haproxy_endpoint
```

### Ansible 실행

```bash
cd ../ansible_files
ansible-inventory --list
ansible-playbook playbooks/deploy.yml
```

검증:

```bash
ansible-playbook playbooks/verify.yml
```

전체 흐름은 다음과 같습니다.

```text
Terraform
-> EC2 생성
-> Docker 설치
-> Swarm 구성
-> PostgreSQL HA 배포
```

