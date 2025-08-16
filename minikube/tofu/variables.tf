variable "ecr_registry_url" {
  description = "ECR registry URL"
  type        = string
}

variable "ecr_token" {
  description = "ECR authentication token"
  type        = string
  sensitive   = true
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}
