variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "application_cluster_name" {
  description = "Name of the EKS cluster for applications"
  type        = string
  default     = "application-cluster"
}

variable "infra_cluster_name" {
  description = "Name of the EKS cluster for infrastructure"
  type        = string
  default     = "infra-cluster"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "backend_image_tag" {
  description = "Backend Docker image tag"
  type        = string
  default     = "latest"
}

variable "frontend_image_tag" {
  description = "Frontend Docker image tag"
  type        = string
  default     = "latest"
}

variable "docker_registry" {
  description = "Docker registry URL"
  type        = string
  default     = "your-registry.amazonaws.com"
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = "yourdomain.com"
}

variable "certificate_arn" {
  description = "SSL certificate ARN"
  type        = string
  default     = ""
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS nodes"
  type        = string
  default     = "t3.medium"
}

variable "desired_capacity" {
  description = "Desired number of nodes in the EKS cluster"
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum number of nodes in the EKS cluster"
  type        = number
  default     = 4
}

variable "min_capacity" {
  description = "Minimum number of nodes in the EKS cluster"
  type        = number
  default     = 1
}
