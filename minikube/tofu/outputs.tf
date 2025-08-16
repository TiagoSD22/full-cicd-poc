output "argocd_server_url" {
  description = "ArgoCD server URL"
  value       = "http://argocd.local"
}

output "argocd_admin_password_command" {
  description = "Command to get ArgoCD admin password"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "application_urls" {
  description = "Application URLs"
  value = {
    frontend = "http://app.local"
    backend  = "http://api.local"
  }
}

output "minikube_ip" {
  description = "Minikube cluster IP for /etc/hosts"
  value       = "Run: minikube ip -p application-cluster"
}
