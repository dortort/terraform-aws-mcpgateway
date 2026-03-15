variable "db_engine" {
  description = "Database engine to use. Valid values: \"aurora-postgresql\" or \"rds-mysql\"."
  type        = string

  validation {
    condition     = contains(["aurora-postgresql", "rds-mysql"], var.db_engine)
    error_message = "db_engine must be one of: aurora-postgresql, rds-mysql."
  }
}

variable "vpc_id" {
  description = "ID of the VPC in which to create the database resources."
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the DB subnet group."
  type        = list(string)
}

variable "security_group_id" {
  description = "ID of the security group to attach to the database."
  type        = string
}

variable "db_password" {
  description = "Master password for the database. Must be managed via a secrets manager; never embed in plaintext."
  type        = string
  sensitive   = true
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used for encryption at rest."
  type        = string
}

variable "tags" {
  description = "Map of tags to apply to all resources in this module."
  type        = map(string)
  default     = {}
}
