# Test valid cluster_type values
run "valid_ecs_cluster_type" {
  command = plan

  variables {
    cluster_type           = "ecs"
    jwt_secret_key         = "test-jwt-secret-key-123456"
    auth_encryption_secret = "test-auth-encryption-secret-123456"
    admin_email            = "admin@example.com"
    admin_password         = "test-admin-password-123456"
  }
}

run "valid_eks_cluster_type" {
  command = plan

  variables {
    cluster_type           = "eks"
    jwt_secret_key         = "test-jwt-secret-key-123456"
    auth_encryption_secret = "test-auth-encryption-secret-123456"
    admin_email            = "admin@example.com"
    admin_password         = "test-admin-password-123456"
  }
}

# Test invalid cluster_type
run "invalid_cluster_type" {
  command = plan

  variables {
    cluster_type           = "lambda"
    jwt_secret_key         = "test-jwt-secret-key-123456"
    auth_encryption_secret = "test-auth-encryption-secret-123456"
    admin_email            = "admin@example.com"
    admin_password         = "test-admin-password-123456"
  }

  expect_failures = [
    var.cluster_type,
  ]
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
