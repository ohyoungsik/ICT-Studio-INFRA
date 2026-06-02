resource "aws_security_group" "alb" {
  name        = "${var.environment}-alb-sg"
  description = "ALB security group"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group" "app" {
  name        = "${var.environment}-app-sg"
  description = "Application servers security group"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group" "db" {
  name        = "${var.environment}-db-sg"
  description = "DB security group"
  vpc_id      = aws_vpc.main.id
}
