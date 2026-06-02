# ==============================================
# 출력 값 정의
# ==============================================

# ASG가 관리하는 실행 중인 EC2 인스턴스 목록 조회
data "aws_instances" "app_instances" {
  filter {
    name   = "tag:aws:autoscaling:groupName"
    values = [aws_autoscaling_group.app_asg.name]
  }
  filter {
    name   = "instance-state-name"
    values = ["running", "pending"]
  }
  depends_on = [aws_autoscaling_group.app_asg]
}

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

output "asg_name" {
  description = "Auto Scaling Group name."
  value       = aws_autoscaling_group.app_asg.name
}

output "app_instance_ids" {
  description = "EC2 instance IDs managed by ASG."
  value       = data.aws_instances.app_instances.ids
}

output "app_instance_private_ips" {
  description = "Private IP addresses of app instances."
  value       = data.aws_instances.app_instances.private_ips
}

output "key_pair_name" {
  description = "EC2 Key Pair name."
  value       = aws_key_pair.app_key.key_name
}

output "deployment_summary" {
  description = "Deployment result summary."
  value = <<-EOT

    ========================================
     Deployment Complete!
    ========================================
     ALB DNS      : ${aws_lb.application_load_balancer.dns_name}
     ASG Name     : ${aws_autoscaling_group.app_asg.name}
     Key Pair     : ${aws_key_pair.app_key.key_name}
     Instance IDs : ${join(", ", data.aws_instances.app_instances.ids)}
     Private IPs  : ${join(", ", data.aws_instances.app_instances.private_ips)}
    ========================================
  EOT
}
