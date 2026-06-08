# Terraform Backend Bootstrap

This directory creates the S3 bucket used by the main Terraform backend.
It intentionally uses local Terraform state because the remote backend bucket
does not exist yet during the first run.

## Usage

From the repository root, run the helper script.

Linux/macOS:

```bash
bash scripts/init-backend.sh
```

Windows PowerShell:

```powershell
.\scripts\init-backend.ps1
```

To skip the Terraform apply confirmation for the bootstrap bucket:

```bash
AUTO_APPROVE=true bash scripts/init-backend.sh
```

```powershell
.\scripts\init-backend.ps1 -AutoApprove
```

After the script finishes:

```powershell
cd terraform_files
terraform plan
terraform apply
```

## GitHub Actions Usage

GitHub Actions should use the CI backend script instead of the local bootstrap
Terraform state. The CI script uses the AWS account ID to derive a stable bucket
name, creates the bucket if needed, and then initializes `terraform_files`.

Required repository secret:

```text
AWS_ROLE_ARN
```

Workflow command:

```bash
bash scripts/init-backend-ci.sh
```

## Manual Usage

```powershell
cd bootstrap
terraform init
terraform apply
terraform output main_terraform_init_command
```

Then run the printed `terraform init -reconfigure ...` command in `terraform_files`.

```powershell
cd ../terraform_files
terraform plan
terraform apply
```
