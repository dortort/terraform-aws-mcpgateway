variable "jwt_secret_key" {
  description = "JWT secret key for token signing"
  type        = string
  sensitive   = true
}

variable "auth_encryption_secret" {
  description = "Secret used for encrypting authentication data"
  type        = string
  sensitive   = true
}

variable "admin_email" {
  description = "Admin user email address"
  type        = string
}

variable "admin_password" {
  description = "Admin user password"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
