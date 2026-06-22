# 주의: docker-compose.yml이 /opt/app/docker-compose.yml에 있어야 함
# 다음 방법 중 하나로 제공 가능:
# 1. User Data에서 Git 저장소 클론
# 2. S3 버킷에서 다운로드
# 3. 미리 빌드된 AMI 사용
resource "aws_launch_template" "app_lt" {
  name_prefix   = "${var.name_prefix}-app-lt-"
  image_id      = var.ami_id
  instance_type = "t3.small"

  key_name = var.key_name

  iam_instance_profile {
    name = var.iam_instance_profile_name
  }

  vpc_security_group_ids = [var.app_security_group_id]

  user_data = base64encode(templatefile("${path.root}/../scripts/worker-node-bootstrap.sh", {
    name_prefix          = var.name_prefix
    aws_region           = var.region
    host_role            = "app"
    loki_push_url        = "http://${var.bastion_private_ip}:3100/loki/api/v1/push"
    backend_image_s3_uri = var.backend_image_s3_uri
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.name_prefix}-app"
      Role        = "app"
      Environment = var.env
    }
  }
}
