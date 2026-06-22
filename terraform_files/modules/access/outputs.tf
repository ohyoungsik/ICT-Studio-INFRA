output "key_name" {
  value = aws_key_pair.app_key.key_name
}

output "private_key_secret_name" {
  value = aws_secretsmanager_secret.private_key.name
}
