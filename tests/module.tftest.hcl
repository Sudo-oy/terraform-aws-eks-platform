# Plan-only tests. The AWS provider is mocked, so no credentials or cloud resources are needed:
#   terraform init -backend=false && terraform test

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["eu-west-3a", "eu-west-3b", "eu-west-3c"]
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:user/test"
    }
  }

  mock_data "aws_iam_session_context" {
    defaults = {
      issuer_arn = "arn:aws:iam::123456789012:user/test"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name = "test-cluster"
}

run "defaults_create_vpc_without_optional_resources" {
  command = plan

  assert {
    condition     = length(module.vpc) == 1
    error_message = "A VPC must be created by default."
  }

  assert {
    condition     = length(aws_db_instance.postgres) == 0
    error_message = "PostgreSQL must be disabled by default."
  }

  assert {
    condition     = length(aws_ecr_repository.this) == 0
    error_message = "No ECR repository must be created by default."
  }
}

run "postgres_is_private_encrypted_and_secret_managed" {
  command = plan

  variables {
    create_postgres  = true
    ecr_repositories = ["app"]
  }

  assert {
    condition     = aws_db_instance.postgres[0].publicly_accessible == false
    error_message = "PostgreSQL must never be publicly accessible."
  }

  assert {
    condition     = aws_db_instance.postgres[0].storage_encrypted == true
    error_message = "PostgreSQL storage must be encrypted."
  }

  assert {
    condition     = aws_db_instance.postgres[0].manage_master_user_password == true
    error_message = "The master password must be managed by Secrets Manager."
  }

  assert {
    condition     = aws_ecr_repository.this["app"].image_tag_mutability == "IMMUTABLE"
    error_message = "ECR tags must be immutable by default."
  }
}

run "rejects_invalid_cluster_name" {
  command = plan

  variables {
    name = "Invalid_Name"
  }

  expect_failures = [var.name]
}

run "requires_vpc_id_for_existing_vpc" {
  command = plan

  variables {
    create_vpc = false
  }

  expect_failures = [var.vpc_id, var.private_subnet_ids]
}

run "rejects_reserved_postgres_username" {
  command = plan

  variables {
    create_postgres   = true
    postgres_username = "admin"
  }

  expect_failures = [var.postgres_username]
}
