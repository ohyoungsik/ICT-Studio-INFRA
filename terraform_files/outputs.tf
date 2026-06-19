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

output "portainer_url" {
  description = "Portainer web UI URL via ALB (HTTP)."
  value       = "http://${aws_lb.application_load_balancer.dns_name}:9000"
}

output "alb_arn" {
  description = "Application Load Balancer ARN."
  value       = aws_lb.application_load_balancer.arn
}

output "backend_target_group_arn" {
  description = "Backend target group ARN."
  value       = aws_lb_target_group.backend.arn
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

output "private_key_secret_name" {
  description = "Secrets Manager secret name containing the generated private SSH key."
  value       = aws_secretsmanager_secret.private_key.name
}

output "private_key_download_command" {
  description = "Command to download the generated private SSH key from Secrets Manager."
  value       = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.private_key.name} --query SecretString --output text > ${var.key_name}.pem"
}

output "db_main_private_ip" {
  description = "DB Main EC2 private IP address."
  value       = aws_instance.db_main.private_ip
}

output "bastion_public_ip" {
  description = "Bastion host public IP address."
  value       = aws_instance.bastion.public_ip
}

output "master_node_private_ip" {
  description = "Swarm manager / Redis host private IP."
  value       = aws_instance.master_node.private_ip
}

output "redis_ssm_parameters" {
  description = "SSM Parameter Store paths for Redis connection."
  value = {
    host     = "/${local.name_prefix}/redis/host"
    port     = "/${local.name_prefix}/redis/port"
    password = "/${local.name_prefix}/redis/password"
  }
}

output "db_ssm_parameters" {
  description = "SSM Parameter Store paths for PostgreSQL connection."
  value = {
    host     = aws_ssm_parameter.db_host.name
    port     = aws_ssm_parameter.db_port.name
    name     = aws_ssm_parameter.db_name.name
    user     = aws_ssm_parameter.db_user.name
    password = aws_ssm_parameter.db_password.name
  }
}

output "deployment_summary" {
  description = "Deployment result summary."
  value       = <<-EOT

    ========================================
     Deployment Complete!
    ========================================
     ALB DNS      : ${aws_lb.application_load_balancer.dns_name}
     Portainer    : http://${aws_lb.application_load_balancer.dns_name}:9000
     Bastion IP   : ${aws_instance.bastion.public_ip}
     DB Main IP   : ${aws_instance.db_main.private_ip}
     Master IP    : ${aws_instance.master_node.private_ip} (Swarm / Redis)
     Redis SSM    : /${local.name_prefix}/redis/*
     DB Main IP   : ${aws_instance.db_main.private_ip}
     DB SSM       : /${local.name_prefix}/db/*
     ASG Name     : ${aws_autoscaling_group.app_asg.name}
     Key Pair     : ${aws_key_pair.app_key.key_name}
     Key Secret   : ${aws_secretsmanager_secret.private_key.name}
     Instance IDs : ${join(", ", data.aws_instances.app_instances.ids)}
     Private IPs  : ${join(", ", data.aws_instances.app_instances.private_ips)}
    ========================================
  EOT
}
