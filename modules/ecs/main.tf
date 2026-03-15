data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Composed secrets stored in Secrets Manager
# The ECS secrets injection mechanism substitutes a full secret value, so we
# pre-compose DATABASE_URL and REDIS_URL and store them here. The raw
# password/token ARNs are never passed as plaintext environment variables.
# ---------------------------------------------------------------------------

locals {
  db_scheme = var.db_engine == "aurora-postgresql" ? "postgresql+psycopg" : (
    var.db_engine == "rds-mysql" ? "mysql+pymysql" : "sqlite"
  )

  # sqlite does not need a network URL; for network engines compose the full URL
  database_url = var.db_engine == "sqlite" ? "sqlite:///./mcpgw.db" : (
    "${local.db_scheme}://${var.db_username}:{{DB_PASSWORD}}@${var.db_endpoint}:${var.db_port}/${var.db_name}"
  )

  redis_url = var.enable_redis ? "rediss://:{{REDIS_AUTH_TOKEN}}@${var.redis_endpoint}:${var.redis_port}/0" : ""

  extra_env = [
    for k, v in var.gateway_env : { name = k, value = v }
  ]
}

# We store the composed URLs as Secrets Manager secrets so that ECS can inject
# them without ever surfacing the credentials in task definition plaintext.

resource "aws_secretsmanager_secret" "database_url" {
  name                    = "mcpgw/database-url"
  description             = "Composed DATABASE_URL for MCP Gateway"
  recovery_window_in_days = 7
  tags                    = var.tags
}

# The secret version references the password secret ARN via dynamic references
# so the actual password value is resolved by Secrets Manager at read time.
# Terraform stores only the ARN-based reference string here.
resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id = aws_secretsmanager_secret.database_url.id

  # Use Secrets Manager dynamic references to avoid materialising the password
  # in Terraform state. The {{...}} placeholders are replaced at ECS launch.
  # For sqlite there is no password substitution needed.
  secret_string = var.db_engine == "sqlite" ? local.database_url : replace(
    replace(local.database_url, "{{DB_PASSWORD}}", "{{resolve:secretsmanager:${var.secret_arns.db_password}}}"),
    "{{resolve:secretsmanager:${var.secret_arns.db_password}}}",
    "{{resolve:secretsmanager:${var.secret_arns.db_password}}}"
  )
}

resource "aws_secretsmanager_secret" "redis_url" {
  count                   = var.enable_redis ? 1 : 0
  name                    = "mcpgw/redis-url"
  description             = "Composed REDIS_URL for MCP Gateway"
  recovery_window_in_days = 7
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "redis_url" {
  count     = var.enable_redis ? 1 : 0
  secret_id = aws_secretsmanager_secret.redis_url[0].id
  secret_string = replace(
    local.redis_url,
    "{{REDIS_AUTH_TOKEN}}",
    "{{resolve:secretsmanager:${var.secret_arns.redis_auth_token}}}"
  )
}

# ---------------------------------------------------------------------------
# ECS Cluster
# ---------------------------------------------------------------------------

resource "aws_ecs_cluster" "mcpgw" {
  name = "mcpgw"

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# CloudWatch Log Group
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "mcpgw" {
  name              = "/ecs/mcpgw"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# ---------------------------------------------------------------------------
# IAM – Execution Role
# Allows ECS agent to pull images and read secrets on behalf of the task.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    sid     = "ECSTasksAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  name               = "mcpgw-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "secrets_read" {
  statement {
    sid    = "ReadGatewaySecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = concat(
      values(var.secret_arns),
      [aws_secretsmanager_secret.database_url.arn],
      var.enable_redis ? [aws_secretsmanager_secret.redis_url[0].arn] : []
    )
  }
}

resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name   = "mcpgw-secrets-read"
  role   = aws_iam_role.ecs_execution.id
  policy = data.aws_iam_policy_document.secrets_read.json
}

# ---------------------------------------------------------------------------
# IAM – Task Role
# Runtime permissions for the container process itself.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "ecs_task" {
  name               = "mcpgw-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "policy_bundle_s3" {
  count = var.policy_bundle_s3_bucket != "" ? 1 : 0

  statement {
    sid     = "ReadPolicyBundle"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "arn:aws:s3:::${var.policy_bundle_s3_bucket}/${var.policy_bundle_s3_key}",
    ]
  }
}

