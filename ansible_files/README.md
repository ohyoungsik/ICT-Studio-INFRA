# PostgreSQL HA Ansible Deployment

이 디렉터리는 `terraform_files`가 생성한 PostgreSQL HA 관련 EC2 4대(db_main + PostgreSQL 데이터 노드 3대)를 대상으로 Docker Swarm과 `postgres-ha` stack을 배포합니다.

## 사전 준비

1. AWS Credential을 준비합니다.

```bash
aws configure
```

또는 GitHub Actions/CI에서는 `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`을 secret/env로 제공합니다.

2. SSH Key는 Terraform이 자동 생성합니다.

```bash
cd ../terraform_files
terraform apply
ls -l ict-project-key.pem
```

`key_name`을 바꿨다면 생성되는 pem 파일명도 바뀝니다. Dynamic inventory가 Terraform output의 `key_pair_name`을 읽어 자동으로 사용합니다.

## Terraform 실행

```bash
cd terraform_files
terraform init
terraform plan
terraform apply
```

Terraform은 다음 DB HA 고정 EC2를 생성합니다.

```text
db_main           - Swarm manager, HAProxy endpoint
postgres-primary  - Swarm worker, PostgreSQL primary
postgres-replica1 - Swarm worker, PostgreSQL replica1
postgres-replica2 - Swarm worker, PostgreSQL replica2
```

출력값으로 각 private IP와 HAProxy endpoint를 확인할 수 있습니다.

```bash
terraform output postgres_primary_private_ip
terraform output postgres_replica1_private_ip
terraform output postgres_replica2_private_ip
terraform output postgres_ha_haproxy_endpoint
```

## Ansible Inventory 확인

```bash
cd ../ansible_files
ansible-inventory --list
```

Inventory는 `../terraform_files/terraform output -json`을 읽고 Bastion Host를 ProxyCommand로 사용합니다.

## PostgreSQL HA 배포

`postgres-ha/stack.yml`은 `${DOCKERHUB_ID}/postgres-ha-repmgr:16` 이미지를 사용합니다. 기본 namespace는 `group_vars/all.yml`의 `dockerhub_id: wodurl`입니다. 다른 Docker Hub namespace를 쓴다면 먼저 수정하거나 실행 시 override합니다.

```bash
cd ../ansible_files
ansible-playbook playbooks/deploy.yml
```

다른 Docker Hub namespace를 사용할 경우:

```bash
ansible-playbook playbooks/deploy.yml -e dockerhub_id=YOUR_DOCKERHUB_ID
```

## 검증

```bash
ansible-playbook playbooks/verify.yml
```

검증 playbook은 다음을 확인합니다.

```text
docker node ls
docker service ls
repmgr cluster show
```

## 전체 배포 흐름

```text
Terraform
-> EC2 생성
-> Ansible Inventory 생성
-> Docker 설치
-> Swarm 구성
-> postgres-ha 업로드
-> Docker Stack Deploy
-> PostgreSQL HA 배포
```

## GitHub Actions 확장 포인트

현재 GitHub Actions는 수정하지 않았습니다. 이후에는 기존 Terraform apply 이후 다음 단계를 추가하면 됩니다.

```text
Terraform Apply
-> ansible-inventory --list
-> ansible-playbook playbooks/deploy.yml
-> ansible-playbook playbooks/verify.yml
```
