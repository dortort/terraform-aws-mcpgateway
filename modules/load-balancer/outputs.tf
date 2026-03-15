output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer."
  value       = aws_lb.mcpgw.dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer."
  value       = aws_lb.mcpgw.arn
}

output "alb_zone_id" {
  description = "Canonical hosted zone ID of the ALB (for Route 53 alias records)."
  value       = aws_lb.mcpgw.zone_id
}

output "target_group_arn" {
  description = "ARN of the ALB target group."
  value       = aws_lb_target_group.mcpgw.arn
}

output "https_listener_arn" {
  description = "ARN of the HTTPS (port 443) listener."
  value       = aws_lb_listener.https.arn
}
