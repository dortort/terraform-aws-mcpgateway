locals {
  # Parse S3 bucket and key from policy_bundle_s3_key ("bucket/path/to/bundle.tar.gz")
  policy_bundle_parts     = var.policy_bundle_s3_key != "" ? split("/", var.policy_bundle_s3_key) : []
  policy_bundle_s3_bucket = length(local.policy_bundle_parts) > 0 ? local.policy_bundle_parts[0] : ""
  policy_bundle_s3_key    = length(local.policy_bundle_parts) > 1 ? join("/", slice(local.policy_bundle_parts, 1, length(local.policy_bundle_parts))) : ""

  common_tags = merge(var.tags, {
    ManagedBy = "terraform"
    Module    = "terraform-aws-mcpgateway"
  })
}

# -----------------------------------------------------------------------------
# Data sources
# -----------------------------------------------------------------------------

data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

module "networking" {
  source = "./modules/networking"

  create_vpc              = var.create_vpc
  vpc_id                  = var.vpc_id
  private_subnet_ids      = var.private_subnet_ids
  public_subnet_ids       = var.public_subnet_ids
  alb_ingress_cidr_blocks = var.alb_ingress_cidr_blocks
  db_engine               = var.db_engine
  enable_redis            = var.enable_redis
  log_retention_days      = var.observability.log_retention_days
  tags                    = local.common_tags
}

# -----------------------------------------------------------------------------
# Secrets
# -----------------------------------------------------------------------------

module "secrets" {
  source = "./modules/secrets"

  jwt_secret_key         = var.jwt_secret_key
  auth_encryption_secret = var.auth_encryption_secret
  admin_email            = var.admin_email
  admin_password         = var.admin_password
  tags                   = local.common_tags
}

# -----------------------------------------------------------------------------
# Database (skip for SQLite)
# -----------------------------------------------------------------------------

module "database" {
  source = "./modules/database"
  count  = var.db_engine != "sqlite" ? 1 : 0

  db_engine          = var.db_engine
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  security_group_id  = module.networking.database_security_group_id
  db_password        = module.secrets.db_password
  kms_key_arn        = module.secrets.kms_key_arn
  tags               = local.common_tags
}

# -----------------------------------------------------------------------------
# Cache (optional Redis)
# -----------------------------------------------------------------------------

module "cache" {
  source = "./modules/cache"
  count  = var.enable_redis ? 1 : 0

  private_subnet_ids = module.networking.private_subnet_ids
  security_group_id  = module.networking.redis_security_group_id
  auth_token         = module.secrets.redis_auth_token
  kms_key_arn        = module.secrets.kms_key_arn
  tags               = local.common_tags
}

# -----------------------------------------------------------------------------
# DNS + ACM (when custom_domain is set)
# -----------------------------------------------------------------------------

module "dns" {
  source = "./modules/dns"
  count  = var.custom_domain != "" ? 1 : 0

  custom_domain = var.custom_domain
  alb_dns_name  = module.load_balancer.alb_dns_name
  alb_zone_id   = module.load_balancer.alb_zone_id
  tags          = local.common_tags
}

# -----------------------------------------------------------------------------
# Load Balancer
# -----------------------------------------------------------------------------

module "load_balancer" {
  source = "./modules/load-balancer"

  vpc_id            = module.networking.vpc_id
  public_subnet_ids = module.networking.public_subnet_ids
  security_group_id = module.networking.alb_security_group_id
  certificate_arn   = var.custom_domain != "" ? module.dns[0].certificate_arn : ""
  enable_waf        = var.enable_waf
  tags              = local.common_tags
}

# -----------------------------------------------------------------------------
# ECS Fargate
# -----------------------------------------------------------------------------

module "ecs" {
  source = "./modules/ecs"
  count  = var.cluster_type == "ecs" ? 1 : 0

  gateway_version    = var.gateway_version
  replicas           = var.replicas
  private_subnet_ids = module.networking.private_subnet_ids
  security_group_id  = module.networking.gateway_security_group_id
  target_group_arn   = module.load_balancer.target_group_arn

  secret_arns = {
    jwt_secret_key         = module.secrets.jwt_secret_arn
    auth_encryption_secret = module.secrets.auth_encryption_secret_arn
    admin_password         = module.secrets.admin_password_arn
    db_password            = module.secrets.db_password_arn
    redis_auth_token       = module.secrets.redis_auth_token_arn
  }

  admin_email = var.admin_email
  db_endpoint = var.db_engine != "sqlite" ? module.database[0].endpoint : ""
  db_port     = var.db_engine != "sqlite" ? module.database[0].port : 0
  db_name     = var.db_engine != "sqlite" ? module.database[0].db_name : ""
  db_username = var.db_engine != "sqlite" ? module.database[0].username : ""
  db_engine   = var.db_engine

  redis_endpoint = var.enable_redis ? module.cache[0].endpoint : ""
  redis_port     = var.enable_redis ? module.cache[0].port : 6379
  enable_redis   = var.enable_redis

  policy_bundle_s3_bucket = local.policy_bundle_s3_bucket
  policy_bundle_s3_key    = local.policy_bundle_s3_key
  gateway_env             = var.gateway_env

  enable_container_insights    = var.observability.enable_container_insights
  log_retention_days           = var.observability.log_retention_days
  alarm_5xx_threshold          = var.observability.alarm_5xx_threshold
  alarm_auth_failure_threshold = var.observability.alarm_auth_failure_threshold
  tags                         = local.common_tags
}

