output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "List of Public Subnet IDs."
  value       = aws_subnet.public.*.id
}

output "private_app_subnet_ids" {
  description = "List of Private App Subnet IDs."
  value       = aws_subnet.private_app.*.id
}

output "db_subnet_ids" {
  description = "List of DB Subnet IDs."
  value       = aws_subnet.db.*.id
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name."
  value       = aws_lb.application_load_balancer.dns_name
}

output "alb_arn" {
  description = "Application Load Balancer ARN."
  value       = aws_lb.application_load_balancer.arn
}
