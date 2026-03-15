# -----------------------------------------------------------------------
# DB Subnet Group (shared by both engines)
# -----------------------------------------------------------------------
resource "aws_db_subnet_group" "this" {
  name        = "mcpgw-db-subnet-group"
  subnet_ids  = var.private_subnet_ids
  description = "Subnet group for MCP Gateway database"

  tags = merge(var.tags, {
    Name = "mcpgw-db-subnet-group"
  })
}

# -----------------------------------------------------------------------
# Aurora PostgreSQL Serverless v2
# -----------------------------------------------------------------------
resource "aws_rds_cluster" "aurora" {
  count = var.db_engine == "aurora-postgresql" ? 1 : 0

  cluster_identifier = "mcpgw-aurora-cluster"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"

  database_name   = "mcpgateway"
  master_username = "mcpgw_admin"
  master_password = var.db_password

  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  deletion_protection       = true
  backup_retention_period   = 7
  skip_final_snapshot       = false
  final_snapshot_identifier = "mcpgw-final-snapshot"

  vpc_security_group_ids = [var.security_group_id]
  db_subnet_group_name   = aws_db_subnet_group.this.name

  enabled_cloudwatch_logs_exports = ["postgresql"]

  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 4
  }

  tags = merge(var.tags, {
    Name = "mcpgw-aurora-cluster"
  })
}

resource "aws_rds_cluster_instance" "aurora" {
  count = var.db_engine == "aurora-postgresql" ? 1 : 0

  identifier         = "mcpgw-aurora-instance-1"
  cluster_identifier = aws_rds_cluster.aurora[0].id
  engine             = "aurora-postgresql"
  instance_class     = "db.serverless"

  db_subnet_group_name = aws_db_subnet_group.this.name

  tags = merge(var.tags, {
    Name = "mcpgw-aurora-instance-1"
  })
}

# -----------------------------------------------------------------------
# RDS MySQL
# -----------------------------------------------------------------------
resource "aws_db_instance" "mysql" {
  count = var.db_engine == "rds-mysql" ? 1 : 0

  identifier     = "mcpgw-mysql"
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t4g.medium"

  db_name  = "mcpgateway"
  username = "mcpgw_admin"
  password = var.db_password

  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  deletion_protection       = true
  backup_retention_period   = 7
  skip_final_snapshot       = false
  final_snapshot_identifier = "mcpgw-final-snapshot"

  vpc_security_group_ids = [var.security_group_id]
  db_subnet_group_name   = aws_db_subnet_group.this.name

  allocated_storage     = 20
  max_allocated_storage = 100

  multi_az = true

  tags = merge(var.tags, {
    Name = "mcpgw-mysql"
  })
}
