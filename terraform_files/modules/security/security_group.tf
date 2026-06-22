# ==============================================
# Security Group 정의 (3가지: ALB, App, DB)
# ==============================================

resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "ALB security group"
  vpc_id      = var.vpc_id
}

# Bastion Host 보안 그룹
resource "aws_security_group" "bastion" {
  name        = "${var.name_prefix}-bastion-sg"
  description = "Bastion host security group"
  vpc_id      = var.vpc_id
}

# 애플리케이션 서버 보안 그룹
resource "aws_security_group" "app" {
  name        = "${var.name_prefix}-app-sg"
  description = "Application servers security group"
  vpc_id      = var.vpc_id
}
# 데이터베이스 보안 그룹

resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-db-sg"
  description = "DB security group"
  vpc_id      = var.vpc_id
}

# master node security group
resource "aws_security_group" "master_node" {
  name        = "${var.name_prefix}-master-node-sg"
  description = "Master node security group"
  vpc_id      = var.vpc_id
}