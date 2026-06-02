# ==============================================
# Application Load Balancer (ALB) 설정
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
  name     = "${local.name_prefix}-app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
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

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.application_load_balancer.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
