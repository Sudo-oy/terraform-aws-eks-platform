provider "aws" {
  region = var.region
}

module "eks" {
  source = "../../"

  name               = var.name
  kubernetes_version = "1.34"

  # Restrict API access to your own public IP range in real environments.
  endpoint_public_access_cidrs = var.allowed_cidrs

  node_groups = {
    default = {
      instance_types = ["t3.medium"]
      min_size       = 1
      desired_size   = 2
      max_size       = 3
    }
  }

  ecr_repositories = ["${var.name}-app"]

  # PostgreSQL is optional. The password is managed by AWS Secrets Manager.
  create_postgres              = true
  postgres_deletion_protection = false

  tags = {
    environment = "demo"
  }
}
