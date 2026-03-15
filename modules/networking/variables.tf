variable "create_vpc" {
  description = "Whether to create a new VPC. Set to false to use an existing VPC."
  type        = bool
}

variable "vpc_id" {
  description = "ID of an existing VPC. Used when create_vpc is false."
  type        = string
  default     = ""
}

variable "private_subnet_ids" {
  description = "List of existing private subnet IDs. Used when create_vpc is false."
  type        = list(string)
  default     = []
}

variable "public_subnet_ids" {
  description = "List of existing public subnet IDs. Used when create_vpc is false."
  type        = list(string)
  default     = []
}

variable "alb_ingress_cidr_blocks" {
  description = "CIDR blocks allowed to reach the ALB on ports 443 and 80."
  type        = list(string)
}

variable "db_engine" {
  description = "Database engine type. Used to derive the database port (aurora-postgresql -> 5432, rds-mysql -> 3306)."
  type        = string
}

variable "enable_redis" {
  description = "Whether to create a security group for Redis/ElastiCache."
  type        = bool
}

variable "log_retention_days" {
  description = "Number of days to retain VPC Flow Log entries in CloudWatch."
  type        = number
  default     = 90
}

variable "tags" {
  description = "Map of tags to apply to all resources in this module."
  type        = map(string)
  default     = {}
}
