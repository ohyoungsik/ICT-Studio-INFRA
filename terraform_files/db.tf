resource "aws_instance" "db_main" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.db[0].id
  vpc_security_group_ids = [aws_security_group.db.id]
  key_name               = aws_key_pair.app_key.key_name
  iam_instance_profile   = aws_iam_instance_profile.instance_profile.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data_base64 = base64encode(templatefile("${path.module}/db-main-userdata.sh", {
    name_prefix = local.name_prefix
    aws_region  = var.region
    db_name     = var.db_name
    db_user     = var.db_user
    db_password = var.db_password
    db_init_sql = file("${path.module}/../postgres-ha/init.sql")
  }))

  tags = {
    Name        = "${local.name_prefix}-db-main"
    Role        = "db"
    Environment = local.env
  }
}
