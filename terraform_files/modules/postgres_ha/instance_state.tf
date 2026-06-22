resource "aws_ec2_instance_state" "db_main" {
  instance_id = aws_instance.db_main.id
  state       = "running"
}

resource "aws_ec2_instance_state" "postgres_primary" {
  instance_id = aws_instance.postgres_primary.id
  state       = "running"
}

resource "aws_ec2_instance_state" "postgres_replica1" {
  instance_id = aws_instance.postgres_replica1.id
  state       = "running"
}

resource "aws_ec2_instance_state" "postgres_replica2" {
  instance_id = aws_instance.postgres_replica2.id
  state       = "running"
}
