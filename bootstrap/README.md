# Terraform Backend Bootstrap

This directory creates the S3 bucket used by the main Terraform backend.
It intentionally uses local Terraform state because the remote backend bucket
does not exist yet during the first run.

## Usage

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
