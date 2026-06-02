output "vpc_id" {
  description = "생성된 VPC ID입니다."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public Subnet ID 목록입니다."
  value       = aws_subnet.public.*.id
}

output "private_app_subnet_ids" {
  description = "Private App Subnet ID 목록입니다."
  value       = aws_subnet.private_app.*.id
}

output "db_subnet_ids" {
  description = "DB Subnet ID 목록입니다."
  value       = aws_subnet.db.*.id
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS 이름입니다."
  value       = aws_lb.application_load_balancer.dns_name
}

output "alb_arn" {
  description = "Application Load Balancer ARN입니다."
  value       = aws_lb.application_load_balancer.arn
}