# -----------------------------------------------------------------------------
# EKS (infra only)
# -----------------------------------------------------------------------------

module "eks" {
  source = "./modules/eks"
  count  = var.cluster_type == "eks" ? 1 : 0

  private_subnet_ids = module.networking.private_subnet_ids
  public_subnet_ids  = module.networking.public_subnet_ids
  security_group_id  = module.networking.gateway_security_group_id
  kms_key_arn        = module.secrets.kms_key_arn
  tags               = local.common_tags
}

# -----------------------------------------------------------------------------
# Kubernetes provider (for EKS path)
# -----------------------------------------------------------------------------

provider "kubernetes" {
  host                   = var.cluster_type == "eks" ? module.eks[0].cluster_endpoint : "https://localhost"
  cluster_ca_certificate = var.cluster_type == "eks" ? base64decode(module.eks[0].cluster_certificate_authority) : ""
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = var.cluster_type == "eks" ? ["eks", "get-token", "--cluster-name", module.eks[0].cluster_name] : []
  }
}

provider "helm" {
  kubernetes {
    host                   = var.cluster_type == "eks" ? module.eks[0].cluster_endpoint : "https://localhost"
    cluster_ca_certificate = var.cluster_type == "eks" ? base64decode(module.eks[0].cluster_certificate_authority) : ""
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = var.cluster_type == "eks" ? ["eks", "get-token", "--cluster-name", module.eks[0].cluster_name] : []
    }
  }
}

# -----------------------------------------------------------------------------
# Kubernetes resources (EKS path only)
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "mcpgw" {
  count = var.cluster_type == "eks" ? 1 : 0

  metadata {
    name = "mcpgateway"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_secret" "mcpgw" {
  count = var.cluster_type == "eks" ? 1 : 0

  metadata {
    name      = "mcpgw-secrets"
    namespace = kubernetes_namespace.mcpgw[0].metadata[0].name
  }

  data = {
    JWT_SECRET_KEY          = var.jwt_secret_key
    AUTH_ENCRYPTION_SECRET  = var.auth_encryption_secret
    PLATFORM_ADMIN_PASSWORD = var.admin_password
    DATABASE_URL = var.db_engine != "sqlite" ? (
      var.db_engine == "aurora-postgresql"
      ? "postgresql+psycopg://${module.database[0].username}:${module.secrets.db_password}@${module.database[0].endpoint}:${module.database[0].port}/${module.database[0].db_name}"
      : "mysql+pymysql://${module.database[0].username}:${module.secrets.db_password}@${module.database[0].endpoint}:${module.database[0].port}/${module.database[0].db_name}"
    ) : "sqlite:///data/mcpgateway.db"
    REDIS_URL = var.enable_redis ? "rediss://:${module.secrets.redis_auth_token}@${module.cache[0].endpoint}:${module.cache[0].port}/0" : ""
  }
}

resource "kubernetes_deployment" "mcpgw" {
  count = var.cluster_type == "eks" ? 1 : 0

  metadata {
    name      = "mcpgateway"
    namespace = kubernetes_namespace.mcpgw[0].metadata[0].name
    labels = {
      "app.kubernetes.io/name" = "mcpgateway"
    }
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "mcpgateway"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "mcpgateway"
        }
      }

      spec {
        security_context {
          run_as_user     = 1001
          run_as_non_root = true
          fs_group        = 1001
        }

        container {
          name  = "mcpgateway"
          image = "ghcr.io/ibm/mcp-context-forge:${var.gateway_version}"

          port {
            container_port = 4444
            protocol       = "TCP"
          }

          env {
            name  = "HOST"
            value = "0.0.0.0"
          }
          env {
            name  = "PORT"
            value = "4444"
          }
          env {
            name  = "ENVIRONMENT"
            value = "production"
          }
          env {
            name  = "HTTP_SERVER"
            value = "gunicorn"
          }
          env {
            name  = "PLATFORM_ADMIN_EMAIL"
            value = var.admin_email
          }
          env {
            name  = "CACHE_TYPE"
            value = var.enable_redis ? "redis" : "simple"
          }
          env {
            name  = "SSRF_PROTECTION_ENABLED"
            value = "true"
          }
          env {
            name  = "SSRF_ALLOW_LOCALHOST"
            value = "false"
          }
          env {
            name  = "SSRF_ALLOW_PRIVATE_NETWORKS"
            value = "false"
          }
          env {
            name  = "SECURE_COOKIES"
            value = "true"
          }

          dynamic "env" {
            for_each = var.gateway_env
            content {
              name  = env.key
              value = env.value
            }
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.mcpgw[0].metadata[0].name
            }
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 4444
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = 4444
            }
            initial_delay_seconds = 15
            period_seconds        = 5
          }

          security_context {
            read_only_root_filesystem  = true
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }
          volume_mount {
            name       = "app-logs"
            mount_path = "/app/logs"
          }
        }

        volume {
          name = "tmp"
          empty_dir {}
        }
        volume {
          name = "app-logs"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service" "mcpgw" {
  count = var.cluster_type == "eks" ? 1 : 0

  metadata {
    name      = "mcpgateway"
    namespace = kubernetes_namespace.mcpgw[0].metadata[0].name
  }

  spec {
    selector = {
      "app.kubernetes.io/name" = "mcpgateway"
    }

    port {
      port        = 4444
      target_port = 4444
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}
