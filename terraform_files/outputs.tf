# ==============================================
# 출력 값 정의
# ==============================================

# ASG가 관리하는 실행 중인 EC2 인스턴스 목록 조회
data "aws_instances" "app_instances" {
  filter {
    name   = "tag:aws:autoscaling:groupName"
    values = [module.app.asg_name]
  }

  filter {
    name   = "instance-state-name"
    values = ["running", "pending"]
  }

  depends_on = [module.app]
}

output "vpc_id" {
  description = "ID of the created VPC."
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "List of Public Subnet IDs."
  value       = module.network.public_subnet_ids
}

output "private_app_subnet_ids" {
  description = "List of Private App Subnet IDs."
  value       = module.network.private_app_subnet_ids
}

output "db_subnet_ids" {
  description = "List of DB Subnet IDs."
  value       = module.network.db_subnet_ids
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name."
  value       = module.alb.alb_dns_name
}

output "portainer_url" {
  description = "Portainer web UI URL via ALB (HTTP)."
  value       = "http://${module.alb.alb_dns_name}:9000"
}

output "alb_arn" {
  description = "Application Load Balancer ARN."
  value       = module.alb.alb_arn
}

output "backend_target_group_arn" {
  description = "Backend target group ARN."
  value       = module.alb.backend_target_group_arn
}

output "asg_name" {
  description = "Auto Scaling Group name."
  value       = module.app.asg_name
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
  value       = module.access.key_name
}

output "private_key_secret_name" {
  description = "Secrets Manager secret name containing the generated private SSH key."
  value       = module.access.private_key_secret_name
}

output "private_key_download_command" {
  description = "Command to download the generated private SSH key from Secrets Manager."
  value       = "aws secretsmanager get-secret-value --secret-id ${module.access.private_key_secret_name} --query SecretString --output text > ${var.key_name}.pem"
}

output "db_main_private_ip" {
  description = "DB Main EC2 private IP address."
  value       = module.postgres_ha.db_main_private_ip
}

output "postgres_primary_private_ip" {
  description = "PostgreSQL HA primary EC2 private IP address."
  value       = module.postgres_ha.postgres_primary_private_ip
}

output "postgres_replica1_private_ip" {
  description = "PostgreSQL HA replica1 EC2 private IP address."
  value       = module.postgres_ha.postgres_replica1_private_ip
}

output "postgres_replica2_private_ip" {
  description = "PostgreSQL HA replica2 EC2 private IP address."
  value       = module.postgres_ha.postgres_replica2_private_ip
}

output "postgres_ha_private_ips" {
  description = "PostgreSQL HA node private IP addresses."
  value = {
    primary  = module.postgres_ha.postgres_primary_private_ip
    replica1 = module.postgres_ha.postgres_replica1_private_ip
    replica2 = module.postgres_ha.postgres_replica2_private_ip
  }
}

output "postgres_ha_haproxy_endpoint" {
  description = "Private PostgreSQL HAProxy write endpoint hosted on db_main manager node."
  value       = "${module.postgres_ha.db_main_private_ip}:5432"
}

output "postgres_ha_ansible_inventory" {
  description = "Run this inventory from ansible_files after terraform apply."
  value       = "cd ../ansible_files && ansible-inventory --list"
}

output "bastion_public_ip" {
  description = "Bastion host public IP address."
  value       = module.bastion_monitoring.bastion_public_ip
}

output "master_node_private_ip" {
  description = "Swarm manager / Redis host private IP."
  value       = module.swarm_master.master_node_private_ip
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
  value       = module.postgres_ha.db_ssm_parameters
}

output "deployment_summary" {
  description = "Deployment result summary."
  value       = <<-EOT

    ========================================
     Deployment Complete!
    ========================================
     ALB DNS      : ${module.alb.alb_dns_name}
     Portainer    : http://${module.alb.alb_dns_name}:9000
     Bastion IP   : ${module.bastion_monitoring.bastion_public_ip}
     DB Main IP   : ${module.postgres_ha.db_main_private_ip}
     PG Primary   : ${module.postgres_ha.postgres_primary_private_ip}
     PG Replica1  : ${module.postgres_ha.postgres_replica1_private_ip}
     PG Replica2  : ${module.postgres_ha.postgres_replica2_private_ip}
     PG HAProxy   : ${module.postgres_ha.db_main_private_ip}:5432
     Master IP    : ${module.swarm_master.master_node_private_ip} (Swarm / Redis)
     Redis SSM    : /${local.name_prefix}/redis/*
     DB Main IP   : ${module.postgres_ha.db_main_private_ip}
     DB SSM       : /${local.name_prefix}/db/*
     ASG Name     : ${module.app.asg_name}
     Key Pair     : ${module.access.key_name}
     Key Secret   : ${module.access.private_key_secret_name}
     Instance IDs : ${join(", ", data.aws_instances.app_instances.ids)}
     Private IPs  : ${join(", ", data.aws_instances.app_instances.private_ips)}
    ========================================
  EOT
}
