# ==============================================
# Subnet 설정 (3가지 계층)
# ==============================================
# 디렉토리를 a, c 두 AZ으로 나눘어 고가용성 달성

locals {

  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

# Public Subnet: ALB, NAT Gateway 위치 (uc778터넷 접근 스늸)
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${local.name_prefix}-public-subnet-${local.az_suffix[count.index]}"
    Environment = local.env
    Tier        = "public"
  }
}

# Private App Subnet: EC2(애플리케이션 서버) 위치 (outside 접근 차단)
resource "aws_subnet" "private_app" {
  count             = length(var.private_app_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_app_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name        = "${local.name_prefix}-private-app-subnet-${local.az_suffix[count.index]}"
    Environment = local.env
    Tier        = "private-app"
  }
}

# DB Subnet: RDS 데이터베이스 위치 (App에서만 접근)
resource "aws_subnet" "db" {
  count             = length(var.db_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.db_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name        = "${local.name_prefix}-db-subnet-${local.az_suffix[count.index]}"
    Environment = local.env
    Tier        = "db"
  }
}
