variable "gateway_version" {
  description = "Container image tag for the MCP Gateway"
  type        = string
}

variable "replicas" {
  description = "Desired count of ECS tasks"
  type        = number
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for the gateway ECS service"
  type        = string
}

variable "target_group_arn" {
  description = "ALB target group ARN to register ECS tasks with"
  type        = string
}

variable "secret_arns" {
  description = "ARNs of Secrets Manager secrets required by the gateway"
  type = object({
    jwt_secret_key         = string
    auth_encryption_secret = string
    admin_password         = string
    db_password            = string
    redis_auth_token       = string
  })
}

variable "admin_email" {
  description = "Platform admin email address"
  type        = string
}

variable "db_endpoint" {
  description = "Database endpoint hostname"
  type        = string
}

variable "db_port" {
  description = "Database port"
  type        = number
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_username" {
  description = "Database username"
  type        = string
}

variable "db_engine" {
  description = "Database engine type: aurora-postgresql, rds-mysql, or sqlite"
  type        = string

  validation {
    condition     = contains(["aurora-postgresql", "rds-mysql", "sqlite"], var.db_engine)
    error_message = "db_engine must be one of: aurora-postgresql, rds-mysql, sqlite."
  }
}

variable "redis_endpoint" {
  description = "Redis endpoint hostname (leave empty to disable Redis)"
  type        = string
  default     = ""
}

variable "redis_port" {
  description = "Redis port"
  type        = number
  default     = 6379
}

variable "enable_redis" {
  description = "Whether Redis is enabled for caching"
  type        = bool
}

variable "policy_bundle_s3_bucket" {
  description = "S3 bucket containing the OPA policy bundle (leave empty to disable)"
  type        = string
  default     = ""
}

variable "policy_bundle_s3_key" {
  description = "S3 key for the OPA policy bundle object"
  type        = string
  default     = ""
}

variable "gateway_env" {
  description = "Additional non-sensitive environment variables to inject into the gateway container"
  type        = map(string)
  default     = {}
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights on the ECS cluster"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log group retention period in days"
  type        = number
  default     = 90
}

variable "alarm_5xx_threshold" {
  description = "Number of ALB 5xx responses in 5 minutes that triggers an alarm"
  type        = number
  default     = 50
}

variable "alarm_auth_failure_threshold" {
  description = "Number of authentication failure log events in 5 minutes that triggers an alarm"
  type        = number
  default     = 100
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
