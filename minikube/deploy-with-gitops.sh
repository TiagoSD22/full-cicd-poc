#!/bin/bash

# Deploy applications using OpenTofu and ArgoCD GitOps

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Deploying applications using OpenTofu + ArgoCD GitOps...${NC}"

# ECR Repository Configuration
BACKEND_ECR_REPO="backend-api"
FRONTEND_ECR_REPO="frontend-app"

# Switch to application cluster
kubectl config use-context application-cluster

# Check dependencies
echo -e "${YELLOW}🔧 Checking dependencies...${NC}"

# Check OpenTofu
if ! command -v tofu &> /dev/null; then
    echo -e "${RED}❌ OpenTofu is not installed. Installing...${NC}"
    # Install OpenTofu
    curl -L https://github.com/opentofu/opentofu/releases/latest/download/tofu_$(uname -s | tr '[:upper:]' '[:lower:]')_amd64.zip -o tofu.zip
    unzip tofu.zip
    sudo mv tofu /usr/local/bin/
    rm tofu.zip
    echo -e "${GREEN}✅ OpenTofu installed successfully${NC}"
fi

# Check AWS CLI and credentials
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI is not installed. Please install AWS CLI first.${NC}"
    exit 1
fi

if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}❌ AWS credentials not configured or invalid.${NC}"
    exit 1
fi

# Check ArgoCD CLI
if ! command -v argocd &> /dev/null; then
    echo -e "${YELLOW}📦 Installing ArgoCD CLI...${NC}"
    curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    chmod +x argocd
    sudo mv argocd /usr/local/bin/
    echo -e "${GREEN}✅ ArgoCD CLI installed successfully${NC}"
fi

# Get AWS account details
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region || echo "us-east-1")
REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo -e "${YELLOW}� Using AWS ECR registry: $REGISTRY_URL${NC}"

# Create ECR repositories if they don't exist
echo -e "${YELLOW}🏗️  Creating ECR repositories...${NC}"

for repo in $BACKEND_ECR_REPO $FRONTEND_ECR_REPO; do
    if aws ecr describe-repositories --repository-names $repo --region $AWS_REGION &>/dev/null; then
        echo -e "${GREEN}✅ ECR repository '$repo' already exists${NC}"
    else
        echo -e "${YELLOW}📦 Creating ECR repository '$repo'...${NC}"
        aws ecr create-repository --repository-name $repo --region $AWS_REGION
        echo -e "${GREEN}✅ ECR repository '$repo' created successfully${NC}"
    fi
done

# Login to ECR
echo -e "${YELLOW}🔐 Logging into AWS ECR...${NC}"
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $REGISTRY_URL

# Build and push images
echo -e "${YELLOW}🔨 Building and pushing Docker images...${NC}"

# Build backend
cd ../backend
echo -e "${BLUE}Building backend image...${NC}"
docker build -t $BACKEND_ECR_REPO:latest .
docker tag $BACKEND_ECR_REPO:latest $REGISTRY_URL/$BACKEND_ECR_REPO:latest
docker push $REGISTRY_URL/$BACKEND_ECR_REPO:latest
echo -e "${GREEN}✅ Backend image pushed to ECR${NC}"

# Build frontend
cd ../frontend
echo -e "${BLUE}Building frontend image...${NC}"
docker build -t $FRONTEND_ECR_REPO:latest .
docker tag $FRONTEND_ECR_REPO:latest $REGISTRY_URL/$FRONTEND_ECR_REPO:latest
docker push $REGISTRY_URL/$FRONTEND_ECR_REPO:latest
echo -e "${GREEN}✅ Frontend image pushed to ECR${NC}"

cd ../minikube/tofu

# Get ECR token for Kubernetes secret
ECR_TOKEN=$(aws ecr get-login-password --region $AWS_REGION)

# Initialize OpenTofu
echo -e "${YELLOW}🏗️  Initializing OpenTofu...${NC}"
tofu init

# Plan the deployment
echo -e "${YELLOW}📋 Planning OpenTofu deployment...${NC}"
tofu plan \
    -var="ecr_registry_url=$REGISTRY_URL" \
    -var="ecr_token=$ECR_TOKEN" \
    -var="aws_region=$AWS_REGION" \
    -var="aws_account_id=$AWS_ACCOUNT_ID"

# Apply the deployment
echo -e "${YELLOW}🚀 Applying OpenTofu deployment...${NC}"
tofu apply -auto-approve \
    -var="ecr_registry_url=$REGISTRY_URL" \
    -var="ecr_token=$ECR_TOKEN" \
    -var="aws_region=$AWS_REGION" \
    -var="aws_account_id=$AWS_ACCOUNT_ID"

# Wait for ArgoCD to be ready
echo -e "${YELLOW}⏳ Waiting for ArgoCD to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
kubectl wait --for=condition=available --timeout=300s deployment/argocd-application-controller -n argocd

# Get ArgoCD admin password
echo -e "${YELLOW}🔑 Getting ArgoCD admin password...${NC}"
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Port forward ArgoCD server (in background)
echo -e "${YELLOW}🌐 Setting up ArgoCD port forwarding...${NC}"
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
PORTFORWARD_PID=$!

# Wait a moment for port forward to establish
sleep 5

# Login to ArgoCD CLI
echo -e "${YELLOW}🔐 Logging into ArgoCD CLI...${NC}"
argocd login localhost:8080 --username admin --password $ARGOCD_PASSWORD --insecure

# Sync applications
echo -e "${YELLOW}🔄 Syncing ArgoCD applications...${NC}"
argocd app sync backend-api
argocd app sync frontend-app

# Wait for applications to be healthy
echo -e "${YELLOW}⏳ Waiting for applications to be healthy...${NC}"
argocd app wait backend-api --health
argocd app wait frontend-app --health

# Kill port forward
kill $PORTFORWARD_PID 2>/dev/null || true

# Show deployment status
echo -e "${BLUE}📊 Deployment Status:${NC}"
echo "===================="
kubectl get applications -n argocd
echo ""
kubectl get pods -n applications
echo ""
kubectl get services -n applications
echo ""
kubectl get ingress -n applications

echo -e "${GREEN}🎉 GitOps deployment completed successfully!${NC}"
echo ""
echo -e "${BLUE}Access Information:${NC}"
echo "=================="
echo ""
CLUSTER_IP=$(minikube ip -p application-cluster)
echo "Add these entries to your /etc/hosts file:"
echo "$CLUSTER_IP app.local"
echo "$CLUSTER_IP api.local"
echo "$CLUSTER_IP argocd.local"
echo ""
echo -e "${YELLOW}Application URLs:${NC}"
echo "  Frontend: http://app.local"
echo "  Backend API: http://api.local/api/hello"
echo "  ArgoCD UI: http://argocd.local"
echo ""
echo -e "${YELLOW}ArgoCD Credentials:${NC}"
echo "  Username: admin"
echo "  Password: $ARGOCD_PASSWORD"
echo ""
echo -e "${BLUE}Testing the API:${NC}"
echo "curl http://api.local/api/hello"
echo ""
echo -e "${GREEN}🎉 GitOps deployment complete!${NC}"

