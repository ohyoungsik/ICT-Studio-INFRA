output "backend_bucket" {
  description = "S3 bucket name for the main Terraform backend."
  value       = aws_s3_bucket.terraform_state.bucket
}

output "backend_region" {
  description = "AWS region for the main Terraform backend."
  value       = var.region
}

output "main_terraform_init_command" {
  description = "Run this in terraform_files after bootstrap apply."
  value = join(" ", [
    "terraform init -reconfigure",
    "-backend-config=\"bucket=${aws_s3_bucket.terraform_state.bucket}\"",
    "-backend-config=\"key=prod-ict/terraform.tfstate\"",
    "-backend-config=\"region=${var.region}\"",
    "-backend-config=\"encrypt=true\"",
    "-backend-config=\"use_lockfile=true\"",
  ])
}
