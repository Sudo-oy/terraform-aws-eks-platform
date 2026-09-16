output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "kubeconfig_command" {
  description = "Command that configures kubectl for the cluster."
  value       = "${module.eks.kubeconfig_command} --region ${var.region}"
}

output "ecr_repository_urls" {
  description = "ECR repository URLs."
  value       = module.eks.ecr_repository_urls
}

output "postgres_endpoint" {
  description = "PostgreSQL hostname."
  value       = module.eks.postgres_endpoint
}

output "postgres_master_user_secret_arn" {
  description = "Secrets Manager secret holding the PostgreSQL master credentials."
  value       = module.eks.postgres_master_user_secret_arn
}
