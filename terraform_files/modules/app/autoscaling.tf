# ==============================================
# Auto Scaling Group 설정
# ==============================================
# EC2 인스턴스의 자동 생성, 삭제, 복구를 관리
# Health Check 실패 시 자동으로 새 인스턴스 생성
# 트래픽 변화에 따라 인스턴스 개수 자동 조정

resource "aws_autoscaling_group" "app_asg" {
  name                = "${var.name_prefix}-app-asg"
  desired_capacity    = var.desired_capacity
  min_size            = var.min_size
  max_size            = var.max_size
  vpc_zone_identifier = var.private_app_subnet_ids

  target_group_arns = [
    var.backend_target_group_arn
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

  # 최초 프로비저닝 중에는 Ansible이 PostgreSQL HA를 뒤늦게 구성하므로
  # ALB /health 실패만으로 app 인스턴스를 반복 교체하지 않는다.
  health_check_type         = "EC2"
  health_check_grace_period = 900

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-private-app"
    propagate_at_launch = true
  }

  tag { # app 태그 추가
    key                 = "Role"
    value               = "app"
    propagate_at_launch = true
  }

  tag { # env 태그 추가
    key                 = "Environment"
    value               = var.env
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                      = "${var.name_prefix}-cpu-target"
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

resource "aws_autoscaling_policy" "queue_target_tracking" {
  name                      = "${var.name_prefix}-queue-target"
  autoscaling_group_name    = aws_autoscaling_group.app_asg.name
  policy_type               = "TargetTrackingScaling"
  estimated_instance_warmup = 120

  target_tracking_configuration {
    customized_metric_specification {
      metric_name = "QueueLengthPerInstanceForAsg"
      namespace   = var.queue_metric_namespace
      statistic   = "Average"
      unit        = "Count"
    }

    target_value = var.queue_length_per_instance_target
  }
}

resource "aws_autoscaling_policy" "queue_burst_step_scale_out" {
  name                      = "${var.name_prefix}-queue-burst-step-out"
  autoscaling_group_name    = aws_autoscaling_group.app_asg.name
  policy_type               = "StepScaling"
  adjustment_type           = "ChangeInCapacity"
  estimated_instance_warmup = 60
  metric_aggregation_type   = "Average"

  step_adjustment {
    metric_interval_lower_bound = 0
    metric_interval_upper_bound = 3000
    scaling_adjustment          = 2
  }

  step_adjustment {
    metric_interval_lower_bound = 3000
    scaling_adjustment          = 4
  }
}

resource "aws_cloudwatch_metric_alarm" "queue_burst_scale_out" {
  alarm_name          = "${var.name_prefix}-queue-burst-scale-out"
  alarm_description   = "Scale out app ASG quickly when the total Redis queue length spikes."
  namespace           = var.queue_metric_namespace
  metric_name         = "QueueLength"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 1
  threshold           = 3000
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    Environment = var.env
    ConcertId   = var.queue_metric_concert_id
  }

  alarm_actions = [
    aws_autoscaling_policy.queue_burst_step_scale_out.arn
  ]
}
