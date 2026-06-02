# ==============================================
# VPC 및 네트워크 인프라 설정
# ==============================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${local.name_prefix}-vpc"
    Environment = local.env
  }
}

# Internet Gateway: VPC에서 인터넷으로나가는 출입구
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${local.name_prefix}-igw"
    Environment = local.env
  }
}

# Elastic IP: NAT Gateway가 사용할 공유 IP
resource "aws_eip" "nat" {
  tags = {
    Name        = "${local.name_prefix}-nat-eip"
    Environment = local.env
  }
}

# NAT Gateway: Private Subnet의 EC2가 외부 인터넷 나가기 가능 (outside -> inside 차단)
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  depends_on = [aws_internet_gateway.main]

  tags = {
    Name        = "${local.name_prefix}-nat"
    Environment = local.env
  }
}
