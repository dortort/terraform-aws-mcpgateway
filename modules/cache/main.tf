resource "aws_elasticache_subnet_group" "mcpgw" {
  name       = "mcpgw"
  subnet_ids = var.private_subnet_ids

  tags = var.tags
}

resource "aws_elasticache_replication_group" "mcpgw" {
  replication_group_id = "mcpgw"
  description          = "MCP Gateway Redis cache"

  engine         = "redis"
  engine_version = "7.1"
  node_type      = "cache.t4g.medium"
  port           = 6379

  num_cache_clusters   = 2
  parameter_group_name = "default.redis7"

  subnet_group_name  = aws_elasticache_subnet_group.mcpgw.name
  security_group_ids = [var.security_group_id]

  at_rest_encryption_enabled = true
  kms_key_id                 = var.kms_key_arn

  transit_encryption_enabled = true
  auth_token                 = var.auth_token

  automatic_failover_enabled = true
  multi_az_enabled           = true

  tags = var.tags
}
