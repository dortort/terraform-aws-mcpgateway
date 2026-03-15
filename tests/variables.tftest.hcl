# Test valid orchestrator values
run "valid_ecs_orchestrator" {
  command = plan

  variables {
    orchestrator           = "ecs"
    jwt_secret_key         = "test-jwt-secret-key-123456"
    auth_encryption_secret = "test-auth-encryption-secret-123456"
    admin_email            = "admin@example.com"
    admin_password         = "test-admin-password-123456"
  }
}

run "valid_eks_orchestrator" {
  command = plan

  variables {
    orchestrator           = "eks"
    jwt_secret_key         = "test-jwt-secret-key-123456"
    auth_encryption_secret = "test-auth-encryption-secret-123456"
    admin_email            = "admin@example.com"
    admin_password         = "test-admin-password-123456"
  }
}

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

# Test valid compute_type values
run "valid_fargate_compute" {
  command = plan

  variables {
    compute_type           = "fargate"
    jwt_secret_key         = "test-jwt-secret-key-123456"
    auth_encryption_secret = "test-auth-encryption-secret-123456"
    admin_email            = "admin@example.com"
    admin_password         = "test-admin-password-123456"
  }
}

run "valid_ec2_compute" {
  command = plan

  variables {
    compute_type           = "ec2"
    jwt_secret_key         = "test-jwt-secret-key-123456"
    auth_encryption_secret = "test-auth-encryption-secret-123456"
    admin_email            = "admin@example.com"
    admin_password         = "test-admin-password-123456"
  }
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

# Test ECS + EC2 combination
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

# Test EKS + Fargate combination
run "eks_fargate_combination" {
  command = plan

  variables {
    orchestrator           = "eks"
    compute_type           = "fargate"
    jwt_secret_key         = "test-jwt-secret-key-123456"
    auth_encryption_secret = "test-auth-encryption-secret-123456"
    admin_email            = "admin@example.com"
    admin_password         = "test-admin-password-123456"
  }
}

# Test valid db_engine values
run "valid_aurora_db_engine" {
  command = plan

  variables {
    db_engine              = "aurora-postgresql"
    jwt_secret_key         = "test-jwt-secret-key-123456"
    auth_encryption_secret = "test-auth-encryption-secret-123456"
    admin_email            = "admin@example.com"
    admin_password         = "test-admin-password-123456"
  }
}

run "valid_mysql_db_engine" {
  command = plan

  variables {
    db_engine              = "rds-mysql"
    jwt_secret_key         = "test-jwt-secret-key-123456"
    auth_encryption_secret = "test-auth-encryption-secret-123456"
    admin_email            = "admin@example.com"
    admin_password         = "test-admin-password-123456"
  }
}

run "valid_sqlite_db_engine" {
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
