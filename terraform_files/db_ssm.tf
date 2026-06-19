resource "aws_ssm_parameter" "db_host" {
  name      = "/${local.name_prefix}/db/host"
  type      = "String"
  value     = aws_instance.db_main.private_ip
  overwrite = true
}

resource "aws_ssm_parameter" "db_port" {
  name      = "/${local.name_prefix}/db/port"
  type      = "String"
  value     = "5432"
  overwrite = true
}

resource "aws_ssm_parameter" "db_name" {
  name      = "/${local.name_prefix}/db/name"
  type      = "String"
  value     = var.db_name
  overwrite = true
}

resource "aws_ssm_parameter" "db_user" {
  name      = "/${local.name_prefix}/db/user"
  type      = "String"
  value     = var.db_user
  overwrite = true
}

resource "aws_ssm_parameter" "db_password" {
  name      = "/${local.name_prefix}/db/password"
  type      = "SecureString"
  value     = var.db_password
  overwrite = true
}
