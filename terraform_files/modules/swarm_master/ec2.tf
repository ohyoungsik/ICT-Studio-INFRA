# init
data "cloudinit_config" "master_node" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/x-shellscript"
    content = templatefile("${path.root}/../scripts/master-node-bootstrap.sh", {
      name_prefix = var.name_prefix
      aws_region  = var.region
    })
  }

  part {
    content_type = "text/x-shellscript"
    content      = file("${path.root}/../scripts/portainer-init.sh")
  }
}

# master node instance
resource "aws_instance" "master_node" {
  ami                    = var.ami_id
  instance_type          = "t3.small"
  key_name               = var.key_name
  iam_instance_profile   = var.iam_instance_profile_name
  vpc_security_group_ids = [var.master_node_security_group_id]
  subnet_id              = var.private_app_subnet_ids[0]

  user_data_base64            = data.cloudinit_config.master_node.rendered
  user_data_replace_on_change = false

  lifecycle {
    ignore_changes = [user_data_base64]
  }

  tags = {
    Name        = "${var.name_prefix}-master-node"
    Role        = "master"
    Environment = var.env
  }
}
