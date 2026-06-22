resource "aws_instance" "bastion" {
  ami                         = var.ami_id
  instance_type               = "t3.small"
  subnet_id                   = var.public_subnet_ids[0]
  vpc_security_group_ids      = [var.bastion_security_group_id]
  key_name                    = var.key_name
  associate_public_ip_address = true

  iam_instance_profile = var.iam_instance_profile_name

  user_data = templatefile("${path.root}/scripts/userdata.sh", {
    name_prefix = var.name_prefix
    aws_region  = var.region
  })

  tags = {
    Name        = "${var.name_prefix}-bastion"
    Environment = var.env
  }
}
