# RSA 키 페어 자동 생성
resource "tls_private_key" "app_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# 생성된 퍼블릭 키를 AWS에 등록
resource "aws_key_pair" "app_key" {
  key_name   = var.key_name
  public_key = tls_private_key.app_key.public_key_openssh

  tags = {
    Name        = var.key_name
    Environment = var.env
  }
}

# 프라이빗 키를 로컬 파일로 저장 (SSH 접속 시 사용)
resource "local_file" "private_key" {
  content         = tls_private_key.app_key.private_key_pem
  filename        = "${path.root}/${var.key_name}.pem"
  file_permission = "0600"
}

resource "aws_secretsmanager_secret" "private_key" {
  name                    = "${var.name_prefix}/${var.key_name}/private-key"
  description             = "Private SSH key for ${var.name_prefix} EC2 access."
  recovery_window_in_days = 0

  tags = {
    Name        = "${var.name_prefix}-private-key"
    Environment = var.env
  }
}

resource "aws_secretsmanager_secret_version" "private_key" {
  secret_id     = aws_secretsmanager_secret.private_key.id
  secret_string = tls_private_key.app_key.private_key_pem
}
