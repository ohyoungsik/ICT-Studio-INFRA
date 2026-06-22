resource "aws_lb" "application_load_balancer" {
  name               = var.alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  tags = {
    Name        = "${var.name_prefix}-alb"
    Environment = var.env
  }
}

# Kept temporarily to avoid deleting an in-use legacy target group during the
# backend-only cutover. Traffic is routed to aws_lb_target_group.backend.
resource "aws_lb_target_group" "app" {
  name                 = "${var.name_prefix}-app-tg"
  port                 = 80
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
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
    Name        = "${var.name_prefix}-app-tg"
    Environment = var.env
  }
}

resource "aws_lb_target_group" "backend" {
  name                 = "${var.name_prefix}-backend-tg"
  port                 = 8000
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
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
    Name        = "${var.name_prefix}-backend-tg"
    Environment = var.env
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
  name                 = "${var.name_prefix}-portainer-tg"
  port                 = 9000
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
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
    Name        = "${var.name_prefix}-portainer-tg"
    Environment = var.env
  }
}

resource "aws_lb_target_group_attachment" "portainer_master" {
  target_group_arn = aws_lb_target_group.portainer.arn
  target_id        = var.master_node_id
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
