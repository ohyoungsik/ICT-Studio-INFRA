# --- Postgres HA --- DB Layer EC2 definitions.
# db_main is the PostgreSQL HA Swarm manager and HAProxy node.
# Actual PostgreSQL data nodes are fixed EC2 instances: primary, replica1, replica2.

locals {
  postgres_ha_nodes = {
    primary = {
      name         = "postgres-primary"
      role         = "primary"
      subnet_index = 0
    }
    replica1 = {
      name         = "postgres-replica1"
      role         = "replica"
      subnet_index = 1
    }
    replica2 = {
      name         = "postgres-replica2"
      role         = "replica"
      subnet_index = 0
    }
  }
}

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

  user_data_replace_on_change = true
  user_data_base64 = base64encode(templatefile("${path.module}/db-main-userdata.sh", {
    hostname = "db-main"
  }))

  tags = {
    Name        = "${local.name_prefix}-db-main"
    Role        = "db"
    SwarmRole   = "manager"
    Project     = "Ticketing-HA"
    Environment = local.env
  }
}

resource "aws_instance" "postgres_primary" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.postgres_ha_instance_type
  subnet_id              = aws_subnet.db[local.postgres_ha_nodes.primary.subnet_index].id
  vpc_security_group_ids = [aws_security_group.db.id]
  key_name               = aws_key_pair.app_key.key_name
  iam_instance_profile   = aws_iam_instance_profile.instance_profile.name

  root_block_device {
    volume_size = var.postgres_ha_root_volume_size
    volume_type = "gp3"
  }

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/postgres-ha-userdata.sh", {
    hostname = local.postgres_ha_nodes.primary.name
  })

  tags = {
    Name        = local.postgres_ha_nodes.primary.name
    Role        = "postgres-primary"
    Project     = "Ticketing-HA"
    Environment = local.env
  }
}

resource "aws_instance" "postgres_replica1" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.postgres_ha_instance_type
  subnet_id              = aws_subnet.db[local.postgres_ha_nodes.replica1.subnet_index].id
  vpc_security_group_ids = [aws_security_group.db.id]
  key_name               = aws_key_pair.app_key.key_name
  iam_instance_profile   = aws_iam_instance_profile.instance_profile.name

  root_block_device {
    volume_size = var.postgres_ha_root_volume_size
    volume_type = "gp3"
  }

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/postgres-ha-userdata.sh", {
    hostname = local.postgres_ha_nodes.replica1.name
  })

  tags = {
    Name        = local.postgres_ha_nodes.replica1.name
    Role        = "postgres-replica"
    Project     = "Ticketing-HA"
    Environment = local.env
  }
}

resource "aws_instance" "postgres_replica2" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.postgres_ha_instance_type
  subnet_id              = aws_subnet.db[local.postgres_ha_nodes.replica2.subnet_index].id
  vpc_security_group_ids = [aws_security_group.db.id]
  key_name               = aws_key_pair.app_key.key_name
  iam_instance_profile   = aws_iam_instance_profile.instance_profile.name

  root_block_device {
    volume_size = var.postgres_ha_root_volume_size
    volume_type = "gp3"
  }

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/postgres-ha-userdata.sh", {
    hostname = local.postgres_ha_nodes.replica2.name
  })

  tags = {
    Name        = local.postgres_ha_nodes.replica2.name
    Role        = "postgres-replica"
    Project     = "Ticketing-HA"
    Environment = local.env
  }
}
