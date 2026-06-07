terraform {
  backend "s3" {
    bucket       = "prod-ict-terraform-state-718036735682"
    key          = "prod-ict/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
