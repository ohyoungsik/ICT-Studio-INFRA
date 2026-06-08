# Scripts

이 디렉터리는 Terraform S3 backend를 준비하기 위한 실행 스크립트를 담고 있습니다.

메인 Terraform 코드는 `terraform_files`에 있지만, S3 backend bucket은
`terraform init` 전에 이미 존재해야 합니다. 그래서 로컬과 GitHub Actions에서
각각 다른 방식으로 backend를 먼저 준비합니다.

## 로컬 개발 환경

개발자 PC에서 직접 Terraform을 실행할 때 사용합니다.

### `init-backend.sh`

Linux/macOS용 backend 초기화 스크립트입니다.

저장소 루트에서 실행합니다.

```bash
bash scripts/init-backend.sh
```

동작 순서:

1. `bootstrap` 디렉터리에서 `terraform init`을 실행합니다.
2. `bootstrap` 디렉터리에서 `terraform apply`를 실행해 backend S3 bucket을 생성합니다.
3. bootstrap output에서 생성된 bucket 이름을 읽습니다.
4. `terraform_files` 디렉터리에서 S3 backend 설정을 포함해
   `terraform init -reconfigure`를 실행합니다.

bootstrap apply 확인을 생략하려면 다음처럼 실행합니다.

```bash
AUTO_APPROVE=true bash scripts/init-backend.sh
```

### `init-backend.ps1`

Windows PowerShell용 backend 초기화 스크립트입니다.

저장소 루트에서 실행합니다.

```powershell
.\scripts\init-backend.ps1
```

bootstrap apply 확인을 생략하려면 다음처럼 실행합니다.

```powershell
.\scripts\init-backend.ps1 -AutoApprove
```

## GitHub Actions 환경

### `init-backend-ci.sh`

GitHub Actions runner 전용 backend 초기화 스크립트입니다.

이 스크립트는 `bootstrap` Terraform 디렉터리를 사용하지 않습니다.
GitHub-hosted runner는 매번 새로 만들어지고 local state를 유지하지 못하기 때문입니다.

대신 다음 방식으로 동작합니다.

1. 현재 AWS 계정 ID를 조회합니다.
2. AWS 계정 ID 기반으로 고정된 backend bucket 이름을 만듭니다.

   ```text
   prod-ict-terraform-state-${AWS_ACCOUNT_ID}
   ```

3. bucket이 없으면 생성합니다.
4. public access block, AES256 암호화, versioning을 설정합니다.
5. `terraform_files` 디렉터리에서 `terraform init -reconfigure`를 실행합니다.

workflow에서는 다음처럼 호출합니다.

```bash
bash scripts/init-backend-ci.sh
```

필요한 GitHub Repository Secret:

```text
AWS_ROLE_ARN
```

backend 초기화 이후 workflow는 다음 명령을 실행할 수 있습니다.

```bash
terraform -chdir=terraform_files validate
terraform -chdir=terraform_files plan -out=tfplan
terraform -chdir=terraform_files apply -auto-approve tfplan
```

## 요약

로컬 개발자는 `init-backend.sh` 또는 `init-backend.ps1`을 사용합니다.
GitHub Actions에서는 `init-backend-ci.sh`만 사용합니다.
