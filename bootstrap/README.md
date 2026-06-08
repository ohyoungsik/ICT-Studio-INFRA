# Terraform Backend Bootstrap

이 디렉터리는 메인 Terraform 프로젝트가 사용할 S3 backend bucket을
처음 생성하기 위한 bootstrap Terraform입니다.

Terraform의 S3 backend bucket은 `terraform init` 시점에 이미 존재해야 합니다.
그래서 `terraform_files`에서 바로 `terraform init`을 실행하면 bucket 값을
입력하라는 프롬프트가 뜨거나 backend 설정 변경 에러가 날 수 있습니다.

## 로컬 실행 방법

로컬 개발 환경에서는 `terraform_files`에서 `terraform plan` 또는
`terraform apply`를 실행하기 전에 backend 초기화 스크립트를 먼저 실행합니다.

저장소 루트에서 실행하세요.

Linux/macOS:

```bash
bash scripts/init-backend.sh
```

Windows PowerShell:

```powershell
.\scripts\init-backend.ps1
```

bootstrap bucket 생성 확인을 생략하려면 다음처럼 실행합니다.

Linux/macOS:

```bash
AUTO_APPROVE=true bash scripts/init-backend.sh
```

Windows PowerShell:

```powershell
.\scripts\init-backend.ps1 -AutoApprove
```

스크립트가 끝난 뒤에는 메인 Terraform을 실행하면 됩니다.

```powershell
cd terraform_files
terraform plan
terraform apply
```

## GitHub Actions 실행 방법

GitHub Actions에서는 이 `bootstrap` Terraform 디렉터리를 실행하지 않습니다.

GitHub-hosted runner는 매번 새로 생성되기 때문에 로컬 bootstrap state를
유지할 수 없습니다. 대신 CI 전용 스크립트인 `scripts/init-backend-ci.sh`가
AWS 계정 ID를 기준으로 안정적인 bucket 이름을 만들고, bucket이 없으면
생성한 뒤 `terraform_files`를 초기화합니다.

필요한 GitHub Repository Secret:

```text
AWS_ROLE_ARN
```

workflow에서 실행되는 명령:

```bash
bash scripts/init-backend-ci.sh
```

## 수동 실행 방법

스크립트를 쓰지 않고 직접 실행하려면 다음 순서로 진행합니다.

```powershell
cd bootstrap
terraform init
terraform apply
terraform output main_terraform_init_command
```

출력된 `terraform init -reconfigure ...` 명령을 복사해서 `terraform_files`에서
실행합니다.

```powershell
cd ../terraform_files
terraform plan
terraform apply
```
