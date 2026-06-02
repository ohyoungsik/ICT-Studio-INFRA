resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  key_name                    = aws_key_pair.app_key.key_name
  associate_public_ip_address = true

  tags = {
    Name        = "${local.name_prefix}-bastion"
    Environment = local.env
  }
}
