output "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt secrets"
  value       = aws_kms_key.secrets.arn
  sensitive   = true
}

output "jwt_secret_arn" {
  description = "ARN of the JWT secret key in Secrets Manager"
  value       = aws_secretsmanager_secret.jwt_secret_key.arn
  sensitive   = true
}

output "auth_encryption_secret_arn" {
  description = "ARN of the auth encryption secret in Secrets Manager"
  value       = aws_secretsmanager_secret.auth_encryption_secret.arn
  sensitive   = true
}

output "admin_password_arn" {
  description = "ARN of the admin password secret in Secrets Manager"
  value       = aws_secretsmanager_secret.admin_password.arn
  sensitive   = true
}

output "db_password_arn" {
  description = "ARN of the database password secret in Secrets Manager"
  value       = aws_secretsmanager_secret.db_password.arn
  sensitive   = true
}

output "redis_auth_token_arn" {
  description = "ARN of the Redis auth token secret in Secrets Manager"
  value       = aws_secretsmanager_secret.redis_auth_token.arn
  sensitive   = true
}

output "db_password" {
  description = "Generated database password value (for passing to database module)"
  value       = random_password.db_password.result
  sensitive   = true
}

output "redis_auth_token" {
  description = "Generated Redis auth token value (for passing to cache module)"
  value       = random_password.redis_auth_token.result
  sensitive   = true
}

output "admin_email" {
  description = "Admin email address (pass-through for ECS environment)"
  value       = var.admin_email
  sensitive   = true
}

output "all_secret_arns" {
  description = "List of all secret ARNs managed by this module (for IAM policies)"
  value = [
    aws_secretsmanager_secret.jwt_secret_key.arn,
    aws_secretsmanager_secret.auth_encryption_secret.arn,
    aws_secretsmanager_secret.admin_password.arn,
    aws_secretsmanager_secret.db_password.arn,
    aws_secretsmanager_secret.redis_auth_token.arn,
  ]
  sensitive = true
}
