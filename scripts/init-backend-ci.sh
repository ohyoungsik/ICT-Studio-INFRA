#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIN_DIR="$ROOT_DIR/terraform_files"

BACKEND_REGION="${TF_BACKEND_REGION:-${AWS_REGION:-ap-northeast-2}}"
BACKEND_KEY="${TF_BACKEND_KEY:-prod-ict/terraform.tfstate}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BACKEND_BUCKET="${TF_BACKEND_BUCKET:-prod-ict-terraform-state-${ACCOUNT_ID}}"

echo "==> Ensuring Terraform backend bucket"
if aws s3api head-bucket --bucket "$BACKEND_BUCKET" >/dev/null 2>&1; then
  echo "Backend bucket already exists: $BACKEND_BUCKET"
else
  echo "Creating backend bucket: $BACKEND_BUCKET"
  if [[ "$BACKEND_REGION" == "us-east-1" ]]; then
    aws s3api create-bucket \
      --bucket "$BACKEND_BUCKET" \
      --region "$BACKEND_REGION"
  else
    aws s3api create-bucket \
      --bucket "$BACKEND_BUCKET" \
      --region "$BACKEND_REGION" \
      --create-bucket-configuration "LocationConstraint=$BACKEND_REGION"
  fi
fi

aws s3api put-public-access-block \
  --bucket "$BACKEND_BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws s3api put-bucket-encryption \
  --bucket "$BACKEND_BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-bucket-versioning \
  --bucket "$BACKEND_BUCKET" \
  --versioning-configuration Status=Enabled

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
