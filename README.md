# terraform-aws-mcpgateway

[![Terraform Version](https://img.shields.io/badge/Terraform-%3E%3D%201.6-blue)](https://www.terraform.io/downloads.html)
[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](./LICENSE)

Terraform module that deploys [IBM MCP Context Forge](https://github.com/IBM/mcp-context-forge) on AWS with enterprise-grade infrastructure: ECS/EKS orchestration, Aurora/RDS/SQLite databases, ElastiCache Redis caching, Application Load Balancer with WAF, Route53 DNS, and ACM certificates.

## Overview

terraform-aws-mcpgateway automates deployment of MCP Context Forge across AWS infrastructure. Choose between serverless ECS Fargate or managed Kubernetes (EKS), select your database engine (Aurora PostgreSQL, RDS MySQL, or embedded SQLite), and enable optional Redis for high-performance caching and session management.

All traffic is protected by AWS WAF, encrypted end-to-end, and monitored via CloudWatch logs and alarms.

## Architecture

```
Internet → Route53 → ALB (WAF) → ECS Fargate / EKS Pods (Private Subnet)
                       ↓
           ┌───────────┼───────────┐
           ↓           ↓           ↓
      Aurora/RDS   ElastiCache   S3 Buckets
      (Encrypted)  (Redis)       (Policies)

Secrets Manager → IAM Roles → ECS/EKS
CloudWatch → Logs & Alarms
```

**Components:**
- **VPC**: Public subnets (ALB), private subnets (ECS/EKS), NAT Gateway for outbound access
- **Load Balancing**: Application Load Balancer with target group, auto-scaling friendly
- **Web Application Firewall**: AWS WAF with managed rules, rate limiting, IP reputation lists
- **Compute**: ECS Fargate (recommended for simple deployments) or EKS (for advanced Kubernetes workflows)
- **Database**: Aurora PostgreSQL Serverless v2 (default, auto-scaling), RDS MySQL, or embedded SQLite
- **Cache**: ElastiCache Redis (optional, for rate-limiting and session state)
- **Secrets**: AWS Secrets Manager (encrypted, rotated)
- **Monitoring**: CloudWatch Logs, Container Insights, custom alarms
- **DNS & TLS**: Route53 + ACM certificates (optional custom domain)

## Quick Start

Deploy MCP Context Forge with minimal ECS configuration:

```hcl
terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "mcpgateway" {
  source = "git::https://github.com/dortort/terraform-aws-mcpgateway.git"

  orchestrator    = "ecs"
  compute_type    = "fargate"
  gateway_version = "latest"
  replicas        = 2
  db_engine       = "aurora-postgresql"
  enable_redis    = true

  jwt_secret_key         = var.jwt_secret_key
  auth_encryption_secret = var.auth_encryption_secret
  admin_email            = "admin@example.com"
  admin_password         = var.admin_password

  tags = {
    Environment = "production"
    Project     = "mcpgateway"
  }
}

output "gateway_url" {
  value = module.mcpgateway.alb_url
}

output "database_endpoint" {
  value = module.mcpgateway.database_endpoint
}

output "redis_endpoint" {
  value = module.mcpgateway.redis_endpoint
}
```

## Requirements

| Requirement | Version |
|-------------|---------|
| Terraform | >= 1.6 |
| AWS Provider | ~> 6.0 |
| Kubernetes Provider | ~> 2.35 (EKS only) |
| Helm Provider | ~> 2.17 (EKS only) |

**AWS Credentials**: Configure via environment variables, credentials file, or IAM role:
```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_REGION="us-east-1"
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `orchestrator` | string | `"ecs"` | No | Container orchestrator: `"ecs"` or `"eks"` |
| `compute_type` | string | `"fargate"` | No | Compute engine: `"fargate"` or `"ec2"` |
| `gateway_version` | string | `"latest"` | No | Container image tag for `ghcr.io/ibm/mcp-context-forge` |
| `replicas` | number | `2` | No | Desired replica count. Must be `1` when using SQLite. |
| `db_engine` | string | `"aurora-postgresql"` | No | Database engine: `"aurora-postgresql"`, `"rds-mysql"`, or `"sqlite"` |
| `enable_redis` | bool | `true` | No | Provision ElastiCache Redis for rate-limiting and sessions |
| `custom_domain` | string | `""` | No | Route53 domain name; omit for ALB DNS name. Provisions ACM certificate and HTTPS listener. |
| `policy_bundle_s3_key` | string | `""` | No | S3 path to OPA/Rego policy bundle in format `bucket-name/path/to/bundle.tar.gz` |
| `observability` | object | `{}` | No | CloudWatch configuration: `log_retention_days` (90), `enable_container_insights` (true), `alarm_5xx_threshold` (50), `alarm_auth_failure_threshold` (100) |
| `tags` | map(string) | `{}` | No | Tags applied to all resources |
| `create_vpc` | bool | `true` | No | Create new VPC; set `false` to use existing VPC |
| `vpc_id` | string | `""` | No | Existing VPC ID (required when `create_vpc = false`) |
| `private_subnet_ids` | list(string) | `[]` | No | Existing private subnet IDs (required when `create_vpc = false`) |
| `public_subnet_ids` | list(string) | `[]` | No | Existing public subnet IDs (required when `create_vpc = false`) |
| `enable_waf` | bool | `true` | No | Attach AWS WAF to ALB with managed rules and rate limiting |
| `alb_ingress_cidr_blocks` | list(string) | `["0.0.0.0/0"]` | No | CIDR blocks allowed to reach the ALB |
| `jwt_secret_key` | string | N/A | Yes | JWT signing secret for the gateway (stored in Secrets Manager) |
| `auth_encryption_secret` | string | N/A | Yes | Auth encryption passphrase (stored in Secrets Manager) |
| `admin_email` | string | N/A | Yes | Platform admin email address (validated format) |
| `admin_password` | string | N/A | Yes | Platform admin password (stored in Secrets Manager) |
| `gateway_env` | map(string) | `{}` | No | Additional non-sensitive environment variables for the container |

## Outputs

| Name | Type | Description |
|------|------|-------------|
| `alb_url` | string | Gateway URL: HTTPS with custom domain, or HTTPS with ALB DNS name |
| `database_endpoint` | string | RDS/Aurora database endpoint (null for SQLite) |
| `redis_endpoint` | string | ElastiCache Redis endpoint (null when disabled) |
| `rds_endpoint` | string | Alias for `database_endpoint` |
| `iam_role_arns` | map(string) | IAM role ARNs: `ecs_task_role`, `ecs_execution_role` (ECS) or `eks_node_role` (EKS) |
| `cloudwatch_log_group` | string | CloudWatch Log Group name (ECS only) |
| `api_gateway_id` | string | WAF Web ACL ID (when WAF is enabled) |

## Cost Estimate (Default Configuration)

Approximate monthly cost for a production deployment with default settings (us-east-1):

| Component | Size | Monthly Cost |
|-----------|------|--------------|
| ALB | Standard | $22.00 |
| ECS Fargate (2 replicas) | 1 vCPU, 2 GB RAM | $58.08 |
| Aurora PostgreSQL Serverless v2 | Min capacity 0.5 ACUs | $43.20 |
| ElastiCache Redis | cache.t4g.medium | $48.56 |
| NAT Gateway | 1 gateway | $32.40 |
| Data Transfer (egress) | 10 GB | $0.90 |
| CloudWatch Logs | 100 GB/month | $50.00 |
| **Total (estimated)** | | **$255.14** |

**Cost optimization:**
- Use SQLite for single-replica dev/test (eliminates database cost ~$40)
- Disable Redis if not needed (saves ~$49)
- Use `create_vpc = false` with existing VPC (eliminates NAT Gateway ~$32)
- Reduce log retention from 90 to 30 days (saves ~$25)

## Deployment Matrix

Choose your orchestrator and compute combination based on your requirements:

| Orchestrator | Compute | Description |
|---|---|---|
| ECS | Fargate | **Serverless, default.** Auto-scaling, pay-per-task, no server management. Best for variable workloads and rapid deployments. |
| ECS | EC2 | **Cost-optimized.** Managed node groups with auto-scaling, GPU support, larger task sizes. Best for steady-state workloads. |
| EKS | Fargate | **Kubernetes without nodes.** Fargate profiles, Kubernetes API, no EC2 management. Best for teams familiar with K8s wanting simplicity. |
| EKS | EC2 | **Full Kubernetes control.** Managed node groups, DaemonSets, advanced networking (Istio, Cilium), custom kubelet configs. Best for complex K8s workloads. |

**Deployment examples:**

```hcl
# ECS Fargate (default, recommended)
module "mcpgateway" {
  orchestrator = "ecs"
  compute_type = "fargate"
}

# ECS on EC2
module "mcpgateway" {
  orchestrator = "ecs"
  compute_type = "ec2"
}

# EKS with Fargate
module "mcpgateway" {
  orchestrator = "eks"
  compute_type = "fargate"
}

# EKS with EC2 (full Kubernetes)
module "mcpgateway" {
  orchestrator = "eks"
  compute_type = "ec2"
}
```

## Security

**Secrets Management:**
- All sensitive data (JWT keys, passwords, DB credentials) stored in AWS Secrets Manager with encryption
- Automatic secret injection into ECS/EKS containers
- No secrets in environment files, logs, or Terraform state

**Encryption:**
- Database encryption at rest with AWS KMS
- Redis encryption in transit (TLS)
- ECS task storage encrypted with KMS
- EKS secrets encrypted with KMS

**Network Isolation:**
- Gateway runs in private subnets (no direct internet access)
- RDS/Redis in private subnets with restrictive security groups
- ALB only public component (protected by WAF)
- All ingress/egress controlled by security groups

**Container Hardening:**
- Non-root user (UID 1001)
- Read-only root filesystem
- No privileged capabilities
- Resource limits enforced

**Web Application Firewall:**
- AWS-managed rule groups (SQL injection, XSS, Common attacks)
- Rate limiting (2000 requests per 5 minutes per IP)
- IP reputation filtering
- Custom rules via WAF ACL

**TLS/HTTPS:**
- ACM certificates (auto-renewal, no manual management)
- ALB HTTPS listener (TLS 1.2+)
- Secure cookies (HttpOnly, SameSite)

## Examples

See full examples in the repository:
- **[examples/ecs_full](./examples/ecs_full)**: Production ECS deployment with custom domain, OPA policies, observability alarms
- **[examples/eks_minimal](./examples/eks_minimal)**: Minimal EKS deployment with Aurora PostgreSQL and Redis

## Documentation

For detailed configuration and troubleshooting:
- **[docs/README.md](./docs/README.md)**: Database selection, VPC configuration, custom domains, observability, WAF, production hardening
- **[docs/advanced.md](./docs/advanced.md)**: Remote state backends, multi-region, scaling, disaster recovery, version upgrades
- **[docs/architecture.puml](./docs/architecture.puml)**: PlantUML architecture diagram

## Contributing

Contributions welcome. Please:
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-feature`)
3. Test thoroughly with both ECS and EKS deployments
4. Submit a pull request with description

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](./LICENSE) for details.

## Related

- [IBM MCP Context Forge GitHub](https://github.com/IBM/mcp-context-forge)
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
