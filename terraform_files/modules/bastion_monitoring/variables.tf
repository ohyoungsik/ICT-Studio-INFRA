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

variable "public_subnet_ids" {
  type = list(string)
}

variable "bastion_security_group_id" {
  type = string
}

variable "key_name" {
  type = string
}

variable "iam_instance_profile_name" {
  type = string
}
