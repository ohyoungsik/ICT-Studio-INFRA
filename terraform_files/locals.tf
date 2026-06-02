locals {
  project     = "ict"
  env         = "prod"
  name_prefix = "${local.env}-${local.project}"
  az_suffix   = ["a", "c"]
}
