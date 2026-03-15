# Advanced Configuration Guide

This document covers advanced deployment patterns, optimization, and operational procedures for terraform-aws-mcpgateway.

## Table of Contents

1. [Remote State Backend](#remote-state-backend)
2. [Multi-Region Deployments](#multi-region-deployments)
3. [Scaling and Performance Tuning](#scaling-and-performance-tuning)
4. [Integration with Existing AWS Infrastructure](#integration-with-existing-aws-infrastructure)
5. [Upgrading Gateway Version](#upgrading-gateway-version)
6. [Backup and Disaster Recovery](#backup-and-disaster-recovery)
7. [Cost Optimization](#cost-optimization)

## Remote State Backend

### S3 + DynamoDB Backend

For production, store Terraform state remotely with locking:

**Step 1: Create S3 backend bucket**

```bash
aws s3api create-bucket \
  --bucket my-terraform-state-mcpgateway \
  --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket my-terraform-state-mcpgateway \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket my-terraform-state-mcpgateway \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}
    }]
  }'

# Block public access
aws s3api put-public-access-block \
  --bucket my-terraform-state-mcpgateway \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

**Step 2: Create DynamoDB lock table**

```bash
aws dynamodb create-table \
  --table-name mcpgateway-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

**Step 3: Configure Terraform backend**

Create `backend-config.hcl`:

```hcl
bucket         = "my-terraform-state-mcpgateway"
key            = "prod/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "mcpgateway-terraform-locks"
encrypt        = true
```

In `main.tf`:

```hcl
terraform {
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

# ... rest of configuration
```

Initialize backend:

```bash
terraform init -backend-config=backend-config.hcl
```

**Verify backend:**

```bash
# Check state file is remote
terraform state list

# View lock status
aws dynamodb scan --table-name mcpgateway-terraform-locks
```

### State Locking

Lock prevents concurrent modifications:

```bash
# Manual lock (for debugging)
aws dynamodb put-item \
  --table-name mcpgateway-terraform-locks \
  --item '{"LockID":{"S":"prod/terraform.tfstate"},"Info":{"S":"Manual lock for maintenance"}}'

# Unlock
aws dynamodb delete-item \
  --table-name mcpgateway-terraform-locks \
  --key '{"LockID":{"S":"prod/terraform.tfstate"}}'
```

## Multi-Region Deployments

Deploy MCP Context Forge across AWS regions for high availability and disaster recovery.

### Single-Master, Multi-Replica Architecture

**Primary Region:** `us-east-1` (active)
**Secondary Region:** `us-west-2` (standby, manual failover)

**Step 1: Deploy primary**

```hcl
# terraform/prod-us-east-1/main.tf

provider "aws" {
  region = "us-east-1"
}

module "mcpgateway_primary" {
  source = "../../"

  cluster_type    = "ecs"
  replicas        = 3
  db_engine       = "aurora-postgresql"
  enable_redis    = true
  custom_domain   = "api.example.com"  # Primary domain

  tags = {
    Region   = "us-east-1"
    Role     = "primary"
    FailOver = "primary"
  }
}

output "primary_database_endpoint" {
  value = module.mcpgateway_primary.database_endpoint
}
```

**Step 2: Deploy secondary (manual standby)**

```hcl
# terraform/prod-us-west-2/main.tf

provider "aws" {
  region = "us-west-2"
}

# Create cross-region Aurora read replica
resource "aws_rds_cluster_instance" "read_replica" {
  identifier         = "mcpgateway-aurora-read-replica"
  cluster_identifier = var.primary_cluster_id  # From primary region output
  instance_class     = "db.serverless"
  engine             = "aurora-postgresql"
  publicly_accessible = false
}

module "mcpgateway_secondary" {
  source = "../../"

  cluster_type  = "ecs"
  replicas      = 2
  db_engine     = "aurora-postgresql"  # Uses read replica above
  custom_domain = ""  # No custom domain; use ALB DNS for failover

  tags = {
    Region   = "us-west-2"
    Role     = "secondary"
    FailOver = "standby"
  }
}
```

**Step 3: Manual failover procedure**

When primary fails, promote secondary:

```bash
# 1. Promote read replica to standalone cluster
aws rds modify-db-cluster \
  --db-cluster-identifier mcpgateway-aurora-read-replica \
  --enable-iam-database-authentication \
  --apply-immediately

# 2. Verify secondary is accessible
aws rds describe-db-clusters \
  --db-cluster-identifier mcpgateway-aurora-read-replica \
  --query 'DBClusters[0].Endpoint'

# 3. Update Route53 to point api.example.com to us-west-2 ALB
aws route53 change-resource-record-sets \
  --hosted-zone-id Z123456789ABC \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.example.com",
        "Type": "CNAME",
        "TTL": 60,
        "ResourceRecords": [{"Value": "us-west-2-alb-dns.elb.amazonaws.com"}]
      }
    }]
  }'

# 4. Verify traffic now hits secondary
curl -I https://api.example.com
```

### Automated Multi-Region with Route53 Health Checks

For truly automated failover, configure Route53 health checks:

```bash
# Create health check for primary
aws route53 create-health-check \
  --health-check-config \
  IPAddress=<PRIMARY_ALB_IP>,Port=443,Type=HTTPS,ResourcePath=/health

# Create health check for secondary
aws route53 create-health-check \
  --health-check-config \
  IPAddress=<SECONDARY_ALB_IP>,Port=443,Type=HTTPS,ResourcePath=/health

# Update Route53 record set with failover policy
aws route53 change-resource-record-sets \
  --hosted-zone-id Z123456789ABC \
  --change-batch file://failover-policy.json
```

File: `failover-policy.json`

```json
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.example.com",
        "Type": "A",
        "SetIdentifier": "Primary-US-EAST-1",
        "Failover": "PRIMARY",
        "HealthCheckId": "abcd1234-health-check-id",
        "AliasTarget": {
          "HostedZoneId": "Z35SXDOTRQ7X7K",
          "DNSName": "mcpgateway-alb-us-east-1.elb.amazonaws.com",
          "EvaluateTargetHealth": true
        }
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.example.com",
        "Type": "A",
        "SetIdentifier": "Secondary-US-WEST-2",
        "Failover": "SECONDARY",
        "HealthCheckId": "efgh5678-health-check-id",
        "AliasTarget": {
          "HostedZoneId": "Z1H1FL5HABSF5",
          "DNSName": "mcpgateway-alb-us-west-2.elb.amazonaws.com",
          "EvaluateTargetHealth": true
        }
      }
    }
  ]
}
```

## Scaling and Performance Tuning

### Horizontal Scaling (Add Replicas)

Increase throughput by adding more gateway replicas:

```hcl
module "mcpgateway" {
  replicas = 10  # Scale from 2 to 10

  # ALB auto-distributes traffic across all replicas
}
```

Apply:

```bash
terraform apply -auto-approve
# Terraform will create 8 new ECS tasks over ~2 minutes
```

### Vertical Scaling (Larger Instances)

For ECS, increase per-task CPU/memory (requires custom module extension):

```hcl
# Extend ECS module or create custom resource
resource "aws_ecs_task_definition" "mcpgateway_large" {
  cpu           = 2048  # 2 vCPU (default: 1024)
  memory        = 4096  # 4 GB (default: 2048)
  # ... rest of definition
}
```

For Aurora, increase ACU range:

```bash
# Update Aurora cluster capacity
aws rds modify-db-cluster \
  --db-cluster-identifier mcpgateway \
  --serverlessv2-scaling-configuration MinCapacity=1.0,MaxCapacity=16.0
```

### Database Connection Pooling

For RDS MySQL/Aurora PostgreSQL, enable RDS Proxy:

```bash
# Create RDS Proxy
aws rds create-db-proxy \
  --db-proxy-name mcpgateway-proxy \
  --engine-family POSTGRESQL \
  --auth '{"AuthScheme":"SECRETS","SecretArn":"arn:aws:secretsmanager:..."}' \
  --role-arn arn:aws:iam::123456789:role/rds-proxy-role \
  --db-subnet-group-name mcpgateway-db-subnet-group

# Point application to proxy instead of direct endpoint
export DATABASE_URL="postgresql://user:pass@mcpgateway-proxy.12345.us-east-1.rds.amazonaws.com:5432/mcpgateway"
```

### Redis Cluster Mode

For high-throughput caching, enable Redis Cluster:

```bash
# Modify ElastiCache cluster
aws elasticache modify-replication-group \
  --replication-group-id mcpgateway-redis \
  --automatic-failover-enabled \
  --apply-immediately
```

### Query Optimization

Monitor slow queries in Aurora:

```bash
# Enable slow query log
aws rds modify-db-instance \
  --db-instance-identifier mcpgateway-aurora \
  --db-parameter-group-name default.aurora-postgresql \
  --apply-immediately

# View slow queries
aws logs filter-log-events \
  --log-group-name /aws/rds/instance/mcpgateway-aurora/postgresql \
  --filter-pattern 'duration'
```

## Integration with Existing AWS Infrastructure

### Use Existing KMS Key

```hcl
module "mcpgateway" {
  # Modify secrets module to use existing key
  # Requires custom module extension

  tags = {
    KMSKey = "arn:aws:kms:us-east-1:123456789:key/12345678-1234-1234-1234-123456789012"
  }
}
```

### Use Existing ALB

If ALB already exists, bypass module ALB creation:

```hcl
# Create custom target group
resource "aws_lb_target_group" "mcpgateway" {
  name        = "mcpgateway"
  port        = 4444
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
  }
}

# Register with existing ALB
resource "aws_lb_listener" "mcpgateway" {
  load_balancer_arn = var.existing_alb_arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = var.existing_cert_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mcpgateway.arn
  }
}
```

### Use Existing RDS Instance

Connect to existing RDS database:

```hcl
module "mcpgateway" {
  create_vpc = false
  vpc_id     = var.existing_vpc_id

  # Skip database module
  # Instead, configure gateway to use existing database
  gateway_env = {
    DATABASE_URL = "postgresql://user:pass@existing-rds.12345.us-east-1.rds.amazonaws.com:5432/mcpgateway"
  }
}
```

### Use Existing NAT Gateway

```hcl
module "mcpgateway" {
  create_vpc = false
  vpc_id     = var.existing_vpc_id

  # Existing VPC must have a NAT Gateway for private subnet outbound access
  # Terraform will use existing route tables and subnets
}
```

## Upgrading Gateway Version

### Minor/Patch Version Upgrade (e.g., v1.0.0 → v1.0.1)

Non-breaking updates are safe to deploy:

```hcl
module "mcpgateway" {
  gateway_version = "v1.0.1"  # Changed from v1.0.0
}
```

Apply with zero-downtime rolling deployment:

```bash
terraform apply

# Terraform will:
# 1. Create new ECS task definition with new image
# 2. Update ECS service to use new definition
# 3. Start new tasks, terminate old ones one-by-one
# 4. ALB routes traffic to healthy tasks only
```

Monitor rollout:

```bash
# Watch deployment progress
watch -n 5 'aws ecs describe-services --cluster mcpgateway --services mcpgateway-service --query "services[].{RunningCount,DesiredCount,DeploymentConfiguration}"'

# View events
aws ecs describe-services --cluster mcpgateway --services mcpgateway-service --query 'services[].events[0:5]'
```

### Major Version Upgrade (e.g., v1.0.0 → v2.0.0)

Major upgrades may require database migrations. Follow application release notes, then:

```hcl
module "mcpgateway" {
  gateway_version = "v2.0.0"
  replicas        = 1  # Temporarily reduce to 1 for migration
}
```

Apply:

```bash
terraform apply

# Monitor logs for migration progress
aws logs tail /aws/ecs/mcpgateway --follow

# Once migration completes, scale back up
terraform apply -var replicas=3
```

### Rollback to Previous Version

If upgrade fails:

```hcl
module "mcpgateway" {
  gateway_version = "v1.0.0"  # Revert to previous version
}
```

```bash
terraform apply

# Terraform will roll back immediately (no data loss if using managed database)
```

## Backup and Disaster Recovery

### Aurora Automated Backups

Aurora maintains automatic backups with point-in-time recovery:

```bash
# Check backup retention
aws rds describe-db-clusters \
  --db-cluster-identifier mcpgateway \
  --query 'DBClusters[].BackupRetentionPeriod'

# Modify retention (1-35 days)
aws rds modify-db-cluster \
  --db-cluster-identifier mcpgateway \
  --backup-retention-period 30 \
  --apply-immediately
```

### Manual Snapshots

Create manual snapshots before major changes:

```bash
# Create snapshot
aws rds create-db-cluster-snapshot \
  --db-cluster-snapshot-identifier mcpgateway-backup-$(date +%Y%m%d-%H%M%S) \
  --db-cluster-identifier mcpgateway

# List snapshots
aws rds describe-db-cluster-snapshots --query 'DBClusterSnapshots[].{DBClusterSnapshotIdentifier,SnapshotCreateTime,Status}'
```

### Restore from Snapshot

Restore to new cluster:

```bash
aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier mcpgateway-restored \
  --snapshot-identifier mcpgateway-backup-20240315-120000 \
  --engine aurora-postgresql

# Wait for restore to complete (~5 minutes)
watch -n 10 'aws rds describe-db-clusters --db-cluster-identifier mcpgateway-restored --query "DBClusters[].Status"'

# Point application to restored database
export DATABASE_URL="postgresql://user:pass@mcpgateway-restored.12345.us-east-1.rds.amazonaws.com:5432/mcpgateway"
```

### Point-in-Time Recovery

Restore to a specific time (within backup retention period):

```bash
aws rds restore-db-cluster-to-point-in-time \
  --db-cluster-identifier mcpgateway-pitr \
  --source-db-cluster-identifier mcpgateway \
  --restore-type copy-on-write \
  --restore-to-time 2024-03-15T12:00:00Z
```

### Backup Verification

Test restore procedure quarterly:

```bash
# Create test snapshot
SNAPSHOT_ID="mcpgateway-test-$(date +%Y%m%d)"
aws rds create-db-cluster-snapshot \
  --db-cluster-snapshot-identifier $SNAPSHOT_ID \
  --db-cluster-identifier mcpgateway

# Restore to test database
aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier mcpgateway-restore-test \
  --snapshot-identifier $SNAPSHOT_ID \
  --engine aurora-postgresql

# Run smoke tests on restored database
# ... application-specific tests ...

# Delete test database
aws rds delete-db-cluster \
  --db-cluster-identifier mcpgateway-restore-test \
  --skip-final-snapshot
```

### RDS MySQL Backups

For RDS MySQL (non-Aurora):

```bash
# Create manual snapshot
aws rds create-db-snapshot \
  --db-snapshot-identifier mcpgateway-mysql-backup \
  --db-instance-identifier mcpgateway-rds-mysql

# Restore from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier mcpgateway-mysql-restored \
  --db-snapshot-identifier mcpgateway-mysql-backup
```

## Cost Optimization

### Reserved Capacity

Pre-purchase capacity at 30% discount:

```bash
# For Aurora Serverless v2 (ACUs)
aws rds purchase-reserved-db-instances-offering \
  --reserved-db-instances-offering-id <offering-id> \
  --reserved-db-instance-id mcpgateway-1-year \
  --db-instance-count 1

# For ECS on-demand (requires Compute Savings Plans, purchased via AWS Console)
```

### Scheduled Scaling

Turn off dev/test environments outside business hours:

```bash
# Use CloudWatch Events + Lambda to scale down at night
# Example: scale replicas to 0 at 6 PM, back to 2 at 8 AM
```

### Spot Instances for ECS

Use EC2 Spot for cost-sensitive workloads (ECS on EC2, not Fargate):

```bash
# Configure ECS cluster with Spot instances (requires custom setup)
# Spot can save 70% vs on-demand
```

### Database Sizing

Right-size Aurora capacity:

```bash
# Monitor ACU usage over time
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBClusterIdentifier,Value=mcpgateway \
  --start-time $(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Maximum

# If consistently below 1.0 ACU: reduce min capacity to 0.5 ACU
# If consistently above 4.0 ACU: increase max capacity
```

### Unused Resource Cleanup

Identify and remove unused resources:

```bash
# Find unattached EBS volumes
aws ec2 describe-volumes --filters Name=status,Values=available --query 'Volumes[].VolumeId'

# Find unused Elastic IPs
aws ec2 describe-addresses --filters Name=association-id,Values="" --query 'Addresses[].PublicIp'

# Find unused security groups
aws ec2 describe-security-groups --query 'SecurityGroups[?GroupName!=`default`]' --output table
```

### Leverage AWS Free Tier

- 750 hours/month of ECS Fargate (12-month free tier)
- 750 hours/month of RDS db.t2.micro/db.t3.micro
- 15 GB egress data transfer
- 1 million CloudWatch alarms

Estimate free tier coverage:

```bash
# Calculate Fargate hours
REPLICAS=2
HOURS_PER_MONTH=730
FARGATE_HOURS=$((REPLICAS * HOURS_PER_MONTH))
echo "Fargate hours: $FARGATE_HOURS / 750"
```

---

For basic configuration, see [docs/README.md](./README.md).
