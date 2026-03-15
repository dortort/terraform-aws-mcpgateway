output "endpoint" {
  description = "Primary connection endpoint for the database (cluster endpoint for Aurora, address for RDS MySQL)."
  value = var.db_engine == "aurora-postgresql" ? (
    length(aws_rds_cluster.aurora) > 0 ? aws_rds_cluster.aurora[0].endpoint : null
    ) : (
    length(aws_db_instance.mysql) > 0 ? aws_db_instance.mysql[0].address : null
  )
}

output "port" {
  description = "Port on which the database accepts connections (5432 for Aurora PostgreSQL, 3306 for RDS MySQL)."
  value       = var.db_engine == "aurora-postgresql" ? 5432 : 3306
}

output "db_name" {
  description = "Name of the application database."
  value       = "mcpgateway"
}

output "username" {
  description = "Master username for the database."
  value       = "mcpgw_admin"
}

output "db_engine" {
  description = "The database engine in use, as passed in via var.db_engine."
  value       = var.db_engine
}
