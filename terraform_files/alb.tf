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
    target_group_arn = aws_lb_target_group.backend.arn
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
