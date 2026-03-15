variable "vpc_id" {
  description = "ID of the VPC in which to create the load balancer resources."
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs across which the ALB will be distributed."
  type        = list(string)
}

variable "security_group_id" {
  description = "ID of the security group to attach to the ALB."
  type        = string
}

variable "certificate_arn" {
  description = "ARN of the ACM certificate to use for the HTTPS listener."
  type        = string
  default     = ""
}

variable "enable_waf" {
  description = "Whether to create and associate a WAFv2 Web ACL with the ALB."
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "Maximum number of requests allowed per IP address per 5-minute window before WAF blocks the source."
  type        = number
  default     = 2000
}

variable "tags" {
  description = "Map of tags to apply to all resources created by this module."
  type        = map(string)
  default     = {}
}
