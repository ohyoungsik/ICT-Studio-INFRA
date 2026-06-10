# Terraform Destroy Git Flow

이 문서는 테스트용으로 생성된 AWS 인프라를 GitHub Actions에서 삭제하는 흐름을 설명합니다.

## 핵심 원칙

- `main`에 push해도 destroy는 자동 실행되지 않습니다.
- destroy는 GitHub Actions의 수동 실행(`workflow_dispatch`)으로만 실행됩니다.
- 확인 문구 `DESTROY-prod-ict`를 정확히 입력해야 삭제가 진행됩니다.
- Terraform backend S3 bucket은 삭제하지 않습니다. 인프라 state 보관과 재배포를 위해 유지합니다.

## 권장 Git Flow

1. destroy workflow 추가 브랜치를 생성합니다.

```bash
git checkout -b chore/add-terraform-destroy-workflow
```

2. 변경사항을 커밋하고 PR을 생성합니다.

```bash
git add .github/workflows/terraform-destroy.yml docs/terraform-destroy-git-flow.md
git commit -m "chore: add manual terraform destroy workflow"
git push origin chore/add-terraform-destroy-workflow
```

3. PR에서 기존 Terraform workflow가 `validate`, `plan`까지 정상 통과하는지 확인합니다.

4. PR을 `main`에 merge합니다.

5. GitHub에서 수동으로 destroy workflow를 실행합니다.

```text
GitHub Repository
-> Actions
-> Terraform Destroy
-> Run workflow
```

6. 입력값을 확인합니다.

```text
confirm_destroy: DESTROY-prod-ict
backend_key: prod-ict/terraform.tfstate
```

7. workflow 로그에서 `Terraform destroy plan`에 삭제 대상이 맞는지 확인한 뒤, 이어지는 `Terraform destroy` 결과를 확인합니다.

## 삭제되는 대상

현재 remote state에 잡힌 `terraform_files`의 리소스가 삭제됩니다. 예를 들면 다음 리소스들이 대상입니다.

- VPC, subnet, route table, internet gateway, NAT gateway, EIP
- ALB, target group, listener
- Auto Scaling Group, launch template, EC2 instances
- Bastion, Swarm manager, DB EC2
- Security groups and rules
- IAM role, instance profile, inline policies
- Secrets Manager private key secret
- Local/TLS 기반 key pair 관련 Terraform 리소스

## 삭제되지 않는 대상

- Terraform backend S3 bucket
- S3 backend object version history
- GitHub repository secrets
- Terraform 외부에서 직접 만든 AWS 리소스

## 실패 시 확인할 것

- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` GitHub Secrets가 유효한지 확인합니다.
- backend key가 실제 배포에 사용한 값인지 확인합니다. 기본값은 `prod-ict/terraform.tfstate`입니다.
- destroy 중 의존성 오류가 나면 같은 workflow를 다시 실행해도 됩니다. Terraform state가 남아 있으면 남은 리소스만 다시 정리합니다.
