output "master_node_id" {
  value = aws_instance.master_node.id
}

output "master_node_private_ip" {
  value = aws_instance.master_node.private_ip
}
