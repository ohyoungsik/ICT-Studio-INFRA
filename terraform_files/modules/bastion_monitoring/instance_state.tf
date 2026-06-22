resource "aws_ec2_instance_state" "bastion" {
  instance_id = aws_instance.bastion.id
  state       = "running"
}
