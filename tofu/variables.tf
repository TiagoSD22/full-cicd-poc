variable "aws_region" {
  description = "AWS region for ECR repositories"
  type        = string
  default     = "us-west-2"
}

variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "backend_ecr_repo" {
  description = "Backend ECR repository name"
  type        = string
  default     = "backend-api"
}

variable "frontend_ecr_repo" {
  description = "Frontend ECR repository name"
  type        = string
  default     = "frontend-app"
}

variable "argocd_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "5.51.6"
}

variable "argocd_namespace" {
  description = "Namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "application_namespace" {
  description = "Namespace for applications"
  type        = string
  default     = "applications"
}

variable "infrastructure_namespace" {
  description = "Namespace for infrastructure components"
  type        = string
  default     = "infrastructure"
}

variable "argocd_admin_password" {
  description = "ArgoCD admin password (bcrypt hashed)"
  type        = string
  sensitive   = true
  default     = "$2a$10$rRyBsGSHK6.uc8fntPwVIuLVHgsAhAX7TcdrqW/RADU9TpY4.BN." # admin
}

variable "git_repo_url" {
  description = "Git repository URL for ArgoCD applications"
  type        = string
  default     = "https://github.com/TiagoSD22/full-cicd-poc.git"
}

variable "git_target_revision" {
  description = "Git target revision (branch/tag/commit)"
  type        = string
  default     = "main"
}

variable "enable_image_updater" {
  description = "Enable ArgoCD Image Updater"
  type        = bool
  default     = true
}

variable "trivy_enabled" {
  description = "Enable Trivy security scanner"
  type        = bool
  default     = true
}
