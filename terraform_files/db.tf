# --- Postgres HA --- DB Layer EC2 정의 파일이다.
# --- Postgres HA --- db_main은 단일 PostgreSQL 서버가 아니라 PostgreSQL HA용 Swarm manager 및 HAProxy 노드로 사용한다.
# --- Postgres HA --- 실제 PostgreSQL 데이터 노드는 postgres-primary, postgres-replica1, postgres-replica2 고정 EC2 3대이다.

locals {
  # --- Postgres HA --- 세 PostgreSQL 데이터 노드의 AWS Name tag, 역할, 배치할 DB subnet index를 한 곳에서 관리한다.
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

# --- Postgres HA --- 기존 db_main EC2를 재사용해 Swarm manager와 HAProxy 배치 노드로 전환한다.
# --- Postgres HA --- 기존 단일 postgres:15 컨테이너는 더 이상 실행하지 않아 HAProxy의 5432 포트와 충돌하지 않는다.
resource "aws_instance" "db_main" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.db[0].id
  vpc_security_group_ids = [aws_security_group.db.id]
  key_name               = aws_key_pair.app_key.key_name
  iam_instance_profile   = aws_iam_instance_profile.instance_profile.name

  root_block_device {
    # --- Postgres HA --- manager/HAProxy 및 모니터링 컨테이너 실행을 위한 root volume이다.
    volume_size = 20
    volume_type = "gp3"
  }

  # --- Postgres HA --- db_main 역할 변경 시 user-data가 실제로 반영되도록 인스턴스를 교체한다.
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

# --- Postgres HA --- 초기 Primary 역할을 맡는 고정 EC2이다.
# --- Postgres HA --- Ansible에서 이 노드는 Swarm worker로 join하고 primary DB service를 실행한다.
resource "aws_instance" "postgres_primary" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.postgres_ha_instance_type
  subnet_id              = aws_subnet.db[local.postgres_ha_nodes.primary.subnet_index].id
  vpc_security_group_ids = [aws_security_group.db.id]
  key_name               = aws_key_pair.app_key.key_name
  iam_instance_profile   = aws_iam_instance_profile.instance_profile.name

  root_block_device {
    # --- Postgres HA --- PostgreSQL bind mount 데이터는 /data/postgres를 쓰지만, OS/도커 영역도 여유를 둔다.
    volume_size = var.postgres_ha_root_volume_size
    volume_type = "gp3"
  }

  # --- Postgres HA --- EC2 hostname을 Swarm placement constraint와 같은 이름으로 고정한다.
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

# --- Postgres HA --- 첫 번째 Replica 역할을 맡는 고정 EC2이다.
# --- Postgres HA --- repmgr failover 시 primary 다음 승격 후보로 동작한다.
resource "aws_instance" "postgres_replica1" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.postgres_ha_instance_type
  subnet_id              = aws_subnet.db[local.postgres_ha_nodes.replica1.subnet_index].id
  vpc_security_group_ids = [aws_security_group.db.id]
  key_name               = aws_key_pair.app_key.key_name
  iam_instance_profile   = aws_iam_instance_profile.instance_profile.name

  root_block_device {
    # --- Postgres HA --- DB 노드별 동일한 root volume 정책을 적용한다.
    volume_size = var.postgres_ha_root_volume_size
    volume_type = "gp3"
  }

  # --- Postgres HA --- Docker node hostname과 stack.yml placement constraint를 맞춘다.
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

# --- Postgres HA --- 두 번째 Replica 역할을 맡는 고정 EC2이다.
# --- Postgres HA --- HAProxy는 db_main에 배치하므로 이 노드는 PostgreSQL replica2 service만 실행한다.
resource "aws_instance" "postgres_replica2" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.postgres_ha_instance_type
  subnet_id              = aws_subnet.db[local.postgres_ha_nodes.replica2.subnet_index].id
  vpc_security_group_ids = [aws_security_group.db.id]
  key_name               = aws_key_pair.app_key.key_name
  iam_instance_profile   = aws_iam_instance_profile.instance_profile.name

  root_block_device {
    # --- Postgres HA --- 세 DB 노드의 디스크 크기는 같은 변수로 통일한다.
    volume_size = var.postgres_ha_root_volume_size
    volume_type = "gp3"
  }

  # --- Postgres HA --- Ansible 배포 전부터 OS hostname을 목표 노드명으로 맞춘다.
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
