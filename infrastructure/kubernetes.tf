# NGINX Ingress Controller
resource "helm_release" "nginx_ingress" {
  name       = "nginx-ingress"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.7.1"
  namespace  = "ingress-nginx"
  create_namespace = true

  values = [
    yamlencode({
      controller = {
        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
            "service.beta.kubernetes.io/aws-load-balancer-ssl-cert" = var.certificate_arn
            "service.beta.kubernetes.io/aws-load-balancer-ssl-ports" = "https"
            "service.beta.kubernetes.io/aws-load-balancer-backend-protocol" = "http"
          }
        }
        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = true
          }
        }
        config = {
          "use-forwarded-headers" = "true"
        }
      }
    })
  ]
}

# Cert-Manager for SSL certificates
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.13.0"
  namespace  = "cert-manager"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [helm_release.nginx_ingress]
}

# ClusterIssuer for Let's Encrypt
resource "kubernetes_manifest" "letsencrypt_prod" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = "admin@${var.domain_name}"
        privateKeySecretRef = {
          name = "letsencrypt-prod"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = "nginx"
              }
            }
          }
        ]
      }
    }
  }

  depends_on = [helm_release.cert_manager]
}

# Backend application deployment
resource "helm_release" "backend_app" {
  name      = "backend-api"
  chart     = "../k8s/charts/backend"
  namespace = "applications"
  create_namespace = true

  values = [
    yamlencode({
      image = {
        repository = aws_ecr_repository.backend.repository_url
        tag        = var.backend_image_tag
      }
      ingress = {
        hosts = [
          {
            host = "api.${var.domain_name}"
            paths = [
              {
                path     = "/(.*)"
                pathType = "Prefix"
              }
            ]
          }
        ]
        tls = [
          {
            secretName = "backend-tls"
            hosts      = ["api.${var.domain_name}"]
          }
        ]
      }
    })
  ]

  depends_on = [
    helm_release.nginx_ingress,
    helm_release.cert_manager
  ]
}

# Frontend application deployment
resource "helm_release" "frontend_app" {
  name      = "frontend-app"
  chart     = "../k8s/charts/frontend"
  namespace = "applications"
  create_namespace = true

  values = [
    yamlencode({
      image = {
        repository = aws_ecr_repository.frontend.repository_url
        tag        = var.frontend_image_tag
      }
      env = [
        {
          name  = "NEXT_PUBLIC_BACKEND_URL"
          value = "https://api.${var.domain_name}"
        }
      ]
      ingress = {
        hosts = [
          {
            host = var.domain_name
            paths = [
              {
                path     = "/(.*)"
                pathType = "Prefix"
              }
            ]
          }
        ]
        tls = [
          {
            secretName = "frontend-tls"
            hosts      = [var.domain_name]
          }
        ]
      }
    })
  ]

  depends_on = [
    helm_release.nginx_ingress,
    helm_release.cert_manager
  ]
}
