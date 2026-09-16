################################################################################
# Cluster
################################################################################

output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = module.eks.cluster_arn
}

output "cluster_endpoint" {
  description = "Endpoint of the Kubernetes API server."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate data required to communicate with the cluster."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_oidc_issuer_url" {
  description = "OpenID Connect issuer URL of the cluster."
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider (for IRSA)."
  value       = module.eks.oidc_provider_arn
}

output "cluster_security_group_id" {
  description = "ID of the cluster security group."
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "ID of the node shared security group."
  value       = module.eks.node_security_group_id
}

output "kubeconfig_command" {
  description = "AWS CLI command that writes a kubeconfig entry for the cluster."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name}"
}

################################################################################
# Networking
################################################################################

output "vpc_id" {
  description = "ID of the VPC hosting the cluster."
  value       = local.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets used by the cluster."
  value       = local.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (empty when `create_vpc` is false)."
  value       = var.create_vpc ? module.vpc[0].public_subnets : []
}

################################################################################
# ECR
################################################################################

output "ecr_repository_urls" {
  description = "Map of ECR repository name to repository URL."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

################################################################################
# PostgreSQL
################################################################################

output "postgres_endpoint" {
  description = "Hostname of the PostgreSQL instance (null when `create_postgres` is false)."
  value       = try(aws_db_instance.postgres[0].address, null)
}

output "postgres_port" {
  description = "Port of the PostgreSQL instance (null when `create_postgres` is false)."
  value       = try(aws_db_instance.postgres[0].port, null)
}

output "postgres_master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the master credentials (null when `create_postgres` is false)."
  value       = try(aws_db_instance.postgres[0].master_user_secret[0].secret_arn, null)
}
