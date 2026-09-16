################################################################################
# General
################################################################################

variable "name" {
  description = "Name of the EKS cluster. Also used as a prefix for every resource created by the module."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,37}$", var.name))
    error_message = "name must be 2-38 characters, start with a lowercase letter and contain only lowercase letters, digits and hyphens."
  }
}

variable "tags" {
  description = "Tags applied to every resource created by the module."
  type        = map(string)
  default     = {}
}

variable "log_retention_in_days" {
  description = "Retention (in days) of the CloudWatch log groups created for the control plane and VPC flow logs."
  type        = number
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days must be a retention period supported by CloudWatch Logs."
  }
}

################################################################################
# Networking
################################################################################

variable "create_vpc" {
  description = "Create a dedicated VPC. Set to false to deploy into an existing VPC (`vpc_id` and `private_subnet_ids` are then required)."
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block of the VPC created by the module (prefix between /16 and /20). Ignored when `create_vpc` is false."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) >= 16 && tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "vpc_cidr must be a valid IPv4 CIDR block with a prefix between /16 and /20."
  }
}

variable "az_count" {
  description = "Number of availability zones used by the VPC created by the module."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3 (EKS requires subnets in at least two availability zones)."
  }
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway instead of one per availability zone. Cheaper, but not highly available."
  type        = bool
  default     = true
}

variable "enable_vpc_flow_logs" {
  description = "Send VPC flow logs to CloudWatch Logs. Ignored when `create_vpc` is false."
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "ID of an existing VPC. Required when `create_vpc` is false."
  type        = string
  default     = null

  validation {
    condition     = var.create_vpc || var.vpc_id != null
    error_message = "vpc_id is required when create_vpc is false."
  }
}

variable "private_subnet_ids" {
  description = "IDs of existing private subnets (at least two AZs) for the control plane ENIs and the nodes. Required when `create_vpc` is false."
  type        = list(string)
  default     = []

  validation {
    condition     = var.create_vpc || length(var.private_subnet_ids) >= 2
    error_message = "At least two private_subnet_ids are required when create_vpc is false."
  }
}

variable "database_subnet_ids" {
  description = "IDs of existing subnets for the PostgreSQL subnet group. Required when `create_vpc` is false and `create_postgres` is true."
  type        = list(string)
  default     = []

  validation {
    condition     = var.create_vpc || !var.create_postgres || length(var.database_subnet_ids) >= 2
    error_message = "At least two database_subnet_ids are required when create_vpc is false and create_postgres is true."
  }
}

################################################################################
# EKS
################################################################################

variable "kubernetes_version" {
  description = "Kubernetes version of the EKS control plane (for example `1.34`)."
  type        = string
  default     = "1.34"

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.34."
  }
}

variable "endpoint_public_access" {
  description = "Expose the Kubernetes API server endpoint publicly. The private endpoint is always enabled."
  type        = bool
  default     = true
}

variable "endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public API endpoint. Restrict this to your office or VPN ranges in production."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for c in var.endpoint_public_access_cidrs : can(cidrhost(c, 0))])
    error_message = "endpoint_public_access_cidrs must only contain valid IPv4 CIDR blocks."
  }
}

variable "enable_cluster_creator_admin_permissions" {
  description = "Grant cluster-admin to the IAM identity that runs Terraform, through an EKS access entry."
  type        = bool
  default     = true
}

variable "access_entries" {
  description = "Additional EKS access entries, passed as-is to the `access_entries` input of terraform-aws-modules/eks."
  type        = any
  default     = {}
}

variable "cluster_enabled_log_types" {
  description = "Control plane log types sent to CloudWatch Logs."
  type        = list(string)
  default     = ["api", "audit", "authenticator"]

  validation {
    condition     = alltrue([for t in var.cluster_enabled_log_types : contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], t)])
    error_message = "cluster_enabled_log_types only accepts api, audit, authenticator, controllerManager and scheduler."
  }
}

