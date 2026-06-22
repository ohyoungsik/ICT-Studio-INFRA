variable "name_prefix" {
  type = string
}

variable "env" {
  type = string
}

variable "region" {
  type = string
}

variable "ami_id" {
  type = string
}

variable "key_name" {
  type = string
}

variable "iam_instance_profile_name" {
  type = string
}

variable "app_security_group_id" {
  type = string
}

variable "private_app_subnet_ids" {
  type = list(string)
}

variable "backend_target_group_arn" {
  type = string
}

variable "bastion_private_ip" {
  type = string
}

variable "backend_image_s3_uri" {
  type = string
}

variable "desired_capacity" {
  type = number
}

variable "min_size" {
  type = number
}

variable "max_size" {
  type = number
}

variable "queue_metric_namespace" {
  type = string
}

variable "queue_metric_concert_id" {
  type = string
}

variable "queue_length_per_instance_target" {
  type = number
}

variable "enable_queue_consumer" {
  type = bool
}

variable "queue_consumer_batch_size" {
  type = number
}

variable "queue_consumer_interval_seconds" {
  type = number
}

variable "alb_dns_name" {
  type = string
}
