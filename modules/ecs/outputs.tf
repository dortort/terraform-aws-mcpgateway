output "service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.mcpgw.name
}

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.mcpgw.name
}

output "task_role_arn" {
  description = "ARN of the ECS task IAM role"
  value       = aws_iam_role.ecs_task.arn
}

output "execution_role_arn" {
  description = "ARN of the ECS task execution IAM role"
  value       = aws_iam_role.ecs_execution.arn
}

output "log_group_name" {
  description = "Name of the CloudWatch log group for the ECS service"
  value       = aws_cloudwatch_log_group.mcpgw.name
}
