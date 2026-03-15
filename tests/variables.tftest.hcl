mock_provider "aws" {
  override_data {
    target = module.networking.data.aws_availability_zones.available
    values = {
      names = ["us-east-1a", "us-east-1b"]
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      name = "us-east-1"
    }
  }

  override_data {
    target = module.ecs[0].data.aws_region.current
    values = {
      name = "us-east-1"
    }
  }

  override_data {
    target = module.ecs[0].data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = module.ecs[0].data.aws_iam_policy_document.ecs_assume_role
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"ecs-tasks.amazonaws.com\"},\"Action\":\"sts:AssumeRole\"}]}"
    }
  }

  override_data {
    target = module.ecs[0].data.aws_ssm_parameter.ecs_ami[0]
    values = {
      value = "ami-12345678"
    }
  }
}

mock_provider "kubernetes" {}
mock_provider "helm" {}
mock_provider "random" {}
mock_provider "tls" {}

# --- Variable validation tests (negative cases) ---

# Test invalid orchestrator
run "invalid_orchestrator" {
  command = plan

  variables {
    orchestrator           = "lambda"
    jwt_secret_key         = "test-jwt-secret-key-123456"
    auth_encryption_secret = "test-auth-encryption-secret-123456"
    admin_email            = "admin@example.com"
    admin_password         = "test-admin-password-123456"
  }

  expect_failures = [
    var.orchestrator,
  ]
}

# Test invalid compute_type
run "invalid_compute_type" {
  command = plan

  variables {
    compute_type           = "spot"
    jwt_secret_key         = "test-jwt-secret-key-123456"
    auth_encryption_secret = "test-auth-encryption-secret-123456"
    admin_email            = "admin@example.com"
    admin_password         = "test-admin-password-123456"
  }

  expect_failures = [
    var.compute_type,
  ]
}

# Test invalid db_engine
run "invalid_db_engine" {
  command = plan

  variables {
    db_engine              = "dynamodb"
    jwt_secret_key         = "test-jwt-secret-key-123456"
    auth_encryption_secret = "test-auth-encryption-secret-123456"
    admin_email            = "admin@example.com"
    admin_password         = "test-admin-password-123456"
  }

  expect_failures = [
    var.db_engine,
  ]
}

# Test invalid admin_email
run "invalid_admin_email" {
  command = plan

  variables {
    admin_email            = "not-an-email"
    jwt_secret_key         = "test-jwt-secret-key-123456"
    auth_encryption_secret = "test-auth-encryption-secret-123456"
    admin_password         = "test-admin-password-123456"
  }

  expect_failures = [
    var.admin_email,
  ]
}

# --- Positive plan tests (default ECS + Fargate) ---

run "valid_ecs_fargate_default" {
  command = plan

  variables {
    jwt_secret_key         = "test-jwt-secret-key-123456"
    auth_encryption_secret = "test-auth-encryption-secret-123456"
    admin_email            = "admin@example.com"
    admin_password         = "test-admin-password-123456"
  }
}

# --- Combination tests ---

run "ecs_ec2_combination" {
  command = plan

  variables {
    orchestrator           = "ecs"
    compute_type           = "ec2"
    jwt_secret_key         = "test-jwt-secret-key-123456"
    auth_encryption_secret = "test-auth-encryption-secret-123456"
    admin_email            = "admin@example.com"
    admin_password         = "test-admin-password-123456"
  }
}

run "valid_sqlite_single_replica" {
  command = plan

  variables {
    db_engine              = "sqlite"
    replicas               = 1
    jwt_secret_key         = "test-jwt-secret-key-123456"
    auth_encryption_secret = "test-auth-encryption-secret-123456"
    admin_email            = "admin@example.com"
    admin_password         = "test-admin-password-123456"
  }
}
