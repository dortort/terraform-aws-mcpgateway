# KMS Customer Managed Key for secrets encryption
resource "aws_kms_key" "secrets" {
  description             = "MCP Gateway secrets encryption key"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  tags = var.tags
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/mcpgw-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# Generated passwords
resource "random_password" "db_password" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+"
}

resource "random_password" "redis_auth_token" {
  length  = 64
  special = false
}

# JWT secret key
resource "aws_secretsmanager_secret" "jwt_secret_key" {
  name       = "mcpgw/jwt-secret-key"
  kms_key_id = aws_kms_key.secrets.key_id

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "jwt_secret_key" {
  secret_id     = aws_secretsmanager_secret.jwt_secret_key.id
  secret_string = var.jwt_secret_key
}

# Auth encryption secret
resource "aws_secretsmanager_secret" "auth_encryption_secret" {
  name       = "mcpgw/auth-encryption-secret"
  kms_key_id = aws_kms_key.secrets.key_id

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "auth_encryption_secret" {
  secret_id     = aws_secretsmanager_secret.auth_encryption_secret.id
  secret_string = var.auth_encryption_secret
}

# Admin password
resource "aws_secretsmanager_secret" "admin_password" {
  name       = "mcpgw/admin-password"
  kms_key_id = aws_kms_key.secrets.key_id

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "admin_password" {
  secret_id     = aws_secretsmanager_secret.admin_password.id
  secret_string = var.admin_password
}

# Database password
resource "aws_secretsmanager_secret" "db_password" {
  name       = "mcpgw/db-password"
  kms_key_id = aws_kms_key.secrets.key_id

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_password.result
}

# Redis auth token
resource "aws_secretsmanager_secret" "redis_auth_token" {
  name       = "mcpgw/redis-auth-token"
  kms_key_id = aws_kms_key.secrets.key_id

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "redis_auth_token" {
  secret_id     = aws_secretsmanager_secret.redis_auth_token.id
  secret_string = random_password.redis_auth_token.result
}
