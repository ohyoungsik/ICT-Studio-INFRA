# ==============================================
# Application Load Balancer (ALB) 설정 - cicd test
# ==============================================

resource "aws_lb" "application_load_balancer" {
  name               = var.alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name        = "${local.name_prefix}-alb"
    Environment = local.env
  }
}

# 대상 그룹: ALB 뒤에 붙는 기본 대상 그룹 (응답 싱크 동작)
resource "aws_lb_target_group" "app" {
  name                 = "${local.name_prefix}-app-tg"
  port                 = 80
  protocol             = "HTTP"
  vpc_id               = aws_vpc.main.id
  deregistration_delay = 20
  # Health Check: /api/health 엔드포인트로 EC2 인스턴스 상태 모니터링

  health_check {
    enabled             = true
    path                = "/health"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "${local.name_prefix}-app-tg"
    Environment = local.env
  }
}
# HTTP 리스너: 다가오는 HTTP 요청을 대상 그룹으로 라우팅

resource "aws_lb_target_group" "backend" {
  name                 = "${local.name_prefix}-backend-tg"
  port                 = 8000
  protocol             = "HTTP"
  vpc_id               = aws_vpc.main.id
  deregistration_delay = 20

  health_check {
    enabled             = true
    path                = "/health"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "${local.name_prefix}-backend-tg"
    Environment = local.env
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.application_load_balancer.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# Portainer UI: ALB → Master:9000 (HTTP, TLS는 추후 ACM + 443 리스너로 확장 가능)
resource "aws_lb_listener_rule" "backend_api" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

resource "aws_lb_listener_rule" "backend_health" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = ["/health"]
    }
  }
}

resource "aws_lb_target_group" "portainer" {
  name                 = "${local.name_prefix}-portainer-tg"
  port                 = 9000
  protocol             = "HTTP"
  vpc_id               = aws_vpc.main.id
  deregistration_delay = 20

  health_check {
    enabled             = true
    path                = "/api/status"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name        = "${local.name_prefix}-portainer-tg"
    Environment = local.env
  }
}

resource "aws_lb_target_group_attachment" "portainer_master" {
  target_group_arn = aws_lb_target_group.portainer.arn
  target_id        = aws_instance.master_node.id
  port             = 9000
}

resource "aws_lb_listener" "portainer" {
  load_balancer_arn = aws_lb.application_load_balancer.arn
  port              = 9000
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.portainer.arn
  }
}
