#!/bin/bash

# Deploy applications to Minikube cluster using single-node approach
# This script is useful if you want to avoid registry complexity

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Deploying Backend and Frontend applications (Single-node approach)...${NC}"

# Switch to application cluster
kubectl config use-context application-cluster

# Check if cluster is single-node or multi-node
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
if [ "$NODE_COUNT" -gt 1 ]; then
    echo -e "${YELLOW}⚠️  Multi-node cluster detected. Consider using deploy-apps.sh instead.${NC}"
    echo -e "${YELLOW}   This script will still work but uses docker-env which may have limitations.${NC}"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled. Use deploy-apps.sh for multi-node clusters."
        exit 0
    fi
fi

# Use Minikube docker-env for single-node clusters
echo -e "${YELLOW}🔧 Setting up Docker environment...${NC}"
eval $(minikube docker-env -p application-cluster)

# Build backend image
echo -e "${YELLOW}🔨 Building backend Docker image...${NC}"
cd ../backend
docker build -t backend-api:latest .

# Build frontend image  
echo -e "${YELLOW}🔨 Building frontend Docker image...${NC}"
cd ../frontend
docker build -t frontend-app:latest .

cd ../minikube

# Deploy backend application
echo -e "${YELLOW}📦 Deploying backend application...${NC}"
helm upgrade --install backend-api ../k8s/charts/backend \
    --namespace applications \
    --create-namespace \
    --set image.repository=backend-api \
    --set image.tag=latest \
    --set image.pullPolicy=Never \
    --set ingress.enabled=true \
    --set ingress.hosts[0].host=api.local \
    --set ingress.hosts[0].paths[0].path="/" \
    --set ingress.hosts[0].paths[0].pathType=Prefix

# Deploy frontend application
echo -e "${YELLOW}📦 Deploying frontend application...${NC}"
helm upgrade --install frontend-app ../k8s/charts/frontend \
    --namespace applications \
    --create-namespace \
    --set image.repository=frontend-app \
    --set image.tag=latest \
    --set image.pullPolicy=Never \
    --set ingress.enabled=true \
    --set ingress.hosts[0].host=app.local \
    --set ingress.hosts[0].paths[0].path="/" \
    --set ingress.hosts[0].paths[0].pathType=Prefix \
    --set env[0].name=NEXT_PUBLIC_BACKEND_URL \
    --set env[0].value="http://api.local"

# Wait for deployments to be ready
echo -e "${YELLOW}⏳ Waiting for deployments to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/backend-api-backend -n applications
kubectl wait --for=condition=available --timeout=300s deployment/frontend-app-frontend-app -n applications

# Get service URLs
APP_IP=$(minikube ip -p application-cluster)

echo -e "${GREEN}✅ Applications deployed successfully!${NC}"
echo ""
echo -e "${BLUE}Access Information:${NC}"
echo "=================="
echo ""
echo "Add these entries to your /etc/hosts file (or C:\\Windows\\System32\\drivers\\etc\\hosts on Windows):"
echo "${APP_IP} api.local"
echo "${APP_IP} app.local"
echo ""
echo -e "${YELLOW}Application URLs:${NC}"
echo "  Frontend: http://app.local"
echo "  Backend API: http://api.local/api/hello"
echo "  Backend Health: http://api.local/health"
echo ""
echo -e "${BLUE}Testing the API:${NC}"
echo "curl http://api.local/api/hello"
echo ""
echo -e "${GREEN}🎉 Applications are ready to use!${NC}"
