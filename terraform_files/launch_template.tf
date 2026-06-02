resource "aws_key_pair" "app_key" {
  key_name   = var.key_name
  public_key = var.public_key

  tags = {
    Name        = var.key_name
    Environment = local.env
  }
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

  user_data = base64encode(file("${path.module}/userdata.sh"))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${local.name_prefix}-app-server"
      Environment = local.env
    }
  }
}
