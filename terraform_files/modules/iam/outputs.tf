output "instance_profile_name" {
  value = aws_iam_instance_profile.instance_profile.name
}

output "ec2_instance_role_id" {
  value = aws_iam_role.ec2_instance_role.id
}
