# Detailed Configuration Guide

This guide covers deployment scenarios, configuration decisions, and best practices for terraform-aws-mcpgateway.

## Table of Contents

1. [Database Engine Selection](#database-engine-selection)
2. [Cluster Type: ECS vs EKS](#cluster-type-ecs-vs-eks)
3. [VPC Configuration](#vpc-configuration)
4. [Custom Domain and TLS](#custom-domain-and-tls)
5. [Policy Bundle Configuration](#policy-bundle-configuration)
6. [Observability Setup](#observability-setup)
7. [Web Application Firewall](#web-application-firewall)
8. [Production Hardening Checklist](#production-hardening-checklist)
9. [Troubleshooting](#troubleshooting)

## Database Engine Selection

Choose the database engine based on your availability, scaling, and operational requirements.

### Aurora PostgreSQL Serverless v2 (Recommended)

**Best for:** Production workloads with variable traffic, multi-AZ deployments, auto-scaling.

**Pros:**
- Automatic scaling (0.5 to 128 ACUs)
- Multi-AZ by default (high availability)
- Managed backups with point-in-time recovery
- Connection pooling via RDS Proxy
- PostgreSQL ecosystem and extensions
- Costs scale with actual usage

**Cons:**
- Higher baseline cost (~$43/month minimum)
- Aurora-specific configuration required

**Configuration:**
```hcl
module "mcpgateway" {
  db_engine   = "aurora-postgresql"
  replicas    = 2  # or more for HA

  # Optional: more aggressive auto-scaling
  # Configure Aurora capacity in AWS console or via custom module
}
```

**Monitoring:**
```bash
aws rds describe-db-clusters --query 'DBClusters[0].{Endpoint,AvailabilityZones,AutomaticBackupRetentionPeriod}' --output table
```

### RDS MySQL

**Best for:** Existing MySQL workloads, cost-sensitive deployments, single-AZ acceptable.

**Pros:**
- Standard MySQL tooling and knowledge
- Lower cost than Aurora (~$30/month)
- Multi-version support (5.7, 8.0)

**Cons:**
- Fixed instance size (no serverless auto-scaling)
- Manual scaling required
- Single-AZ by default (requires manual Multi-AZ)

**Configuration:**
```hcl
module "mcpgateway" {
  db_engine = "rds-mysql"
  replicas  = 1  # RDS MySQL supports single-AZ

  # For HA: manually create Multi-AZ read replicas
}
```

**Upgrading instance class:**
```bash
aws rds modify-db-instance \
  --db-instance-identifier mcpgateway-rds-mysql \
  --db-instance-class db.t4g.medium \
  --apply-immediately
```

### SQLite

**Best for:** Development, testing, single-instance deployments with <100GB data.

**Pros:**
- Zero infrastructure cost
- No database credentials to manage
- Instant setup
- Perfect for dev/test environments

**Cons:**
- Single-replica only (`replicas = 1` required)
- No clustering or HA
- Limited to one server
- Not suitable for production with multiple instances

**Configuration:**
```hcl
module "mcpgateway" {
  db_engine = "sqlite"
  replicas  = 1  # Must be 1 for SQLite

  # Disable Redis for simplicity (optional)
  enable_redis = false

  # Keep other settings as needed
}
```

**Persistence:**
The SQLite database is stored in the ECS task storage (ephemeral). For persistence:
- Use EFS mounting (requires custom module extension)
- Or configure regular backups to S3
- Or migrate to Aurora/RDS for production

## Cluster Type: ECS vs EKS

Choose between AWS's managed container platforms.

### ECS Fargate (Recommended for Most)

**Best for:** Simple deployments, AWS-native environments, minimal Kubernetes overhead.

**Pros:**
- Simpler to manage (no cluster nodes)
- Faster deployment (minutes vs hours)
- Automatic scaling built-in
- Lower operational overhead
- Serverless compute model
- Native AWS integrations (IAM, Secrets Manager, CloudWatch)

**Cons:**
- Less flexible than Kubernetes
- Limited to AWS-specific patterns
- Harder to use third-party Kubernetes tools

**Configuration:**
```hcl
module "mcpgateway" {
  cluster_type = "ecs"
  replicas     = 2

  tags = {
    ClusterType = "ecs"
  }
}

output "log_group" {
  value = module.mcpgateway.cloudwatch_log_group
}
```

**Accessing logs:**
```bash
aws logs tail /aws/ecs/mcpgateway --follow
```

**Scaling:**
```bash
aws ecs update-service \
  --cluster mcpgateway \
  --service mcpgateway-service \
  --desired-count 5
```

### EKS (Kubernetes)

**Best for:** Complex workloads, multi-cluster deployments, advanced Kubernetes features.

**Pros:**
- Full Kubernetes ecosystem
- Multi-cloud portability
- Advanced networking (Istio, Cilium)
- Custom Kubernetes operators
- Horizontal Pod Autoscaling (HPA)
- Ingress controller flexibility

**Cons:**
- Higher operational complexity
- Node management overhead
- Longer learning curve
- Additional cost (EKS control plane $0.10/hour)

**Configuration:**
```hcl
module "mcpgateway" {
  cluster_type = "eks"
  replicas     = 2

  tags = {
    ClusterType = "eks"
  }
}

output "cluster_endpoint" {
  value = module.mcpgateway.cluster_endpoint
}
```

**Accessing the cluster:**
```bash
aws eks update-kubeconfig --name mcpgateway --region us-east-1
kubectl get pods -n mcpgateway
kubectl logs -n mcpgateway deploy/mcpgateway -f
```

**Scaling:**
```bash
kubectl scale deployment mcpgateway -n mcpgateway --replicas=5
```

## VPC Configuration

### New VPC (Default)

Create a new VPC with public and private subnets:

```hcl
module "mcpgateway" {
  create_vpc = true  # Default

  # Module creates:
  # - VPC (10.0.0.0/16)
  # - Public subnets (10.0.1.0/24, 10.0.2.0/24)
  # - Private subnets (10.0.10.0/24, 10.0.11.0/24)
  # - NAT Gateway
  # - Internet Gateway
}
```

### Existing VPC

Integrate with an existing VPC:

```hcl
module "mcpgateway" {
  create_vpc              = false
  vpc_id                  = "vpc-0123456789abcdef0"
  private_subnet_ids      = ["subnet-private-1a", "subnet-private-1b"]
  public_subnet_ids       = ["subnet-public-1a", "subnet-public-1b"]

  # Existing VPC must have:
  # - Public subnets for ALB (with route to IGW)
  # - Private subnets for ECS/EKS/database (with route to NAT)
  # - NAT Gateway in at least one public subnet
}
```

**Validation:**
```bash
aws ec2 describe-subnets --subnet-ids subnet-private-1a subnet-private-1b \
  --query 'Subnets[].{SubnetId,VpcId,CidrBlock}' --output table

aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=subnet-private-1a" \
  --query 'RouteTables[].Routes[]' --output table
```

## Custom Domain and TLS

### Setup with Custom Domain

Configure HTTPS access with your own domain:

```hcl
module "mcpgateway" {
  custom_domain = "api.example.com"

  # Module automatically:
  # 1. Creates Route53 A record (alias to ALB)
  # 2. Provisions ACM certificate
  # 3. Configures ALB HTTPS listener (TLS 1.2+)
  # 4. Redirects HTTP → HTTPS
}

output "gateway_url" {
  value = module.mcpgateway.alb_url  # https://api.example.com
}
```

**Prerequisites:**
- Domain registered and Route53 hosted zone created
- AWS account has permission to modify Route53

**Validation:**
```bash
curl -I https://api.example.com
# Should return 200 with secure headers

aws acm list-certificates --query 'CertificateSummaryList[].DomainName' --output table
```

### Certificate Management

ACM certificates are automatically renewed before expiry (no action needed).

**Check certificate status:**
```bash
aws acm describe-certificate --certificate-arn arn:aws:acm:us-east-1:123456789:certificate/12345 \
  --query 'Certificate.{Status,ValidFrom,ValidTo,RenewalEligibility}'
```

### ALB DNS Name (Without Custom Domain)

If not using a custom domain, access via ALB DNS:

```hcl
module "mcpgateway" {
  # custom_domain = ""  # Leave empty
}

output "gateway_url" {
  value = module.mcpgateway.alb_url
  # https://mcpgateway-alb-1234567890.us-east-1.elb.amazonaws.com
}
```

**Note:** ALB DNS names are not memorable; consider using a CNAME in your DNS provider to point to the ALB.

## Policy Bundle Configuration

Configure OPA/Rego policy bundles for authorization and request filtering.

### Bundle Format

OPA bundles are tar.gz archives containing Rego policy files:

```bash
# Example structure
policies/
├── authn.rego
├── authz.rego
└── rate_limit.rego

# Create bundle
tar -czf bundle.tar.gz policies/

# Upload to S3
aws s3 cp bundle.tar.gz s3://my-policy-bucket/mcpgateway/bundle.tar.gz
```

### Configuration

```hcl
module "mcpgateway" {
  policy_bundle_s3_key = "my-policy-bucket/mcpgateway/bundle.tar.gz"

  # Module automatically:
  # 1. Configures S3 IAM permissions for gateway
  # 2. Injects POLICY_BUNDLE_URL into container
  # 3. Sets up periodic bundle refresh (if supported by image)
}
```

### Monitoring Policy Violations

Policies that deny requests are logged. Check CloudWatch:

```bash
aws logs filter-log-events \
  --log-group-name /aws/ecs/mcpgateway \
  --filter-pattern '"policy_denial" OR "authz_failed"' \
  --query 'events[].message' --output text
```

## Observability Setup

### CloudWatch Logs

Configure log retention and filtering:

```hcl
module "mcpgateway" {
  observability = {
    log_retention_days           = 90      # Days to retain logs
    enable_container_insights    = true    # ECS Container Insights
    alarm_5xx_threshold          = 50      # 5xx errors in 5 min
    alarm_auth_failure_threshold = 100     # Auth failures in 5 min
  }
}
```

**View logs:**
```bash
# Real-time logs
aws logs tail /aws/ecs/mcpgateway --follow

# Search by pattern
aws logs filter-log-events --log-group-name /aws/ecs/mcpgateway \
  --filter-pattern "ERROR" --start-time $(($(date +%s) * 1000 - 3600000))
```

### Container Insights (ECS only)

Enable detailed metrics and dashboards:

```bash
# Verify Container Insights is enabled
aws ecs describe-clusters --clusters mcpgateway \
  --query 'clusters[].settings[?name==`containerInsights`].value'

# View metrics in CloudWatch dashboard
aws cloudwatch list-dashboards --query 'DashboardEntries[].DashboardName'
```

### CloudWatch Alarms

Alarms trigger SNS notifications for critical events. Create SNS topic first:

```bash
aws sns create-topic --name mcpgateway-alerts
# Output: TopicArn=arn:aws:sns:us-east-1:123456789:mcpgateway-alerts

# Subscribe to notifications
aws sns subscribe --topic-arn arn:aws:sns:us-east-1:123456789:mcpgateway-alerts \
  --protocol email --notification-endpoint ops@example.com
```

Then configure in Terraform (requires custom extension):

```hcl
module "mcpgateway" {
  observability = {
    alarm_5xx_threshold          = 25   # Lower threshold = more sensitive
    alarm_auth_failure_threshold = 50
  }

  # Note: SNS topic ARN must be added to ECS alarm module separately
}
```

### Custom Metrics

Emit custom metrics from the gateway (requires application code changes):

```python
# Example: in MCP Context Forge application
import boto3

cloudwatch = boto3.client('cloudwatch')

cloudwatch.put_metric_data(
    Namespace='MCPGateway',
    MetricData=[
        {
            'MetricName': 'ContextForgeSyncCount',
            'Value': 42,
            'Unit': 'Count'
        }
    ]
)
```

## Web Application Firewall

### Enabling WAF

```hcl
module "mcpgateway" {
  enable_waf = true

  # Module attaches AWS-managed rule groups:
  # - AWSManagedRulesCommonRuleSet (SQL injection, XSS, etc.)
  # - AWSManagedRulesKnownBadInputsRuleSet
  # - AWSManagedRulesSQLiRuleSet
}
```

### Managed Rules

AWS-managed rules are automatically applied:

| Rule Group | Protection |
|------------|-----------|
| Common Rule Set | SQL injection, XSS, CSRF, local file inclusion, protocol attacks |
| Known Bad Inputs | Patterns known to trigger CVEs |
| SQL Injection Rule Set | Advanced SQL injection detection |
| Rate Limiting | 2000 requests per 5 minutes per IP |

### Custom Rules

To add custom rules (requires extending the module):

```hcl
resource "aws_wafv2_ip_set" "blocklist" {
  name               = "mcpgateway-blocklist"
  description        = "Custom IP blocklist"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = ["203.0.113.0/24"]  # Example: block CIDR range
}

# Attach to WAF ACL in load-balancer module
```

### WAF Logging

Enable logging of all WAF actions:

```bash
# Create S3 bucket for WAF logs
aws s3 mb s3://mcpgateway-waf-logs

# Enable WAF logging (requires CloudFormation or custom Terraform resource)
aws wafv2 put-logging-configuration \
  --logging-configuration ResourceArn=arn:aws:wafv2:...,LogDestinationConfigs=arn:aws:s3:::mcpgateway-waf-logs/...
```

## Production Hardening Checklist

Before deploying to production, verify:

**Infrastructure**
- [ ] Using Aurora PostgreSQL (or RDS MySQL) with automatic backups enabled
- [ ] Multi-AZ deployment (replicas >= 2)
- [ ] VPC is private (ECS/EKS in private subnets only)
- [ ] NAT Gateway configured for outbound internet access
- [ ] Database and Redis in private subnets with restrictive security groups

**Security**
- [ ] All secrets stored in AWS Secrets Manager (not in code/env files)
- [ ] KMS encryption enabled for database and Redis
- [ ] WAF enabled on ALB with managed rules
- [ ] Security groups restrict ingress to required ports only
- [ ] IAM roles follow least-privilege principle

**TLS/HTTPS**
- [ ] Custom domain configured with ACM certificate
- [ ] HTTP redirects to HTTPS (443)
- [ ] TLS 1.2+ enforced (default in ALB)
- [ ] Secure cookies enabled (HttpOnly, SameSite=Strict)

**Observability**
- [ ] CloudWatch logs retention set (recommend 90 days minimum)
- [ ] Container Insights enabled (ECS)
- [ ] Alarms configured for 5xx errors and auth failures
- [ ] SNS topic created and subscribed for alert notifications

**Backups & Recovery**
- [ ] Automated database backups enabled (RDS/Aurora)
- [ ] Backup retention >= 7 days
- [ ] Test restore procedure quarterly
- [ ] Document Recovery Time Objective (RTO) and Recovery Point Objective (RPO)

**Access Control**
- [ ] Admin credentials rotated initially
- [ ] MFA enabled on AWS console accounts
- [ ] Only authorized admins can modify infrastructure
- [ ] Audit logging enabled in CloudTrail

## Troubleshooting

### Gateway Not Responding

**Symptom:** `curl: (7) Failed to connect`

**Diagnosis:**
```bash
# Check if ALB is healthy
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:... \
  --query 'TargetHealthDescriptions[].{Id,State,Reason}'

# Check ECS task status
aws ecs list-tasks --cluster mcpgateway --query 'taskArns'
aws ecs describe-tasks --cluster mcpgateway --tasks arn:aws:ecs:... \
  --query 'tasks[].{Status,LastStatus}'

# View task logs
aws logs tail /aws/ecs/mcpgateway --follow
```

**Resolution:**
- If target is "unhealthy": check health check endpoint (/health)
- If task is "STOPPED": check logs for startup errors
- If no tasks: `replicas` may be set to 0

### High Latency

**Symptom:** Response times > 1 second

**Diagnosis:**
```bash
# Check database connections
aws rds describe-db-instances --db-instance-identifier mcpgateway \
  --query 'DBInstances[].{DBInstanceStatus,PendingModifiedValues}'

# Check Aurora capacity
aws rds describe-db-clusters --db-cluster-identifier mcpgateway \
  --query 'DBClusters[].{Status,EngineVersion,AutomaticBackupRetentionPeriod}'

# View CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=mcpgateway \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 --statistics Average
```

**Resolution:**
- If Aurora CPU high: enable auto-scaling (increase max ACUs)
- If RDS instance undersized: manually scale up instance class
- If database connections saturated: enable RDS Proxy

### Database Connection Errors

**Symptom:** `Error connecting to database`

**Diagnosis:**
```bash
# Check security group rules
aws ec2 describe-security-groups --group-ids sg-0123456789abcdef0 \
  --query 'SecurityGroups[].IpPermissions[]' --output table

# Test connectivity from ECS task (if supported)
aws ecs execute-command \
  --cluster mcpgateway \
  --task <task-id> \
  --container mcpgateway \
  --interactive \
  --command "/bin/bash"

# Inside task: ping database
nslookup mcpgateway-aurora.123456.us-east-1.rds.amazonaws.com
```

**Resolution:**
- Check security group: database must allow port 5432 (PostgreSQL) or 3306 (MySQL) from ECS subnet
- Check subnet routes: private subnets need NAT or VPC endpoint for RDS access
- Check credentials: JWT_SECRET_KEY and auth_encryption_secret in Secrets Manager

### Memory or CPU Throttling

**Symptom:** Intermittent task crashes, OOM errors in logs

**Diagnosis:**
```bash
# Check ECS task definition
aws ecs describe-task-definition --task-definition mcpgateway \
  --query 'taskDefinition.containerDefinitions[].{Name,Memory,Cpu}'

# Check Container Insights metrics
aws cloudwatch get-metric-statistics \
  --namespace ECS/ContainerInsights \
  --metric-name MemoryUtilized \
  --dimensions Name=ServiceName,Value=mcpgateway \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 --statistics Maximum
```

**Resolution:**
- If memory maxed out: increase ECS task memory (requires custom module extension)
- If CPU throttled: increase task CPU allocation
- If cache bloated: reduce log_retention_days or clear CloudWatch logs

### WAF Blocking Legitimate Traffic

**Symptom:** `403 Forbidden` from AWS WAF

**Diagnosis:**
```bash
# Check WAF logs
aws s3 ls s3://mcpgateway-waf-logs/

# Extract and analyze
aws s3 cp s3://mcpgateway-waf-logs/path/to/log.gz - | gunzip | grep '403'
```

**Resolution:**
- Review WAF rule that triggered (check logs for rule action)
- Add exemption for legitimate traffic (IP whitelist, URL patterns)
- Contact AWS support if rule is too aggressive

### Secrets Not Injected Into Container

**Symptom:** `NameError: name 'JWT_SECRET_KEY' is not defined`

**Diagnosis:**
```bash
# Check Secrets Manager
aws secretsmanager list-secrets --query 'SecretList[].Name'

# Check IAM role permissions
aws iam get-role-policy --role-name mcpgateway-ecs-task-role \
  --policy-name secretsmanager-policy

# Check ECS task definition for secretsValueFrom
aws ecs describe-task-definition --task-definition mcpgateway \
  --query 'taskDefinition.containerDefinitions[].secrets'
```

**Resolution:**
- Verify secret ARN matches in task definition
- Verify IAM role has `secretsmanager:GetSecretValue` permission
- Restart ECS service: `aws ecs update-service --cluster mcpgateway --service mcpgateway-service --force-new-deployment`

### Certificate Validation Errors

**Symptom:** `SSL certificate problem: unable to get local issuer certificate`

**Diagnosis:**
```bash
# Check certificate status
aws acm describe-certificate --certificate-arn arn:aws:acm:... \
  --query 'Certificate.{Status,ValidationMethod,DomainValidationOptions}'

# Test TLS connection
openssl s_client -connect api.example.com:443 -servername api.example.com
```

**Resolution:**
- If certificate pending validation: wait for ACM to validate (typically 15 min)
- If certificate expired: check Route53 CNAME points to ALB
- If Domain Validation failed: verify Route53 hosted zone is authoritative for domain

---

For advanced topics, see [docs/advanced.md](./advanced.md).
