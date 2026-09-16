variable "region" {
  description = "AWS region to deploy the example into."
  type        = string
  default     = "eu-west-3"
}

variable "name" {
  description = "Name of the example cluster."
  type        = string
  default     = "eks-basic"
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed to reach the public Kubernetes API endpoint."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
