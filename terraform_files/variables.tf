variable "region" {
  description = "AWS 리전을 지정합니다."
  type        = string
  default     = "ap-northeast-2"
}

variable "environment" {
  description = "태그와 리소스 네이밍에 사용할 환경 이름입니다."
  type        = string
  default     = "prod"
}

variable "vpc_cidr" {
  description = "VPC CIDR 블록입니다."
  type        = string
  default     = "172.16.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public Subnet CIDR 목록입니다."
  type        = list(string)
  default     = ["172.16.10.0/24", "172.16.11.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "Private App Subnet CIDR 목록입니다."
  type        = list(string)
  default     = ["172.16.20.0/24", "172.16.21.0/24"]
}

variable "db_subnet_cidrs" {
  description = "DB Subnet CIDR 목록입니다."
  type        = list(string)
  default     = ["172.16.30.0/24", "172.16.31.0/24"]
}

variable "alb_name" {
  description = "Application Load Balancer 이름입니다."
  type        = string
  default     = "concert-alb"
}
