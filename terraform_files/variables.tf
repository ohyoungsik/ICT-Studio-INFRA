# ==============================================
# 입력 변수 정의
# ==============================================

variable "region" {
  description = "AWS region for resources."
  type        = string
  default     = "ap-northeast-2"
}

variable "vpc_cidr" {
  description = "VPC CIDR block."
  type        = string
  default     = "172.16.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "List of Public Subnet CIDRs."
  type        = list(string)
  default     = ["172.16.10.0/24", "172.16.11.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "List of Private App Subnet CIDRs."
  type        = list(string)
  default     = ["172.16.20.0/24", "172.16.21.0/24"]
}

variable "db_subnet_cidrs" {
  description = "List of DB Subnet CIDRs."
  type        = list(string)
  default     = ["172.16.30.0/24", "172.16.31.0/24"]
}

variable "alb_name" {
  description = "Application Load Balancer name."
  type        = string
  default     = "prod-ict-alb"
}

variable "key_name" {
  description = "EC2 key pair name for SSH access."
  type        = string
  default     = "ict-project-key"
}

variable "desired_capacity" {
  description = "ASG desired capacity."
  type        = number
  default     = 2
}

variable "min_size" {
  description = "ASG minimum size."
  type        = number
  default     = 2
}

variable "max_size" {
  description = "ASG maximum size."
  type        = number
  default     = 4
}
