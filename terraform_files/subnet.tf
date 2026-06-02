locals {
  azs       = slice(data.aws_availability_zones.available.names, 0, 2)
}

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
