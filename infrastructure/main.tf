terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    bucket = "your-terraform-state-bucket"
    key    = "infra-kata/terraform.tfstate"
    region = "us-west-2"
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_eks_cluster" "application_cluster" {
  name = var.application_cluster_name
}

data "aws_eks_cluster_auth" "application_cluster" {
  name = var.application_cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.application_cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.application_cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.application_cluster.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.application_cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.application_cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.application_cluster.token
  }
}
