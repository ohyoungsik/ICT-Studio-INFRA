resource "aws_ec2_instance_state" "master_node" {
  instance_id = aws_instance.master_node.id
  state       = "running"
}