variable "node_groups" {
  description = "EKS managed node groups, keyed by name. Every attribute is optional."
  type = map(object({
    ami_type       = optional(string, "AL2023_x86_64_STANDARD")
    instance_types = optional(list(string), ["t3.medium"])
    capacity_type  = optional(string, "ON_DEMAND")
    min_size       = optional(number, 1)
    max_size       = optional(number, 3)
    desired_size   = optional(number, 2)
    labels         = optional(map(string), {})
  }))
  default = {
    default = {}
  }

  validation {
    condition     = alltrue([for ng in values(var.node_groups) : contains(["ON_DEMAND", "SPOT"], ng.capacity_type)])
    error_message = "capacity_type must be ON_DEMAND or SPOT."
  }

  validation {
    condition     = alltrue([for ng in values(var.node_groups) : ng.min_size <= ng.desired_size && ng.desired_size <= ng.max_size])
    error_message = "Each node group must satisfy min_size <= desired_size <= max_size."
  }
}

################################################################################
# ECR
################################################################################

variable "ecr_repositories" {
  description = "Names of the ECR repositories to create. Empty list: no repository."
  type        = list(string)
  default     = []
}

variable "ecr_image_tag_mutability" {
  description = "Tag mutability of the ECR repositories."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.ecr_image_tag_mutability)
    error_message = "ecr_image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "ecr_kms_key_arn" {
  description = "ARN of a customer managed KMS key for ECR encryption. `null` uses the AWS managed key."
  type        = string
  default     = null
}

variable "ecr_max_image_count" {
  description = "Number of images kept per ECR repository. Older images are expired by a lifecycle policy."
  type        = number
  default     = 30
}

variable "ecr_force_delete" {
  description = "Allow Terraform to delete ECR repositories that still contain images."
  type        = bool
  default     = false
}

################################################################################
# PostgreSQL
################################################################################

variable "create_postgres" {
  description = "Create a private Amazon RDS for PostgreSQL instance reachable from the EKS nodes."
  type        = bool
  default     = false
}

variable "postgres_engine_version" {
  description = "PostgreSQL engine version (major, or major.minor)."
  type        = string
  default     = "17"
}

variable "postgres_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.small"
}

variable "postgres_allocated_storage" {
  description = "Initial storage (GiB)."
  type        = number
  default     = 20
}

variable "postgres_max_allocated_storage" {
  description = "Upper limit (GiB) for storage autoscaling. Set it equal to `postgres_allocated_storage` to disable autoscaling."
  type        = number
  default     = 100
}

variable "postgres_db_name" {
  description = "Name of the database created on the instance."
  type        = string
  default     = "app"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.postgres_db_name))
    error_message = "postgres_db_name must start with a letter and contain only letters, digits and underscores."
  }
}

variable "postgres_username" {
  description = "Master user name. The password is generated and stored in AWS Secrets Manager."
  type        = string
  default     = "app_admin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.postgres_username)) && !contains(["admin", "postgres", "rdsadmin"], lower(var.postgres_username))
    error_message = "postgres_username must be a valid identifier and cannot be a reserved name (admin, postgres, rdsadmin)."
  }
}

variable "postgres_multi_az" {
  description = "Deploy a standby replica in another availability zone."
  type        = bool
  default     = false
}

variable "postgres_backup_retention_period" {
  description = "Number of days automated backups are kept."
  type        = number
  default     = 7

  validation {
    condition     = var.postgres_backup_retention_period >= 1 && var.postgres_backup_retention_period <= 35
    error_message = "postgres_backup_retention_period must be between 1 and 35 days."
  }
}

variable "postgres_deletion_protection" {
  description = "Enable deletion protection and take a final snapshot on destroy. Disable it for ephemeral environments."
  type        = bool
  default     = true
}

variable "postgres_monitoring_interval" {
  description = "Enhanced Monitoring interval in seconds. 0 disables Enhanced Monitoring."
  type        = number
  default     = 60

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.postgres_monitoring_interval)
    error_message = "postgres_monitoring_interval must be one of 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "postgres_log_min_duration_ms" {
  description = "Log statements running longer than this many milliseconds (-1 disables slow query logging)."
  type        = number
  default     = 1000
}

variable "postgres_performance_insights_enabled" {
  description = "Enable Performance Insights (not supported on every instance class)."
  type        = bool
  default     = false
}

variable "postgres_kms_key_arn" {
  description = "ARN of a customer managed KMS key for storage and Performance Insights encryption. `null` uses the AWS managed key."
  type        = string
  default     = null
}
