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
    Environment = local.env
  }
}

# 프라이빗 키를 로컬 파일로 저장 (SSH 접속 시 사용)
resource "local_file" "private_key" {
  content         = tls_private_key.app_key.private_key_pem
  filename        = "${path.module}/${var.key_name}.pem"
  file_permission = "0600"
}

resource "aws_secretsmanager_secret" "private_key" {
  name                    = "${local.name_prefix}/${var.key_name}/private-key"
  description             = "Private SSH key for ${local.name_prefix} EC2 access."
  recovery_window_in_days = 0

  tags = {
    Name        = "${local.name_prefix}-private-key"
    Environment = local.env
  }
}

resource "aws_secretsmanager_secret_version" "private_key" {
  secret_id     = aws_secretsmanager_secret.private_key.id
  secret_string = tls_private_key.app_key.private_key_pem
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (Ubuntu 공식 배포자)
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# 주의: docker-compose.yml이 /opt/app/docker-compose.yml에 있어야 함
# 다음 방법 중 하나로 제공 가능:
# 1. User Data에서 Git 저장소 클론
# 2. S3 버킷에서 다운로드
# 3. 미리 빌드된 AMI 사용
resource "aws_launch_template" "app_lt" {
  name_prefix   = "${local.name_prefix}-app-lt-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t3.small"

  key_name = aws_key_pair.app_key.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.instance_profile.name
  }

  vpc_security_group_ids = [aws_security_group.app.id]

  user_data = base64encode(templatefile("${path.module}/../scripts/worker-node-bootstrap.sh", {
    name_prefix   = local.name_prefix
    aws_region    = var.region
    host_role     = "app"
    loki_push_url = "http://${aws_instance.bastion.private_ip}:3100/loki/api/v1/push"
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${local.name_prefix}-app"
      Role        = "app"
      Environment = local.env
    }
  }
}
