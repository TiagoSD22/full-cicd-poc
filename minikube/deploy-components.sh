#!/bin/bash

# Deployment script for Infrastructure Kata components

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Deploying Infrastructure Kata components...${NC}"

# Function to wait for deployment to be ready
wait_for_deployment() {
    local namespace=$1
    local deployment=$2
    local timeout=${3:-300}
    
    echo -e "${YELLOW}⏳ Waiting for $deployment in $namespace to be ready...${NC}"
    kubectl wait --for=condition=available --timeout=${timeout}s deployment/$deployment -n $namespace
}

# Function to wait for pods to be ready
wait_for_pods() {
    local namespace=$1
    local label=$2
    local timeout=${3:-300}
    
    echo -e "${YELLOW}⏳ Waiting for pods with label $label in $namespace to be ready...${NC}"
    kubectl wait --for=condition=ready --timeout=${timeout}s pod -l $label -n $namespace
}

# Deploy to Infrastructure Cluster
echo -e "${BLUE}📦 Deploying to Infrastructure Cluster...${NC}"
kubectl config use-context infra-cluster

# Create namespaces
kubectl create namespace jenkins --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace opentofu --dry-run=client -o yaml | kubectl apply -f -

# Deploy Jenkins
echo -e "${YELLOW}🔧 Deploying Jenkins...${NC}"
helm repo add jenkins https://charts.jenkins.io
helm repo update

helm upgrade --install jenkins jenkins/jenkins \
    --namespace jenkins \
    --values - <<EOF
controller:
  admin:
    password: "admin123"
  serviceType: NodePort
  nodePort: 32000
  installPlugins:
    - kubernetes:4029.v5712230ccb_f8
    - workflow-aggregator:596.v8c21c963d92d
    - git:5.0.0
    - configuration-as-code:1670.v564dc8b_982d0
  additionalPlugins:
    - docker-workflow:563.vd5d2e5c4007f
    - pipeline-stage-view:2.34
    - blueocean:1.25.8
  JCasC:
    defaultConfig: true
    configScripts:
      welcome-message: |
        jenkins:
          systemMessage: Welcome to Infrastructure Kata Jenkins!
persistence:
  enabled: true
  size: 20Gi
EOF

# Deploy to Application Cluster
echo -e "${BLUE}📦 Deploying to Application Cluster...${NC}"
kubectl config use-context application-cluster

# Create namespaces
kubectl create namespace applications --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Deploy NGINX Ingress Controller
echo -e "${YELLOW}🔧 Deploying NGINX Ingress Controller...${NC}"

# Disable minikube ingress addon if enabled to avoid conflicts
echo -e "${YELLOW}🔧 Disabling minikube ingress addon to avoid conflicts...${NC}"
minikube addons disable ingress -p application-cluster || true

# Clean up any existing nginx ingressclass that might conflict
echo -e "${YELLOW}🧹 Cleaning up existing nginx IngressClass...${NC}"
kubectl delete ingressclass nginx --ignore-not-found=true

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install nginx-ingress ingress-nginx/ingress-nginx \
    --namespace ingress-nginx \
    --create-namespace \
    --set controller.service.type=NodePort \
    --set controller.service.nodePorts.http=30080 \
    --set controller.service.nodePorts.https=30443 \
    --set controller.ingressClassResource.name=nginx \
    --set controller.ingressClassResource.controllerValue="k8s.io/ingress-nginx" \
    --set controller.ingressClassResource.enabled=true \
    --set controller.ingressClassResource.default=true

# Deploy Prometheus and Grafana
echo -e "${YELLOW}📊 Deploying Prometheus and Grafana...${NC}"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --values - <<EOF
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    retention: 7d
  service:
    type: NodePort
    nodePort: 30090

grafana:
  adminPassword: "admin123"
  service:
    type: NodePort
    nodePort: 30030
  persistence:
    enabled: true
    size: 5Gi

alertmanager:
  service:
    type: NodePort
    nodePort: 30093
EOF

echo -e "${GREEN}✅ Deployments completed!${NC}"
echo ""
echo -e "${BLUE}Access Information:${NC}"
echo "=================="
echo ""

# Get Minikube IPs
INFRA_IP=$(minikube ip -p infra-cluster)
APP_IP=$(minikube ip -p application-cluster)

echo -e "${YELLOW}Infrastructure Cluster (${INFRA_IP}):${NC}"
echo "  Jenkins: http://${INFRA_IP}:32000"
echo "  Username: admin"
echo "  Password: admin123"
echo ""

echo -e "${YELLOW}Application Cluster (${APP_IP}):${NC}"
echo "  Grafana: http://${APP_IP}:30030"
echo "  Username: admin"
echo "  Password: admin123"
echo ""
echo "  Prometheus: http://${APP_IP}:30090"
echo "  AlertManager: http://${APP_IP}:30093"
echo ""

echo -e "${BLUE}Next Steps:${NC}"
echo "1. Configure Jenkins pipelines"
echo "2. Build and deploy applications"
echo "3. Setup Grafana dashboards"
echo "4. Configure monitoring alerts"

echo ""
echo -e "${GREEN}🎉 Infrastructure Kata setup complete!${NC}"
