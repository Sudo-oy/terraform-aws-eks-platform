output "cluster_name" {
  description = "Nom du cluster EKS"
  value       = module.eks.cluster_id
}

output "ecr_repository_url" {
  description = "URL complète du dépôt ECR (pour le pipeline CI/CD)"
  value       = aws_ecr_repository.app_repo.repository_url
}

output "db_endpoint" {
  description = "Endpoint de l'instance RDS PostgreSQL (C'est le DB_HOST)"
  value       = aws_db_instance.app_db.address
}
