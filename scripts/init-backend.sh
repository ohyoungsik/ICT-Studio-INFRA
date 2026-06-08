#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP_DIR="$ROOT_DIR/bootstrap"
MAIN_DIR="$ROOT_DIR/terraform_files"
BACKEND_KEY="${TF_BACKEND_KEY:-prod-ict/terraform.tfstate}"

echo "==> Initializing bootstrap Terraform"
terraform -chdir="$BOOTSTRAP_DIR" init

echo "==> Applying bootstrap Terraform"
if [[ "${AUTO_APPROVE:-false}" == "true" ]]; then
  terraform -chdir="$BOOTSTRAP_DIR" apply -auto-approve
else
  terraform -chdir="$BOOTSTRAP_DIR" apply
fi

BACKEND_BUCKET="$(terraform -chdir="$BOOTSTRAP_DIR" output -raw backend_bucket)"
BACKEND_REGION="$(terraform -chdir="$BOOTSTRAP_DIR" output -raw backend_region)"

echo "==> Initializing main Terraform backend"
terraform -chdir="$MAIN_DIR" init -reconfigure \
  -backend-config="bucket=$BACKEND_BUCKET" \
  -backend-config="key=$BACKEND_KEY" \
  -backend-config="region=$BACKEND_REGION" \
  -backend-config="encrypt=true" \
  -backend-config="use_lockfile=true"

echo
echo "Backend ready:"
echo "  bucket: $BACKEND_BUCKET"
echo "  key   : $BACKEND_KEY"
echo "  region: $BACKEND_REGION"
echo
echo "Next:"
echo "  cd terraform_files"
echo "  terraform plan"
echo "  terraform apply"
