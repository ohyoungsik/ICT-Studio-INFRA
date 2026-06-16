# init
data "cloudinit_config" "master_node" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/../scripts/master-node-bootstrap.sh", {
      name_prefix = local.name_prefix
      aws_region  = var.region
    })
  }

  part {
    content_type = "text/x-shellscript"
    content      = file("${path.module}/../scripts/portainer-init.sh")
  }
}

# master node instance
resource "aws_instance" "master_node" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.small"
  key_name               = aws_key_pair.app_key.key_name
  iam_instance_profile   = aws_iam_instance_profile.instance_profile.name
  vpc_security_group_ids = [aws_security_group.master_node.id]
  subnet_id              = aws_subnet.private_app[0].id

  user_data_base64            = data.cloudinit_config.master_node.rendered
  user_data_replace_on_change = true

  tags = {
    Name        = "${local.name_prefix}-master-node"
    Role        = "master"
    Environment = local.env
  }
}
