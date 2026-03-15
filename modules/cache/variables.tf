variable "private_subnet_ids" {
  description = "List of private subnet IDs for the ElastiCache subnet group"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID to attach to the Redis replication group"
  type        = string
}

variable "auth_token" {
  description = "Redis AUTH token for transit encryption authentication"
  type        = string
  sensitive   = true
}

variable "kms_key_arn" {
  description = "KMS key ARN for ElastiCache encryption at rest"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
