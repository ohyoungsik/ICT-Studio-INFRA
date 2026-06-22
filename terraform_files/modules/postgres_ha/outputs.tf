output "db_main_private_ip" {
  value = aws_instance.db_main.private_ip
}

output "postgres_primary_private_ip" {
  value = aws_instance.postgres_primary.private_ip
}

output "postgres_replica1_private_ip" {
  value = aws_instance.postgres_replica1.private_ip
}

output "postgres_replica2_private_ip" {
  value = aws_instance.postgres_replica2.private_ip
}

output "db_ssm_parameters" {
  value = {
    host     = aws_ssm_parameter.db_host.name
    port     = aws_ssm_parameter.db_port.name
    name     = aws_ssm_parameter.db_name.name
    user     = aws_ssm_parameter.db_user.name
    password = aws_ssm_parameter.db_password.name
  }
}
