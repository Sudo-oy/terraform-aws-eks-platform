variable "aws_region" {
  description = "Région AWS pour le déploiement"
  type        = string
  default     = "eu-west-3" 

variable "cluster_name" {
  description = "Nom du cluster EKS"
  type        = string
  default     = "omar-devops-cluster"
}

variable "ecr_repo_name" {
  description = "Nom du dépôt ECR"
  type        = string
  default     = "devops-data-pipeline-app"
}

# Variables pour la Base de Données RDS
variable "db_name" {
  description = "Nom de la base de données PostgreSQL"
  type        = string
  default     = "mydb"
}
variable "db_user" {
  description = "Nom d'utilisateur de la base de données (maître)"
  type        = string
  default     = "admin"
}
variable "db_password" {
  description = "Mot de passe de la base de données (maître)"
  type        = string
  default     = null # **CHANGEZ CE MOT DE PASSE EN PROD**
  sensitive   = true # Marqué comme sensible pour ne pas s'afficher dans les logs
}
