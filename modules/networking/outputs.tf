output "vpc_id" {
  description = "ID of the VPC used by the MCP Gateway deployment."
  value       = local.vpc_id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs available to the MCP Gateway."
  value       = local.private_subnet_ids
}

output "public_subnet_ids" {
  description = "List of public subnet IDs available to the MCP Gateway."
  value       = local.public_subnet_ids
}

output "alb_security_group_id" {
  description = "ID of the security group attached to the Application Load Balancer."
  value       = aws_security_group.mcpgw_alb.id
}

output "gateway_security_group_id" {
  description = "ID of the security group attached to the MCP Gateway service containers."
  value       = aws_security_group.mcpgw_gateway.id
}

output "database_security_group_id" {
  description = "ID of the security group attached to the database."
  value       = aws_security_group.mcpgw_database.id
}

output "redis_security_group_id" {
  description = "ID of the security group attached to Redis. Empty string if enable_redis is false."
  value       = var.enable_redis ? aws_security_group.mcpgw_redis[0].id : ""
}
