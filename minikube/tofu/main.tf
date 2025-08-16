terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
  required_version = ">= 1.0"
}

# Configure the Kubernetes Provider
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "application-cluster"
}

# Configure the Helm Provider
provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "application-cluster"
  }
}

# Create ArgoCD namespace
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      "app.kubernetes.io/name" = "argocd"
    }
  }
}

# Create applications namespace
resource "kubernetes_namespace" "applications" {
  metadata {
    name = "applications"
    labels = {
      "app.kubernetes.io/name" = "applications"
    }
  }
}

# Install ArgoCD using Helm
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "5.46.8"
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  values = [
    yamlencode({
      global = {
        domain = "argocd.local"
      }
      
      configs = {
        params = {
          "server.insecure" = true
        }
      }
      
      server = {
        service = {
          type = "NodePort"
          nodePortHttp = 30080
        }
        ingress = {
          enabled = true
          hosts = ["argocd.local"]
          annotations = {
            "kubernetes.io/ingress.class" = "nginx"
          }
        }
      }
      
      dex = {
        enabled = false
      }
    })
  ]

  depends_on = [kubernetes_namespace.argocd]
}

# Create ECR pull-through secret
resource "kubernetes_secret" "ecr_secret" {
  metadata {
    name      = "ecr-secret"
    namespace = kubernetes_namespace.applications.metadata[0].name
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "${var.ecr_registry_url}" = {
          username = "AWS"
          password = var.ecr_token
          auth     = base64encode("AWS:${var.ecr_token}")
        }
      }
    })
  }
}

# ArgoCD Project for our applications
resource "kubernetes_manifest" "argocd_project" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "infra-kata"
      namespace = kubernetes_namespace.argocd.metadata[0].name
    }
    spec = {
      description = "Infrastructure Kata Project"
      
      sourceRepos = ["*"]
      
      destinations = [
        {
          namespace = "*"
          server    = "https://kubernetes.default.svc"
        }
      ]
      
      clusterResourceWhitelist = [
        {
          group = "*"
          kind  = "*"
        }
      ]
      
      namespaceResourceWhitelist = [
        {
          group = "*"
          kind  = "*"
        }
      ]
    }
  }

  depends_on = [helm_release.argocd]
}

# ArgoCD Application for Backend
resource "kubernetes_manifest" "backend_application" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "backend-api"
      namespace = kubernetes_namespace.argocd.metadata[0].name
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "infra-kata"
      
      source = {
        repoURL        = "."
        targetRevision = "HEAD"
        path           = "k8s/charts/backend"
        helm = {
          valueFiles = ["values.yaml"]
          parameters = [
            {
              name  = "image.repository"
              value = "${var.ecr_registry_url}/backend-api"
            },
            {
              name  = "image.tag"
              value = "latest"
            },
            {
              name  = "image.pullPolicy"
              value = "Always"
            },
            {
              name  = "imagePullSecrets[0].name"
              value = "ecr-secret"
            },
            {
              name  = "ingress.enabled"
              value = "true"
            },
            {
              name  = "ingress.hosts[0].host"
              value = "api.local"
            },
            {
              name  = "ingress.hosts[0].paths[0].path"
              value = "/"
            },
            {
              name  = "ingress.hosts[0].paths[0].pathType"
              value = "Prefix"
            }
          ]
        }
      }
      
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = kubernetes_namespace.applications.metadata[0].name
      }
      
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true"
        ]
      }
    }
  }

  depends_on = [kubernetes_manifest.argocd_project, kubernetes_secret.ecr_secret]
}

# ArgoCD Application for Frontend
resource "kubernetes_manifest" "frontend_application" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "frontend-app"
      namespace = kubernetes_namespace.argocd.metadata[0].name
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "infra-kata"
      
      source = {
        repoURL        = "."
        targetRevision = "HEAD"
        path           = "k8s/charts/frontend"
        helm = {
          valueFiles = ["values.yaml"]
          parameters = [
            {
              name  = "image.repository"
              value = "${var.ecr_registry_url}/frontend-app"
            },
            {
              name  = "image.tag"
              value = "latest"
            },
            {
              name  = "image.pullPolicy"
              value = "Always"
            },
            {
              name  = "imagePullSecrets[0].name"
              value = "ecr-secret"
            },
            {
              name  = "ingress.enabled"
              value = "true"
            },
            {
              name  = "ingress.hosts[0].host"
              value = "app.local"
            },
            {
              name  = "ingress.hosts[0].paths[0].path"
              value = "/"
            },
            {
              name  = "ingress.hosts[0].paths[0].pathType"
              value = "Prefix"
            },
            {
              name  = "env[0].name"
              value = "NEXT_PUBLIC_BACKEND_URL"
            },
            {
              name  = "env[0].value"
              value = "http://api.local"
            }
          ]
        }
      }
      
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = kubernetes_namespace.applications.metadata[0].name
      }
      
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true"
        ]
      }
    }
  }

  depends_on = [kubernetes_manifest.argocd_project, kubernetes_secret.ecr_secret]
}
