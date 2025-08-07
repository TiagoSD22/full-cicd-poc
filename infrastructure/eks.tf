# Application EKS Cluster
module "application_eks" {
  source = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.application_cluster_name
  cluster_version = "1.28"

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  # EKS Managed Node Groups
  eks_managed_node_groups = {
    application_nodes = {
      name = "application-nodes"

      instance_types = [var.node_instance_type]
      
      min_size     = var.min_capacity
      max_size     = var.max_capacity
      desired_size = var.desired_capacity

      disk_size = 50
      
      labels = {
        Environment = var.environment
        NodeGroup   = "application"
      }

      taints = []

      tags = {
        Environment = var.environment
        NodeGroup   = "application"
      }
    }
  }

  # aws-auth configmap
  manage_aws_auth_configmap = true

  aws_auth_roles = [
    {
      rolearn  = aws_iam_role.eks_node_group.arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups   = ["system:bootstrappers", "system:nodes"]
    },
  ]

  tags = {
    Environment = var.environment
    Cluster     = "application"
  }
}

# Infrastructure EKS Cluster (for Jenkins and OpenTofu)
module "infra_eks" {
  source = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.infra_cluster_name
  cluster_version = "1.28"

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  # EKS Managed Node Groups
  eks_managed_node_groups = {
    infra_nodes = {
      name = "infra-nodes"

      instance_types = ["t3.large"] # Larger instances for Jenkins and OpenTofu
      
      min_size     = 1
      max_size     = 3
      desired_size = 2

      disk_size = 100 # More storage for build artifacts
      
      labels = {
        Environment = var.environment
        NodeGroup   = "infrastructure"
      }

      taints = []

      tags = {
        Environment = var.environment
        NodeGroup   = "infrastructure"
      }
    }
  }

  # aws-auth configmap
  manage_aws_auth_configmap = true

  aws_auth_roles = [
    {
      rolearn  = aws_iam_role.eks_node_group.arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups   = ["system:bootstrappers", "system:nodes"]
    },
  ]

  tags = {
    Environment = var.environment
    Cluster     = "infrastructure"
  }
}

# IAM Role for EKS Node Groups
resource "aws_iam_role" "eks_node_group" {
  name = "${var.environment}-eks-node-group-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group.name
}
