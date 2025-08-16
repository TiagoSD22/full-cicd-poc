output "argocd_server_url" {
  description = "ArgoCD server URL"
  value       = "http://argocd.local"
}

output "argocd_admin_password" {
  description = "ArgoCD admin password (use 'admin' with default)"
  value       = "admin"
  sensitive   = false
}

output "ecr_registry_url" {
  description = "ECR registry URL"
  value       = local.ecr_registry_url
}

output "backend_image_uri" {
  description = "Backend ECR image URI"
  value       = "${local.ecr_registry_url}/${var.backend_ecr_repo}:latest"
}

output "frontend_image_uri" {
  description = "Frontend ECR image URI"
  value       = "${local.ecr_registry_url}/${var.frontend_ecr_repo}:latest"
}

output "nginx_ingress_external_ip" {
  description = "NGINX Ingress external access information"
  value       = "Use 'minikube ip -p application-cluster' and NodePort 30080/30443"
}

output "cluster_info" {
  description = "Cluster access information"
  value = {
    context = "application-cluster"
    namespaces = {
      argocd = var.argocd_namespace
      applications = var.application_namespace
      infrastructure = var.infrastructure_namespace
    }
  }
}
