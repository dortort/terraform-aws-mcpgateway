output "endpoint" {
  description = "Primary endpoint address of the Redis replication group"
  value       = aws_elasticache_replication_group.mcpgw.primary_endpoint_address
}

output "port" {
  description = "Port the Redis replication group listens on"
  value       = aws_elasticache_replication_group.mcpgw.port
}
