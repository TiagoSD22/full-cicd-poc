output "application_cluster_endpoint" {
  description = "Endpoint for EKS application cluster"
  value       = module.application_eks.cluster_endpoint
}

output "application_cluster_name" {
  description = "Application EKS cluster name"
  value       = module.application_eks.cluster_name
}

output "infra_cluster_endpoint" {
  description = "Endpoint for EKS infrastructure cluster"
  value       = module.infra_eks.cluster_endpoint
}

output "infra_cluster_name" {
  description = "Infrastructure EKS cluster name"
  value       = module.infra_eks.cluster_name
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = module.vpc.public_subnets
}

output "backend_ecr_repository_url" {
  description = "URL of the backend ECR repository"
  value       = aws_ecr_repository.backend.repository_url
}

output "frontend_ecr_repository_url" {
  description = "URL of the frontend ECR repository"
  value       = aws_ecr_repository.frontend.repository_url
}

output "load_balancer_dns" {
  description = "DNS name of the load balancer"
  value       = aws_lb.application.dns_name
}

output "load_balancer_zone_id" {
  description = "Zone ID of the load balancer"
  value       = aws_lb.application.zone_id
}

output "route53_zone_id" {
  description = "Route53 zone ID"
  value       = aws_route53_zone.main.zone_id
}

output "certificate_arn" {
  description = "ARN of the SSL certificate"
  value       = aws_acm_certificate_validation.main.certificate_arn
}
