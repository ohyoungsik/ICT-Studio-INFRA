# ==============================================
# Auto Scaling Group 설정
# ==============================================
# EC2 인스턴스의 자동 생성, 삭제, 복구를 관리
# Health Check 실패 시 자동으로 새 인스턴스 생성
# 트래픽 변화에 따라 인스턴스 개수 자동 조정

resource "aws_autoscaling_group" "app_asg" {
  name                = "${local.name_prefix}-app-asg"
  desired_capacity    = var.desired_capacity
  min_size            = var.min_size
  max_size            = var.max_size
  vpc_zone_identifier = aws_subnet.private_app[*].id

  target_group_arns = [
    aws_lb_target_group.app.arn,
    aws_lb_target_group.backend.arn
  ]

  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      instance_warmup        = 300
      min_healthy_percentage = 50
    }
  }

  # ELB Health Check 사용: ALB의 /api/health 응답 성공 여부로 인스턴스 상태 판단
  health_check_type = "ELB"
  # Grace Period: Docker 설치, 백엔드 빌드, Swarm join 시간 확보
  health_check_grace_period = 420

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-private-app"
    propagate_at_launch = true
  }

  tag { # app 태그 추가
    key                 = "Role"
    value               = "app"
    propagate_at_launch = true
  }

  tag { # env 태그 추가
    key                 = "Environment"
    value               = local.env
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                      = "${local.name_prefix}-cpu-target"
  autoscaling_group_name    = aws_autoscaling_group.app_asg.name
  policy_type               = "TargetTrackingScaling"
  estimated_instance_warmup = 60

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    # cpu 사용률이 70%를 초과하면 인스턴스 추가, 70% 미만이면 인스턴스 제거
    target_value = 70.0
  }
}
