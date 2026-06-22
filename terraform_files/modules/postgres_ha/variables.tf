variable "name_prefix" {
  type = string
}

variable "env" {
  type = string
}

variable "ami_id" {
  type = string
}

variable "db_subnet_ids" {
  type = list(string)
}

variable "db_security_group_id" {
  type = string
}

variable "key_name" {
  type = string
}

variable "iam_instance_profile_name" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_user" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "postgres_ha_instance_type" {
  type = string
}

variable "postgres_ha_root_volume_size" {
  type = number
}
