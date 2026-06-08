variable "region" {
  description = "AWS region for the Terraform backend bucket."
  type        = string
  default     = "ap-northeast-2"
}

variable "environment" {
  description = "Environment tag value."
  type        = string
  default     = "prod"
}

variable "name_prefix" {
  description = "Prefix used for backend resources."
  type        = string
  default     = "prod-ict"
}
