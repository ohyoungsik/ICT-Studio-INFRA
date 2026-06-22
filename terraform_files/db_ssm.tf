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

# 읽기 전용 엔드포인트. HAProxy는 동일한 db_main 노드에서 5433 포트로 replica 읽기를 라우팅한다.
resource "aws_ssm_parameter" "db_read_host" {
  name      = "/${local.name_prefix}/db/read_host"
  type      = "String"
  value     = aws_instance.db_main.private_ip
  overwrite = true
}

resource "aws_ssm_parameter" "db_read_port" {
  name      = "/${local.name_prefix}/db/read_port"
  type      = "String"
  value     = "5433"
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
