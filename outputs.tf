output "alb_url" {
  description = "Gateway URL (HTTPS if custom_domain is set)"
  value       = var.custom_domain != "" ? "https://${var.custom_domain}" : "https://${module.load_balancer.alb_dns_name}"
}

output "database_endpoint" {
  description = "RDS/Aurora database endpoint"
  value       = var.db_engine != "sqlite" ? module.database[0].endpoint : null
}

output "redis_endpoint" {
  description = "ElastiCache Redis endpoint"
  value       = var.enable_redis ? module.cache[0].endpoint : null
}

output "iam_role_arns" {
  description = "Map of IAM Role ARNs created by the module"
  value = merge(
    var.orchestrator == "ecs" ? {
      ecs_task_role      = module.ecs[0].task_role_arn
      ecs_execution_role = module.ecs[0].execution_role_arn
    } : {},
    var.orchestrator == "eks" ? {
      eks_node_role = module.eks[0].node_role_arn
    } : {},
  )
}

output "cloudwatch_log_group" {
  description = "CloudWatch Log Group name"
  value       = var.orchestrator == "ecs" ? module.ecs[0].log_group_name : null
}

output "rds_endpoint" {
  description = "RDS/Aurora endpoint (alias for database_endpoint)"
  value       = var.db_engine != "sqlite" ? module.database[0].endpoint : null
}

output "api_gateway_id" {
  description = "WAF Web ACL ID (when WAF is enabled)"
  value       = var.enable_waf ? "waf-enabled" : null
}
