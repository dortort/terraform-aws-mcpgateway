locals {
  vpc_id             = var.create_vpc ? aws_vpc.mcpgw[0].id : var.vpc_id
  private_subnet_ids = var.create_vpc ? [aws_subnet.mcpgw_private[0].id, aws_subnet.mcpgw_private[1].id] : var.private_subnet_ids
  public_subnet_ids  = var.create_vpc ? [aws_subnet.mcpgw_public[0].id, aws_subnet.mcpgw_public[1].id] : var.public_subnet_ids

  db_port = var.db_engine == "aurora-postgresql" ? 5432 : 3306
}

# ---------------------------------------------------------------------------
# Data Sources
# ---------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

# ---------------------------------------------------------------------------
# VPC (conditional)
# ---------------------------------------------------------------------------

resource "aws_vpc" "mcpgw" {
  count = var.create_vpc ? 1 : 0

  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "mcpgw-vpc" })
}

# ---------------------------------------------------------------------------
# Subnets
# ---------------------------------------------------------------------------

resource "aws_subnet" "mcpgw_public" {
  count = var.create_vpc ? 2 : 0

  vpc_id                  = aws_vpc.mcpgw[0].id
  cidr_block              = count.index == 0 ? "10.0.1.0/24" : "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, { Name = "mcpgw-public-${count.index + 1}" })
}

resource "aws_subnet" "mcpgw_private" {
  count = var.create_vpc ? 2 : 0

  vpc_id            = aws_vpc.mcpgw[0].id
  cidr_block        = count.index == 0 ? "10.0.10.0/24" : "10.0.11.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(var.tags, { Name = "mcpgw-private-${count.index + 1}" })
}

# ---------------------------------------------------------------------------
# Internet Gateway
# ---------------------------------------------------------------------------

resource "aws_internet_gateway" "mcpgw" {
  count = var.create_vpc ? 1 : 0

  vpc_id = aws_vpc.mcpgw[0].id

  tags = merge(var.tags, { Name = "mcpgw-igw" })
}

# ---------------------------------------------------------------------------
# NAT Gateway (single, in first public subnet)
# ---------------------------------------------------------------------------

resource "aws_eip" "mcpgw_nat" {
  count = var.create_vpc ? 1 : 0

  domain = "vpc"

  tags = merge(var.tags, { Name = "mcpgw-nat-eip" })

  depends_on = [aws_internet_gateway.mcpgw]
}

resource "aws_nat_gateway" "mcpgw" {
  count = var.create_vpc ? 1 : 0

  allocation_id = aws_eip.mcpgw_nat[0].id
  subnet_id     = aws_subnet.mcpgw_public[0].id

  tags = merge(var.tags, { Name = "mcpgw-nat-gw" })

  depends_on = [aws_internet_gateway.mcpgw]
}

# ---------------------------------------------------------------------------
# Route Tables
# ---------------------------------------------------------------------------

resource "aws_route_table" "mcpgw_public" {
  count = var.create_vpc ? 1 : 0

  vpc_id = aws_vpc.mcpgw[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mcpgw[0].id
  }

  tags = merge(var.tags, { Name = "mcpgw-public-rt" })
}

resource "aws_route_table_association" "mcpgw_public" {
  count = var.create_vpc ? 2 : 0

  subnet_id      = aws_subnet.mcpgw_public[count.index].id
  route_table_id = aws_route_table.mcpgw_public[0].id
}

resource "aws_route_table" "mcpgw_private" {
  count = var.create_vpc ? 1 : 0

  vpc_id = aws_vpc.mcpgw[0].id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.mcpgw[0].id
  }

  tags = merge(var.tags, { Name = "mcpgw-private-rt" })
}

resource "aws_route_table_association" "mcpgw_private" {
  count = var.create_vpc ? 2 : 0

  subnet_id      = aws_subnet.mcpgw_private[count.index].id
  route_table_id = aws_route_table.mcpgw_private[0].id
}

# ---------------------------------------------------------------------------
# VPC Flow Logs
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "mcpgw_flow_logs" {
  count = var.create_vpc ? 1 : 0

  name              = "/aws/vpc/mcpgw-flow-logs"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, { Name = "mcpgw-flow-logs" })
}

resource "aws_iam_role" "mcpgw_flow_logs" {
  count = var.create_vpc ? 1 : 0

  name = "mcpgw-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "mcpgw_flow_logs" {
  count = var.create_vpc ? 1 : 0

  name = "mcpgw-vpc-flow-logs-policy"
  role = aws_iam_role.mcpgw_flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_flow_log" "mcpgw" {
  count = var.create_vpc ? 1 : 0

  vpc_id          = aws_vpc.mcpgw[0].id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.mcpgw_flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.mcpgw_flow_logs[0].arn

  tags = merge(var.tags, { Name = "mcpgw-flow-log" })
}

# ---------------------------------------------------------------------------
# Security Group: ALB
# ---------------------------------------------------------------------------

resource "aws_security_group" "mcpgw_alb" {
  name        = "mcpgw-alb-sg"
  description = "Security group for the MCP Gateway Application Load Balancer"
  vpc_id      = local.vpc_id

  ingress {
    description = "HTTPS from allowed CIDRs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.alb_ingress_cidr_blocks
  }

  ingress {
    description = "HTTP from allowed CIDRs"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.alb_ingress_cidr_blocks
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "mcpgw-alb-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Security Group: Gateway
# ---------------------------------------------------------------------------

resource "aws_security_group" "mcpgw_gateway" {
  name        = "mcpgw-gateway-sg"
  description = "Security group for the MCP Gateway service containers"
  vpc_id      = local.vpc_id

  ingress {
    description     = "MCP Gateway port from ALB only"
    from_port       = 4444
    to_port         = 4444
    protocol        = "tcp"
    security_groups = [aws_security_group.mcpgw_alb.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "mcpgw-gateway-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Security Group: Database
# ---------------------------------------------------------------------------

resource "aws_security_group" "mcpgw_database" {
  name        = "mcpgw-database-sg"
  description = "Security group for the MCP Gateway database"
  vpc_id      = local.vpc_id

  ingress {
    description     = "Database port from gateway only"
    from_port       = local.db_port
    to_port         = local.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.mcpgw_gateway.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "mcpgw-database-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Security Group: Redis (conditional)
# ---------------------------------------------------------------------------

resource "aws_security_group" "mcpgw_redis" {
  count = var.enable_redis ? 1 : 0

  name        = "mcpgw-redis-sg"
  description = "Security group for the MCP Gateway Redis cache"
  vpc_id      = local.vpc_id

  ingress {
    description     = "Redis port from gateway only"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.mcpgw_gateway.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "mcpgw-redis-sg" })

  lifecycle {
    create_before_destroy = true
  }
}
