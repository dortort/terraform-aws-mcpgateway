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

  orchestrator    = "eks"
  compute_type    = "ec2"
  gateway_version = "latest"
  replicas        = 2
  db_engine       = "aurora-postgresql"
  enable_redis    = true
  custom_domain   = var.custom_domain
  enable_waf      = true

  jwt_secret_key         = var.jwt_secret_key
  auth_encryption_secret = var.auth_encryption_secret
  admin_email            = var.admin_email
  admin_password         = var.admin_password

  tags = {
    Environment = "production"
    Project     = "mcpgateway"
  }
}

output "alb_url" {
  value = module.mcpgateway.alb_url
}

output "database_endpoint" {
  value = module.mcpgateway.database_endpoint
}
