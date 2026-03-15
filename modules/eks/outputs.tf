output "cluster_endpoint" {
  description = "EKS cluster API server endpoint"
  value       = aws_eks_cluster.mcpgw.endpoint
}

output "cluster_certificate_authority" {
  description = "Base64-encoded certificate authority data for the EKS cluster"
  value       = aws_eks_cluster.mcpgw.certificate_authority[0].data
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.mcpgw.name
}

output "cluster_security_group_id" {
  description = "EKS-managed cluster security group ID"
  value       = aws_eks_cluster.mcpgw.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC identity provider for IRSA"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "OIDC issuer URL without the https:// prefix (for IAM condition keys)"
  value       = trimprefix(aws_eks_cluster.mcpgw.identity[0].oidc[0].issuer, "https://")
}

output "node_role_arn" {
  description = "ARN of the IAM role assigned to managed node group instances"
  value       = local.is_ec2 ? aws_iam_role.eks_nodes[0].arn : null
}

output "fargate_profile_arn" {
  description = "ARN of the EKS Fargate profile"
  value       = local.is_fargate ? aws_eks_fargate_profile.mcpgw[0].arn : null
}

output "fargate_execution_role_arn" {
  description = "ARN of the Fargate pod execution role"
  value       = local.is_fargate ? aws_iam_role.eks_fargate[0].arn : null
}
