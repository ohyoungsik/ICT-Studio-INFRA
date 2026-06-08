# Scripts 사용법

이 폴더에는 Terraform을 실행하기 전에 필요한 준비 스크립트가 들어 있습니다.

이 프로젝트는 Terraform state를 S3 bucket에 저장합니다. 그래서 처음 실행할 때
S3 bucket을 먼저 만들고, 그 bucket을 Terraform backend로 연결해야 합니다.

## 팀원이 Ubuntu에서 처음 실행할 때

저장소를 받은 뒤 프로젝트 루트에서 실행합니다.

```bash
bash scripts/init-backend.sh
```

이 명령이 해주는 일:

```text
1. backend용 S3 bucket 생성
2. terraform_files의 backend 초기화
```

그 다음 메인 Terraform을 실행합니다.

```bash
cd terraform_files
terraform plan
terraform apply
```

주의: 처음부터 `terraform_files`로 들어가서 `terraform init`을 직접 실행하지 마세요.
backend bucket 정보가 없어서 에러가 날 수 있습니다.

## Windows에서 실행할 때

Windows PowerShell에서는 아래 명령을 사용합니다.

```powershell
.\scripts\init-backend.ps1
```

그 다음:

```powershell
cd terraform_files
terraform plan
terraform apply
```

## 삭제할 때

삭제할 때도 먼저 backend를 연결해야 합니다.

```bash
bash scripts/init-backend.sh
cd terraform_files
terraform plan -destroy
terraform destroy
```

대부분의 경우 backend S3 bucket은 삭제하지 않습니다.  
나중에 다시 배포하거나 state 기록을 확인할 수 있기 때문입니다.

## GitHub Actions에서 사용할 때

GitHub Actions는 사람이 직접 실행하지 않습니다. workflow가 자동으로 실행합니다.

workflow에서는 아래 스크립트를 사용합니다.

```bash
bash scripts/init-backend-ci.sh
```

이 스크립트는 GitHub Actions runner에서 backend S3 bucket을 준비하고,
`terraform_files`를 초기화합니다.

## GitHub Actions에 필요한 Secret

현재 workflow는 AWS Access Key 방식으로 AWS에 접속합니다.
GitHub Repository Secret에 아래 두 값을 등록해야 합니다.

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
```

등록 위치:

```text
GitHub Repository
-> Settings
-> Secrets and variables
-> Actions
-> New repository secret
```

## GitHub Actions 배포 흐름

PR을 올리면:

```text
terraform validate
terraform plan
```

main 브랜치에 push 또는 merge되면:

```text
terraform validate
terraform plan
terraform apply
```

즉, PR에서는 확인만 하고 실제 AWS 배포는 main 브랜치에 들어갔을 때 실행됩니다.

## 파일별 역할

```text
init-backend.sh       Ubuntu/Linux/macOS 로컬 실행용
init-backend.ps1      Windows PowerShell 로컬 실행용
init-backend-ci.sh    GitHub Actions 실행용
```
