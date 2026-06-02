resource "aws_security_group" "alb" {
  name        = "${var.environment}-alb-sg"
  description = "ALB 용 Security Group"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group" "app" {
  name        = "${var.environment}-app-sg"
  description = "Application 서버용 Security Group"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group" "db" {
  name        = "${var.environment}-db-sg"
  description = "DB 서버용 Security Group"
  vpc_id      = aws_vpc.main.id
}
