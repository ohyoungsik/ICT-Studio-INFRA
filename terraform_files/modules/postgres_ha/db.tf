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
  ami                    = var.ami_id
  instance_type          = "t3.small"
  subnet_id              = var.db_subnet_ids[0]
  vpc_security_group_ids = [var.db_security_group_id]
  key_name               = var.key_name
  iam_instance_profile   = var.iam_instance_profile_name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data_replace_on_change = true
  user_data_base64 = base64encode(templatefile("${path.root}/scripts/db-main-userdata.sh", {
    hostname = "db-main"
  }))

  tags = {
    Name        = "${var.name_prefix}-db-main"
    Role        = "db"
    SwarmRole   = "manager"
    Project     = "Ticketing-HA"
    Environment = var.env
  }
}

resource "aws_instance" "postgres_primary" {
  ami                    = var.ami_id
  instance_type          = var.postgres_ha_instance_type
  subnet_id              = var.db_subnet_ids[local.postgres_ha_nodes.primary.subnet_index]
  vpc_security_group_ids = [var.db_security_group_id]
  key_name               = var.key_name
  iam_instance_profile   = var.iam_instance_profile_name

  root_block_device {
    volume_size = var.postgres_ha_root_volume_size
    volume_type = "gp3"
  }

  user_data_replace_on_change = true
  user_data = templatefile("${path.root}/scripts/postgres-ha-userdata.sh", {
    hostname = local.postgres_ha_nodes.primary.name
  })

  tags = {
    Name        = local.postgres_ha_nodes.primary.name
    Role        = "postgres-primary"
    Project     = "Ticketing-HA"
    Environment = var.env
  }
}

resource "aws_instance" "postgres_replica1" {
  ami                    = var.ami_id
  instance_type          = var.postgres_ha_instance_type
  subnet_id              = var.db_subnet_ids[local.postgres_ha_nodes.replica1.subnet_index]
  vpc_security_group_ids = [var.db_security_group_id]
  key_name               = var.key_name
  iam_instance_profile   = var.iam_instance_profile_name

  root_block_device {
    volume_size = var.postgres_ha_root_volume_size
    volume_type = "gp3"
  }

  user_data_replace_on_change = true
  user_data = templatefile("${path.root}/scripts/postgres-ha-userdata.sh", {
    hostname = local.postgres_ha_nodes.replica1.name
  })

  tags = {
    Name        = local.postgres_ha_nodes.replica1.name
    Role        = "postgres-replica"
    Project     = "Ticketing-HA"
    Environment = var.env
  }
}

resource "aws_instance" "postgres_replica2" {
  ami                    = var.ami_id
  instance_type          = var.postgres_ha_instance_type
  subnet_id              = var.db_subnet_ids[local.postgres_ha_nodes.replica2.subnet_index]
  vpc_security_group_ids = [var.db_security_group_id]
  key_name               = var.key_name
  iam_instance_profile   = var.iam_instance_profile_name

  root_block_device {
    volume_size = var.postgres_ha_root_volume_size
    volume_type = "gp3"
  }

  user_data_replace_on_change = true
  user_data = templatefile("${path.root}/scripts/postgres-ha-userdata.sh", {
    hostname = local.postgres_ha_nodes.replica2.name
  })

  tags = {
    Name        = local.postgres_ha_nodes.replica2.name
    Role        = "postgres-replica"
    Project     = "Ticketing-HA"
    Environment = var.env
  }
}