resource "aws_iam_role_policy" "ecs_task_s3" {
  count  = var.policy_bundle_s3_bucket != "" ? 1 : 0
  name   = "mcpgw-policy-bundle-s3"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.policy_bundle_s3[0].json
}

# ---------------------------------------------------------------------------
# ECS Task Definition
# ---------------------------------------------------------------------------

locals {
  base_environment = [
    { name = "HOST", value = "0.0.0.0" },
    { name = "PORT", value = "4444" },
    { name = "ENVIRONMENT", value = "production" },
    { name = "HTTP_SERVER", value = "gunicorn" },
    { name = "SSRF_PROTECTION_ENABLED", value = "true" },
    { name = "SSRF_ALLOW_LOCALHOST", value = "false" },
    { name = "SSRF_ALLOW_PRIVATE_NETWORKS", value = "false" },
    { name = "SECURE_COOKIES", value = "true" },
    { name = "PLATFORM_ADMIN_EMAIL", value = var.admin_email },
    { name = "CACHE_TYPE", value = var.enable_redis ? "redis" : "simple" },
  ]

  container_environment = concat(local.base_environment, local.extra_env)

  base_secrets = [
    { name = "JWT_SECRET_KEY", valueFrom = var.secret_arns.jwt_secret_key },
    { name = "AUTH_ENCRYPTION_SECRET", valueFrom = var.secret_arns.auth_encryption_secret },
    { name = "PLATFORM_ADMIN_PASSWORD", valueFrom = var.secret_arns.admin_password },
    { name = "DATABASE_URL", valueFrom = aws_secretsmanager_secret.database_url.arn },
  ]

  redis_secret = var.enable_redis ? [
    { name = "REDIS_URL", valueFrom = aws_secretsmanager_secret.redis_url[0].arn },
  ] : []

  container_secrets = concat(local.base_secrets, local.redis_secret)

  container_definition = {
    name      = "mcpgw"
    image     = "ghcr.io/ibm/mcp-context-forge:${var.gateway_version}"
    essential = true

    portMappings = [
      { containerPort = 4444, protocol = "tcp" }
    ]

    user                   = "1001"
    readonlyRootFilesystem = true

    linuxParameters = {
      initProcessEnabled = true
      capabilities = {
        drop = ["ALL"]
      }
      tmpfs = [
        { containerPath = "/tmp", size = 512 },
        { containerPath = "/app/logs", size = 256 },
      ]
    }

    mountPoints = []

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.mcpgw.name
        awslogs-region        = data.aws_region.current.region
        awslogs-stream-prefix = "mcpgw"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "wget -q --spider http://localhost:4444/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }

    environment = local.container_environment
    secrets     = local.container_secrets
  }
}

resource "aws_ecs_task_definition" "mcpgw" {
  family                   = "mcpgw"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "1024"
  memory                   = "2048"

  execution_role_arn = aws_iam_role.ecs_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([local.container_definition])

  tags = var.tags
}

# ---------------------------------------------------------------------------
# ECS Service
# ---------------------------------------------------------------------------

resource "aws_ecs_service" "mcpgw" {
  name            = "mcpgw"
  cluster         = aws_ecs_cluster.mcpgw.arn
  task_definition = aws_ecs_task_definition.mcpgw.arn
  desired_count   = var.replicas
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "mcpgw"
    container_port   = 4444
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 120

  # Avoid replacing the service on every plan when task definition updates
  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# CloudWatch Alarms
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "http_5xx" {
  alarm_name          = "mcpgw-alb-5xx"
  alarm_description   = "ALB 5xx responses from MCP Gateway exceeded threshold"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = var.alarm_5xx_threshold
  treat_missing_data  = "notBreaching"

  tags = var.tags
}

resource "aws_cloudwatch_log_metric_filter" "auth_failures" {
  name           = "mcpgw-auth-failures"
  log_group_name = aws_cloudwatch_log_group.mcpgw.name
  pattern        = "?\"authentication failed\" ?\"401\""

  metric_transformation {
    name          = "AuthFailureCount"
    namespace     = "MCPGateway/Security"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "auth_failures" {
  alarm_name          = "mcpgw-auth-failures"
  alarm_description   = "MCP Gateway authentication failures exceeded threshold"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.auth_failures.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.auth_failures.metric_transformation[0].namespace
  period              = 300
  statistic           = "Sum"
  threshold           = var.alarm_auth_failure_threshold
  treat_missing_data  = "notBreaching"

  tags = var.tags
}
