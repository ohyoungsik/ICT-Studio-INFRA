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

variable "db_name" {
  description = "PostgreSQL database name."
  type        = string
  default     = "ticketing"
}

variable "db_user" {
  description = "PostgreSQL user name."
  type        = string
  default     = "appuser"
}

variable "db_password" {
  description = "PostgreSQL password."
  type        = string
  default     = "app_password"
  sensitive   = true
}

variable "backend_image_s3_uri" {
  description = "S3 URI of the backend Docker image tarball loaded by worker nodes."
  type        = string
  default     = "s3://prod-ict-terraform-state-2df0de99/artifacts/ict-studio-be/latest.tar.gz"
}

variable "desired_capacity" {
  description = "ASG desired capacity."
  type        = number
  default     = 1
}

variable "min_size" {
  description = "ASG minimum size."
  type        = number
  default     = 1
}

variable "max_size" {
  description = "ASG maximum size."
  type        = number
  default     = 8
}

variable "queue_metric_namespace" {
  description = "CloudWatch namespace for Redis queue scaling metrics."
  type        = string
  default     = "ICT/Queue"
}

variable "queue_metric_concert_id" {
  description = "Concert ID dimension used by queue scaling metrics."
  type        = string
  default     = "1"
}

variable "queue_length_per_instance_target" {
  description = "Target Redis queue length per healthy app instance for ASG target tracking."
  type        = number
  default     = 2000
}

variable "enable_queue_consumer" {
  description = "Whether to install a test queue consumer timer on the master node for scale-in validation."
  type        = bool
  default     = false
}

variable "queue_consumer_batch_size" {
  description = "Number of queue users consumed per queue consumer run."
  type        = number
  default     = 100
}

variable "queue_consumer_interval_seconds" {
  description = "Interval in seconds for the test queue consumer timer."
  type        = number
  default     = 30
}

variable "telegram_bot_token" {
  type      = string
  sensitive = true
}

variable "telegram_chat_id" {
  type      = string
  sensitive = true
}

variable "discord_webhook_url" {
  type      = string
  sensitive = true
}
