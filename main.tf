terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# --- 1. AWS PROVIDER ---
provider "aws" {
  region = var.aws_region
}

# --- 2. VPC (Réseau) ---
# Utilisation du module VPC officiel pour la simplicité et les bonnes pratiques
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  # Zones de disponibilité pour la haute dispo
  azs             = ["${var.aws_region}a", "${var.aws_region}b"] 
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24"]
  database_subnets = ["10.0.21.0/24", "10.0.22.0/24"] # Subnets dédiés pour RDS (privés)

  enable_nat_gateway     = true
  single_nat_gateway     = true
  enable_database_nat_gateway = false
}

# --- 3. EKS Cluster ---
module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "19.15.0"
  cluster_name    = var.cluster_name
  cluster_version = "1.27"
  
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets # Les Worker Nodes s'exécutent dans les subnets privés
  cluster_endpoint_public_access = true

  eks_managed_node_groups = {
    default = {
      min_size     = 1
      max_size     = 2
      desired_size = 1
      instance_types = ["t3.medium"]
      subnet_ids     = module.vpc.private_subnets
    }
  }
}

# --- 4. ECR Repository (Registre Docker) ---
resource "aws_ecr_repository" "app_repo" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# --- 5. AWS RDS (PostgreSQL) et Security Group ---

# Security Group : Autorise le trafic entrant sur 5432 (PostgreSQL) depuis les Worker Nodes EKS
resource "aws_security_group" "rds_sg" {
  name        = "${var.cluster_name}-rds-sg"
  description = "Allow inbound traffic from EKS nodes for PostgreSQL"
  vpc_id      = module.vpc.vpc_id

  # Règle d'entrée (Ingress)
  ingress {
    description     = "PostgreSQL access from EKS Nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    # Source : On autorise uniquement les Worker Nodes EKS à se connecter
    security_groups = [module.eks.node_security_group_id] 
  }
  
  # Règle de sortie (Egress)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Instance RDS PostgreSQL
resource "aws_db_instance" "app_db" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "postgres"
  engine_version       = "15.4" 
  instance_class       = "db.t3.micro"
  db_name              = var.db_name
  username             = var.db_user
  password             = var.db_password
  skip_final_snapshot  = true
  publicly_accessible  = false # Crucial : La DB doit rester privée
  
  # Association des Security Groups et Subnet Group
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = module.vpc.database_subnet_group_name 
}
