terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

resource "random_password" "db" {
  length  = 24
  special = false
}

# Isolated VPC for RDS — no peering with egress VPC.
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-rds-vpc" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-rds-igw" })
}

# Two public subnets — RDS subnet group requires at least 2 AZs.
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 3, count.index)
  availability_zone = var.azs[count.index]

  tags = merge(var.tags, { Name = "${var.name_prefix}-rds-public-${count.index}" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-rds-rt" })
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.name_prefix}-rds-subnet-group"
  subnet_ids = aws_subnet.public[*].id

  tags = merge(var.tags, { Name = "${var.name_prefix}-rds-subnet-group" })
}

# SG: only allow inbound 5432 from the static NAT GW IP.
resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds-sg"
  description = "Allow inbound 5432 from static egress NAT GW IP only."
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-rds-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_nat" {
  security_group_id = aws_security_group.rds.id
  cidr_ipv4         = "${var.nat_eip_public_ip}/32"
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  description       = "Proxy NAT GW static IP to RDS :5432"
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_databricks" {
  for_each = toset(var.databricks_egress_cidrs)

  security_group_id = aws_security_group.rds.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  description       = "Databricks serverless direct to RDS :5432"
}

resource "aws_vpc_security_group_egress_rule" "rds_all" {
  security_group_id = aws_security_group.rds.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_db_instance" "main" {
  identifier             = "${var.name_prefix}-rds-test"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = var.instance_class
  allocated_storage      = 20
  storage_type           = "gp2"
  db_name                = var.db_name
  username               = var.db_username
  password               = random_password.db.result
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = true
  skip_final_snapshot    = true
  deletion_protection    = false
  multi_az               = false

  tags = merge(var.tags, { Name = "${var.name_prefix}-rds-test" })
}
