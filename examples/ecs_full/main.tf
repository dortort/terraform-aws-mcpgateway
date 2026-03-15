# Configure S3 backend (recommended for production)
# terraform {
#   backend "s3" {
#     bucket         = "my-terraform-state"
#     key            = "mcpgateway/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "terraform-locks"
#     encrypt        = true
#   }
# }

provider "aws" {
  region = var.region
}

module "mcpgateway" {
  source = "../../"

  cluster_type    = "ecs"
  gateway_version = "v1.0.0"
  replicas        = 3
  db_engine       = "aurora-postgresql"
  enable_redis    = true
  custom_domain   = var.custom_domain
  enable_waf      = true

  policy_bundle_s3_key = "my-opa-bucket/policies/bundle.tar.gz"

  alb_ingress_cidr_blocks = ["10.0.0.0/8"]

  observability = {
    log_retention_days           = 180
    enable_container_insights    = true
    alarm_5xx_threshold          = 25
    alarm_auth_failure_threshold = 50
  }

  jwt_secret_key         = var.jwt_secret_key
  auth_encryption_secret = var.auth_encryption_secret
  admin_email            = var.admin_email
  admin_password         = var.admin_password

  gateway_env = {
    LOG_LEVEL = "info"
  }

  tags = {
    Environment = "production"
    Project     = "mcpgateway"
    Team        = "platform"
  }
}

output "alb_url" {
  value = module.mcpgateway.alb_url
}

output "database_endpoint" {
  value = module.mcpgateway.database_endpoint
}

output "redis_endpoint" {
  value = module.mcpgateway.redis_endpoint
}

output "cloudwatch_log_group" {
  value = module.mcpgateway.cloudwatch_log_group
}

output "iam_role_arns" {
  value = module.mcpgateway.iam_role_arns
}
