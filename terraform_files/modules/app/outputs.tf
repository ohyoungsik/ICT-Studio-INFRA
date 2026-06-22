output "asg_name" {
  value = aws_autoscaling_group.app_asg.name
}

output "launch_template_id" {
  value = aws_launch_template.app_lt.id
}
