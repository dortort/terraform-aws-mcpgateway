variable "cluster_type" {
  description = "Cluster type to deploy: 'ecs' (Fargate) or 'eks' (Kubernetes)"
  type        = string
  default     = "ecs"

  validation {
    condition     = contains(["ecs", "eks"], var.cluster_type)
    error_message = "cluster_type must be 'ecs' or 'eks'."
  }
}

variable "gateway_version" {
  description = "Container image tag for ghcr.io/ibm/mcp-context-forge"
  type        = string
  default     = "latest"
}

variable "replicas" {
  description = "Desired replica count for the gateway service"
  type        = number
  default     = 2
}

variable "db_engine" {
  description = "Database engine: 'aurora-postgresql', 'rds-mysql', or 'sqlite'"
  type        = string
  default     = "aurora-postgresql"

  validation {
    condition     = contains(["aurora-postgresql", "rds-mysql", "sqlite"], var.db_engine)
    error_message = "db_engine must be 'aurora-postgresql', 'rds-mysql', or 'sqlite'."
  }
}

variable "enable_redis" {
  description = "Provision ElastiCache Redis for rate-limiting and sessions"
  type        = bool
  default     = true
}

variable "custom_domain" {
  description = "Route 53 domain for HTTPS access; provisions ACM certificate and ALB HTTPS listener"
  type        = string
  default     = ""
}

variable "policy_bundle_s3_key" {
  description = "S3 path to OPA/Rego policy bundle (format: 'bucket-name/path/to/bundle.tar.gz')"
  type        = string
  default     = ""
}

variable "observability" {
  description = "Observability configuration for CloudWatch"
  type = object({
    log_retention_days           = optional(number, 90)
    enable_container_insights    = optional(bool, true)
    alarm_5xx_threshold          = optional(number, 50)
    alarm_auth_failure_threshold = optional(number, 100)
  })
  default = {}
}

variable "tags" {
  description = "Resource tags applied to all resources"
  type        = map(string)
  default     = {}
}

# --- Networking ---

variable "create_vpc" {
  description = "Create a new VPC; set to false to use an existing VPC"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "Existing VPC ID (required when create_vpc = false)"
  type        = string
  default     = ""
}

variable "private_subnet_ids" {
  description = "Existing private subnet IDs (required when create_vpc = false)"
  type        = list(string)
  default     = []
}

variable "public_subnet_ids" {
  description = "Existing public subnet IDs (required when create_vpc = false)"
  type        = list(string)
  default     = []
}

variable "enable_waf" {
  description = "Attach AWS WAF to the ALB with managed rules and rate limiting"
  type        = bool
  default     = true
}

variable "alb_ingress_cidr_blocks" {
  description = "CIDR blocks allowed to reach the ALB"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# --- Application secrets ---

variable "jwt_secret_key" {
  description = "JWT signing secret for the gateway"
  type        = string
  sensitive   = true
}

variable "auth_encryption_secret" {
  description = "Auth encryption passphrase for the gateway"
  type        = string
  sensitive   = true
}

variable "admin_email" {
  description = "Platform admin email address"
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.admin_email))
    error_message = "admin_email must be a valid email address."
  }
}

variable "admin_password" {
  description = "Platform admin password"
  type        = string
  sensitive   = true
}

variable "gateway_env" {
  description = "Additional non-sensitive environment variables for the gateway container"
  type        = map(string)
  default     = {}
}

# --- Validation ---

locals {
  _validate_sqlite_replicas = (
    var.db_engine == "sqlite" && var.replicas > 1
    ? tobool("SQLite does not support multiple replicas — set replicas = 1 when db_engine = 'sqlite'")
    : true
  )

  _validate_existing_vpc = (
    !var.create_vpc && (var.vpc_id == "" || length(var.private_subnet_ids) == 0 || length(var.public_subnet_ids) == 0)
    ? tobool("When create_vpc = false, vpc_id, private_subnet_ids, and public_subnet_ids are required")
    : true
  )
}
