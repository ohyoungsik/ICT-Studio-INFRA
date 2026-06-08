param(
  [switch]$AutoApprove,
  [string]$BackendKey = "prod-ict/terraform.tfstate"
)

$ErrorActionPreference = "Stop"

$RootDir = Resolve-Path (Join-Path $PSScriptRoot "..")
$BootstrapDir = Join-Path $RootDir "bootstrap"
$MainDir = Join-Path $RootDir "terraform_files"

Write-Host "==> Initializing bootstrap Terraform"
terraform -chdir="$BootstrapDir" init

Write-Host "==> Applying bootstrap Terraform"
if ($AutoApprove) {
  terraform -chdir="$BootstrapDir" apply -auto-approve
} else {
  terraform -chdir="$BootstrapDir" apply
}

$BackendBucket = terraform -chdir="$BootstrapDir" output -raw backend_bucket
$BackendRegion = terraform -chdir="$BootstrapDir" output -raw backend_region

Write-Host "==> Initializing main Terraform backend"
terraform -chdir="$MainDir" init -reconfigure `
  -backend-config="bucket=$BackendBucket" `
  -backend-config="key=$BackendKey" `
  -backend-config="region=$BackendRegion" `
  -backend-config="encrypt=true" `
  -backend-config="use_lockfile=true"

Write-Host ""
Write-Host "Backend ready:"
Write-Host "  bucket: $BackendBucket"
Write-Host "  key   : $BackendKey"
Write-Host "  region: $BackendRegion"
Write-Host ""
Write-Host "Next:"
Write-Host "  cd terraform_files"
Write-Host "  terraform plan"
Write-Host "  terraform apply"
