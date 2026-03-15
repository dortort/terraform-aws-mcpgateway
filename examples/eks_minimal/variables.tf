variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "custom_domain" {
  description = "Custom domain for the gateway"
  type        = string
}

variable "jwt_secret_key" {
  description = "JWT signing secret"
  type        = string
  sensitive   = true
}

variable "auth_encryption_secret" {
  description = "Auth encryption passphrase"
  type        = string
  sensitive   = true
}

variable "admin_email" {
  description = "Platform admin email"
  type        = string
}

variable "admin_password" {
  description = "Platform admin password"
  type        = string
  sensitive   = true
}
