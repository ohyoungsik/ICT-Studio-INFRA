# ==============================================
# Auto Scaling Group 설정
# ==============================================
# EC2 인스턴스의 자동 생성, 삭제, 복구를 관리
# Health Check 실패 시 자동으로 새 인스턴스 생성
# 트래픽 변화에 따라 인스턴스 개수 자동 조정

resource "aws_autoscaling_group" "app_asg" {
  name                = "${local.name_prefix}-app-asg"
  desired_capacity    = 2
  min_size            = 2
  max_size            = 2
  vpc_zone_identifier = aws_subnet.private_app[*].id

  target_group_arns = [
    aws_lb_target_group.app.arn
  ]

  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }

  # ELB Health Check 사용: ALB의 /api/health 응답 성공 여부로 인스턴스 상태 판단
  health_check_type = "ELB"
  # Grace Period: 인스턴스 시작 후 120초 이내는 Health Check 실패해도 교체하지 않음
  # (Docker 이미지 다운로드 및 서비스 시작 시간 확보)
  health_check_grace_period = 120

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-app-auto"
    propagate_at_launch = true
  }
}
