variable "custom_domain" {
  description = "The fully qualified domain name for the MCP Gateway (e.g. \"mcpgateway.example.com\")"
  type        = string
}

variable "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer"
  type        = string
}

variable "alb_zone_id" {
  description = "The canonical hosted zone ID of the Application Load Balancer"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
