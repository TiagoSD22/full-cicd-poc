terraform {
  required_version = ">= 1.0"
  
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure Kubernetes provider to use Minikube
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "application-cluster"
}

# Configure Helm provider to use Minikube
provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "application-cluster"
  }
}

# AWS provider for ECR operations
provider "aws" {
  region = var.aws_region
}
