# Create namespaces
resource "kubernetes_namespace" "infrastructure" {
  metadata {
    name = var.infrastructure_namespace
    labels = {
      "managed-by" = "opentofu"
      "purpose"    = "infrastructure"
    }
  }
}

resource "kubernetes_namespace" "applications" {
  metadata {
    name = var.application_namespace
    labels = {
      "managed-by" = "opentofu"
      "purpose"    = "applications"
    }
  }
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.argocd_namespace
    labels = {
      "managed-by" = "opentofu"
      "purpose"    = "gitops"
    }
  }
}

# Create ECR pull-through secret
data "aws_caller_identity" "current" {}

locals {
  ecr_registry_url = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

# Get ECR authorization token
data "aws_ecr_authorization_token" "token" {}

resource "kubernetes_secret" "ecr_secret" {
  metadata {
    name      = "ecr-secret"
    namespace = var.application_namespace
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        (local.ecr_registry_url) = {
          "username" = "AWS"
          "password" = data.aws_ecr_authorization_token.token.password
          "auth"     = base64encode("AWS:${data.aws_ecr_authorization_token.token.password}")
        }
      }
    })
  }

  depends_on = [kubernetes_namespace.applications]
}

# Install NGINX Ingress Controller
resource "helm_release" "nginx_ingress" {
  name       = "nginx-ingress"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.8.3"
  namespace  = var.infrastructure_namespace
  create_namespace = false

  values = [
    yamlencode({
      controller = {
        service = {
          type = "NodePort"
          nodePorts = {
            http  = 30080
            https = 30443
          }
        }
        metrics = {
          enabled = true
        }
        config = {
          "use-forwarded-headers" = "true"
        }
        extraArgs = {
          "enable-ssl-passthrough" = true
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.infrastructure]
}

# Install ArgoCD
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_version
  namespace  = var.argocd_namespace
  create_namespace = false

  values = [
    yamlencode({
      global = {
        domain = "argocd.local"
      }
      
      configs = {
        secret = {
          argocdServerAdminPassword = var.argocd_admin_password
        }
        cm = {
          "url" = "https://argocd.local"
          "application.instanceLabelKey" = "argocd.argoproj.io/instance"
          "server.insecure" = "true"
          "oidc.config" = ""
        }
        params = {
          "server.insecure" = true
        }
      }
      
      server = {
        service = {
          type = "NodePort"
          nodePortHttp = 30081
          nodePortHttps = 30444
        }
        ingress = {
          enabled = true
          ingressClassName = "nginx"
          hosts = ["argocd.local"]
          annotations = {
            "nginx.ingress.kubernetes.io/ssl-redirect" = "false"
            "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP"
          }
        }
        extraArgs = ["--insecure"]
      }
      
      controller = {
        metrics = {
          enabled = true
        }
      }
      
      repoServer = {
        metrics = {
          enabled = true
        }
      }
      
      applicationSet = {
        enabled = true
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.argocd,
    helm_release.nginx_ingress
  ]
}

# Install ArgoCD Image Updater (optional)
resource "helm_release" "argocd_image_updater" {
  count = var.enable_image_updater ? 1 : 0

  name       = "argocd-image-updater"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-image-updater"
  version    = "0.9.1"
  namespace  = var.argocd_namespace
  create_namespace = false

  values = [
    yamlencode({
      config = {
        registries = [
          {
            name = "ecr"
            api_url = "https://${local.ecr_registry_url}"
            prefix = local.ecr_registry_url
            ping = false
            credentials = "ext:/scripts/auth.sh"
            credsexpiry = "10m"
          }
        ]
      }
      
      authScripts = {
        enabled = true
        scripts = {
          "auth.sh" = <<-EOF
            #!/bin/sh
            aws ecr get-login-password --region ${var.aws_region}
          EOF
        }
      }
    })
  ]

  depends_on = [helm_release.argocd]
}

# Install Trivy Operator for vulnerability scanning
resource "helm_release" "trivy_operator" {
  count = var.trivy_enabled ? 1 : 0

  name       = "trivy-operator"
  repository = "https://aquasecurity.github.io/helm-charts"
  chart      = "trivy-operator"
  version    = "0.18.4"
  namespace  = var.infrastructure_namespace
  create_namespace = false

  values = [
    yamlencode({
      operator = {
        scannerReportTTL = "24h"
        configAuditScannerEnabled = true
        vulnerabilityScannerEnabled = true
        sbomGenerationEnabled = true
      }
      
      trivyOperator = {
        scanJob = {
          tolerations = []
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.infrastructure]
}
