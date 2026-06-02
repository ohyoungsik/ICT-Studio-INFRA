# ==============================================
# 로컬 변수 정의 (Terraform 전체에서 사용)
# ==============================================

locals {
  project     = "ict"
  env         = "prod"
  name_prefix = "${local.env}-${local.project}"
  az_suffix   = ["a", "c"]
}
