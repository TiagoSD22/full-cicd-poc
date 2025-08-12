#!/bin/bash

# Cleanup script to resolve NGINX Ingress Controller conflicts

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧹 NGINX Ingress Controller Cleanup Script${NC}"
echo -e "${YELLOW}This script resolves conflicts with existing ingress resources${NC}"
echo ""

# Switch to application cluster
kubectl config use-context application-cluster

echo -e "${YELLOW}📋 Checking current ingress resources...${NC}"

# Check for existing IngressClass resources
echo "Current IngressClass resources:"
kubectl get ingressclass 2>/dev/null || echo "No IngressClass resources found"
echo ""

# Check for existing ingress controllers
echo "Current ingress controller pods:"
kubectl get pods -A | grep ingress || echo "No ingress controller pods found"
echo ""

# Ask user for confirmation
read -p "Do you want to proceed with cleanup? This will remove existing ingress resources. (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo -e "${YELLOW}🔧 Starting cleanup process...${NC}"

# 1. Disable minikube ingress addon
echo -e "${YELLOW}Step 1: Disabling minikube ingress addon...${NC}"
minikube addons disable ingress -p application-cluster || true

# 2. Remove existing NGINX Ingress Controller Helm release
echo -e "${YELLOW}Step 2: Removing existing NGINX Ingress Controller Helm release...${NC}"
helm uninstall nginx-ingress -n ingress-nginx || true

# 3. Delete the ingress-nginx namespace
echo -e "${YELLOW}Step 3: Deleting ingress-nginx namespace...${NC}"
kubectl delete namespace ingress-nginx --ignore-not-found=true

# 4. Clean up any remaining IngressClass resources
echo -e "${YELLOW}Step 4: Cleaning up IngressClass resources...${NC}"
kubectl delete ingressclass nginx --ignore-not-found=true
kubectl delete ingressclass nginx-example --ignore-not-found=true

# 5. Wait for cleanup to complete
echo -e "${YELLOW}Step 5: Waiting for cleanup to complete...${NC}"
sleep 10

# 6. Verify cleanup
echo -e "${YELLOW}📋 Verifying cleanup...${NC}"
echo "Remaining IngressClass resources:"
kubectl get ingressclass 2>/dev/null || echo "No IngressClass resources found ✅"
echo ""

echo "Remaining ingress controller pods:"
kubectl get pods -A | grep ingress || echo "No ingress controller pods found ✅"
echo ""

echo -e "${GREEN}✅ Cleanup completed!${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Run the deploy-components.sh script to reinstall NGINX Ingress Controller"
echo "2. Or manually install with:"
echo ""
echo "   helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx"
echo "   helm repo update"
echo "   helm install nginx-ingress ingress-nginx/ingress-nginx \\"
echo "       --namespace ingress-nginx \\"
echo "       --create-namespace \\"
echo "       --set controller.service.type=NodePort \\"
echo "       --set controller.service.nodePorts.http=30080 \\"
echo "       --set controller.service.nodePorts.https=30443"
echo ""
echo -e "${GREEN}🎉 Ready for fresh NGINX Ingress Controller installation!${NC}"
