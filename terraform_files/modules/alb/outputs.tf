output "alb_dns_name" {
  value = aws_lb.application_load_balancer.dns_name
}

output "alb_arn" {
  value = aws_lb.application_load_balancer.arn
}

output "backend_target_group_arn" {
  value = aws_lb_target_group.backend.arn
}
