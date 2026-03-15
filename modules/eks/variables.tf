variable "compute_type" {
  description = "Compute engine: 'ec2' (managed node groups) or 'fargate' (serverless pods)"
  type        = string
  default     = "ec2"

  validation {
    condition     = contains(["ec2", "fargate"], var.compute_type)
    error_message = "compute_type must be 'ec2' or 'fargate'."
  }
}

variable "fargate_namespace" {
  description = "Kubernetes namespace for Fargate profile selector"
  type        = string
  default     = "mcpgateway"
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for node groups and cluster"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the cluster VPC config"
  type        = list(string)
}

variable "security_group_id" {
  description = "Gateway security group ID to attach as additional SG on nodes"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt Kubernetes secrets"
  type        = string
}

variable "endpoint_public_access" {
  description = "Whether the EKS cluster API server endpoint is publicly accessible"
  type        = bool
  default     = false
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of nodes in the managed node group"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of nodes in the managed node group"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of nodes in the managed node group"
  type        = number
  default     = 4
}

variable "tags" {
  description = "Map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}
