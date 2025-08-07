# Deploy Prometheus and Grafana using kube-prometheus-stack
resource "helm_release" "kube_prometheus_stack" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "51.0.0"
  namespace  = "monitoring"
  create_namespace = true

  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = {
          serviceMonitorSelectorNilUsesHelmValues = false
          podMonitorSelectorNilUsesHelmValues     = false
          retention = "30d"
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp2"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "50Gi"
                  }
                }
              }
            }
          }
        }
        ingress = {
          enabled = true
          ingressClassName = "nginx"
          annotations = {
            "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
          }
          hosts = ["prometheus.${var.domain_name}"]
          tls = [
            {
              secretName = "prometheus-tls"
              hosts      = ["prometheus.${var.domain_name}"]
            }
          ]
        }
      }
      
      grafana = {
        enabled = true
        adminPassword = "admin123"  # Change this in production
        persistence = {
          enabled = true
          size    = "10Gi"
          storageClassName = "gp2"
        }
        ingress = {
          enabled = true
          ingressClassName = "nginx"
          annotations = {
            "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
          }
          hosts = ["grafana.${var.domain_name}"]
          tls = [
            {
              secretName = "grafana-tls"
              hosts      = ["grafana.${var.domain_name}"]
            }
          ]
        }
        dashboardProviders = {
          "dashboardproviders.yaml" = {
            apiVersion = 1
            providers = [
              {
                name    = "default"
                orgId   = 1
                folder  = ""
                type    = "file"
                disableDeletion = false
                editable = true
                options = {
                  path = "/var/lib/grafana/dashboards/default"
                }
              }
            ]
          }
        }
        dashboards = {
          default = {
            "kubernetes-cluster-monitoring" = {
              gnetId = 315
              revision = 3
              datasource = "Prometheus"
            }
            "node-exporter" = {
              gnetId = 1860
              revision = 31
              datasource = "Prometheus"
            }
            "kubernetes-deployment-statefulset-daemonset-metrics" = {
              gnetId = 8588
              revision = 1
              datasource = "Prometheus"
            }
          }
        }
      }
      
      alertmanager = {
        enabled = true
        alertmanagerSpec = {
          storage = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp2"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "10Gi"
                  }
                }
              }
            }
          }
        }
        ingress = {
          enabled = true
          ingressClassName = "nginx"
          annotations = {
            "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
          }
          hosts = ["alertmanager.${var.domain_name}"]
          tls = [
            {
              secretName = "alertmanager-tls"
              hosts      = ["alertmanager.${var.domain_name}"]
            }
          ]
        }
      }
    })
  ]

  depends_on = [
    helm_release.nginx_ingress,
    helm_release.cert_manager
  ]
}
