data "aws_partition" "current" {}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  vpc_id             = var.create_vpc ? module.vpc[0].vpc_id : var.vpc_id
  private_subnet_ids = var.create_vpc ? module.vpc[0].private_subnets : var.private_subnet_ids
  database_subnet_ids = var.create_vpc ? (
    var.create_postgres ? module.vpc[0].database_subnets : []
  ) : var.database_subnet_ids

  tags = merge(
    {
      "terraform-module" = "terraform-aws-eks-platform"
      "cluster"          = var.name
    },
    var.tags,
  )
}

################################################################################
# Networking
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.2"
  count   = var.create_vpc ? 1 : 0

  name = "${var.name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  # /20 private subnets for pods and nodes, /24 public subnets for load balancers,
  # /24 database subnets (only when PostgreSQL is enabled).
  private_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets   = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, 48 + i)]
  database_subnets = var.create_postgres ? [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, 52 + i)] : []

  create_database_subnet_group = false

  enable_nat_gateway = true
  single_nat_gateway = var.single_nat_gateway

  enable_flow_log                                 = var.enable_vpc_flow_logs
  create_flow_log_cloudwatch_log_group            = var.enable_vpc_flow_logs
  create_flow_log_cloudwatch_iam_role             = var.enable_vpc_flow_logs
  flow_log_cloudwatch_log_group_retention_in_days = var.log_retention_in_days

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    # Lets Karpenter discover the subnets if it is installed on the cluster.
    "karpenter.sh/discovery" = var.name
  }

  tags = local.tags
}

################################################################################
# EKS cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.25.0"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  vpc_id     = local.vpc_id
  subnet_ids = local.private_subnet_ids

  endpoint_public_access       = var.endpoint_public_access
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions
  access_entries                           = var.access_entries

  enabled_log_types                      = var.cluster_enabled_log_types
  cloudwatch_log_group_retention_in_days = var.log_retention_in_days

  addons = {
    vpc-cni = {
      before_compute = true
    }
    kube-proxy = {}
    coredns    = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
  }

  eks_managed_node_groups = {
    for name, ng in var.node_groups : name => {
      ami_type       = ng.ami_type
      instance_types = ng.instance_types
      capacity_type  = ng.capacity_type
      min_size       = ng.min_size
      max_size       = ng.max_size
      desired_size   = ng.desired_size
      labels         = ng.labels
    }
  }

  tags = local.tags
}

################################################################################
# Container registry (optional)
################################################################################

resource "aws_ecr_repository" "this" {
  for_each = toset(var.ecr_repositories)

  name                 = each.value
  image_tag_mutability = var.ecr_image_tag_mutability
  force_delete         = var.ecr_force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.ecr_kms_key_arn
  }

  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.ecr_max_image_count
      }
      action = {
        type = "expire"
      }
    }]
  })
}

################################################################################
# PostgreSQL (optional)
################################################################################

resource "aws_db_subnet_group" "postgres" {
  count = var.create_postgres ? 1 : 0

  name        = "${var.name}-postgres"
  description = "Subnets for the ${var.name} PostgreSQL instance"
  subnet_ids  = local.database_subnet_ids

  tags = local.tags
}

resource "aws_security_group" "postgres" {
  count = var.create_postgres ? 1 : 0

  name        = "${var.name}-postgres"
  description = "PostgreSQL access from the ${var.name} EKS nodes"
  vpc_id      = local.vpc_id

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_nodes" {
  count = var.create_postgres ? 1 : 0

  description                  = "PostgreSQL from EKS worker nodes"
  security_group_id            = aws_security_group.postgres[0].id
  referenced_security_group_id = module.eks.node_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_db_parameter_group" "postgres" {
  count = var.create_postgres ? 1 : 0

  name_prefix = "${var.name}-postgres-"
  description = "Parameters for the ${var.name} PostgreSQL instance"
  family      = "postgres${split(".", var.postgres_engine_version)[0]}"

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = tostring(var.postgres_log_min_duration_ms)
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = local.tags
}

data "aws_iam_policy_document" "rds_monitoring_assume" {
  count = var.create_postgres && var.postgres_monitoring_interval > 0 ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_monitoring" {
  count = var.create_postgres && var.postgres_monitoring_interval > 0 ? 1 : 0

  name_prefix        = "${var.name}-rds-mon-"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume[0].json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  count = var.create_postgres && var.postgres_monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.rds_monitoring[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_db_instance" "postgres" {
  count = var.create_postgres ? 1 : 0

  identifier     = "${var.name}-postgres"
  engine         = "postgres"
  engine_version = var.postgres_engine_version
  instance_class = var.postgres_instance_class

  allocated_storage     = var.postgres_allocated_storage
  max_allocated_storage = var.postgres_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.postgres_kms_key_arn

  db_name  = var.postgres_db_name
  username = var.postgres_username
  # The master password is generated and rotated by AWS Secrets Manager:
  # it never appears in the Terraform configuration or state.
  manage_master_user_password         = true
  iam_database_authentication_enabled = true

  parameter_group_name   = aws_db_parameter_group.postgres[0].name
  db_subnet_group_name   = aws_db_subnet_group.postgres[0].name
  vpc_security_group_ids = [aws_security_group.postgres[0].id]
  publicly_accessible    = false
  multi_az               = var.postgres_multi_az

  backup_retention_period         = var.postgres_backup_retention_period
  copy_tags_to_snapshot           = true
  deletion_protection             = var.postgres_deletion_protection
  skip_final_snapshot             = !var.postgres_deletion_protection
  final_snapshot_identifier       = var.postgres_deletion_protection ? "${var.name}-postgres-final" : null
  auto_minor_version_upgrade      = true
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  monitoring_interval = var.postgres_monitoring_interval
  monitoring_role_arn = var.postgres_monitoring_interval > 0 ? aws_iam_role.rds_monitoring[0].arn : null

  performance_insights_enabled    = var.postgres_performance_insights_enabled
  performance_insights_kms_key_id = var.postgres_performance_insights_enabled ? var.postgres_kms_key_arn : null

  tags = local.tags
}
