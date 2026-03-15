output "certificate_arn" {
  description = "ARN of the validated ACM certificate"
  value       = aws_acm_certificate_validation.mcpgw.certificate_arn
}

output "fqdn" {
  description = "Fully qualified domain name of the MCP Gateway"
  value       = aws_route53_record.mcpgw.fqdn
}
