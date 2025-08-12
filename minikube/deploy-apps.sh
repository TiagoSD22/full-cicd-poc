#!/bin/bash

# Deploy applications to Minikube cluster

set -e

# ECR Repository Configuration
BACKEND_ECR_REPO="backend-api"
FRONTEND_ECR_REPO="frontend-app"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Deploying Backend and Frontend applications...${NC}"

# Switch to application cluster
kubectl config use-context application-cluster

# Check AWS CLI and credentials
echo -e "${YELLOW}🔧 Checking AWS credentials and setup...${NC}"
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI is not installed. Please install AWS CLI first.${NC}"
    echo "Visit: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}❌ AWS credentials not configured or invalid.${NC}"
    echo "Please run 'aws configure' or export AWS credentials:"
    echo "export AWS_ACCESS_KEY_ID=your-access-key"
    echo "export AWS_SECRET_ACCESS_KEY=your-secret-key"
    echo "export AWS_DEFAULT_REGION=your-region"
    exit 1
fi

# Get AWS account ID and region
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region || echo "us-west-2")
REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo -e "${YELLOW}📋 Using AWS ECR registry: $REGISTRY_URL${NC}"
echo -e "${YELLOW}📋 AWS Account ID: $AWS_ACCOUNT_ID${NC}"
echo -e "${YELLOW}📋 AWS Region: $AWS_REGION${NC}"
echo -e "${YELLOW}📋 Backend ECR Repository: $BACKEND_ECR_REPO${NC}"
echo -e "${YELLOW}📋 Frontend ECR Repository: $FRONTEND_ECR_REPO${NC}"

# Create ECR repositories if they don't exist
echo -e "${YELLOW}🏗️  Creating ECR repositories...${NC}"

# Create backend repository
if aws ecr describe-repositories --repository-names $BACKEND_ECR_REPO --region $AWS_REGION &>/dev/null; then
    echo -e "${GREEN}✅ ECR repository '$BACKEND_ECR_REPO' already exists${NC}"
else
    echo -e "${YELLOW}📦 Creating ECR repository '$BACKEND_ECR_REPO'...${NC}"
    if aws ecr create-repository --repository-name $BACKEND_ECR_REPO --region $AWS_REGION; then
        echo -e "${GREEN}✅ ECR repository '$BACKEND_ECR_REPO' created successfully${NC}"
    else
        echo -e "${RED}❌ Failed to create ECR repository '$BACKEND_ECR_REPO'${NC}"
        exit 1
    fi
fi

# Create frontend repository
if aws ecr describe-repositories --repository-names $FRONTEND_ECR_REPO --region $AWS_REGION &>/dev/null; then
    echo -e "${GREEN}✅ ECR repository '$FRONTEND_ECR_REPO' already exists${NC}"
else
    echo -e "${YELLOW}📦 Creating ECR repository '$FRONTEND_ECR_REPO'...${NC}"
    if aws ecr create-repository --repository-name $FRONTEND_ECR_REPO --region $AWS_REGION; then
        echo -e "${GREEN}✅ ECR repository '$FRONTEND_ECR_REPO' created successfully${NC}"
    else
        echo -e "${RED}❌ Failed to create ECR repository '$FRONTEND_ECR_REPO'${NC}"
        exit 1
    fi
fi

# Verify ECR repositories exist
echo -e "${YELLOW}🔍 Verifying ECR repositories...${NC}"
if aws ecr describe-repositories --repository-names $BACKEND_ECR_REPO --region $AWS_REGION &>/dev/null; then
    BACKEND_URI=$(aws ecr describe-repositories --repository-names $BACKEND_ECR_REPO --region $AWS_REGION --query 'repositories[0].repositoryUri' --output text)
    echo -e "${GREEN}✅ Backend repository exists: $BACKEND_URI${NC}"
else
    echo -e "${RED}❌ Backend repository '$BACKEND_ECR_REPO' not found${NC}"
    exit 1
fi

if aws ecr describe-repositories --repository-names $FRONTEND_ECR_REPO --region $AWS_REGION &>/dev/null; then
    FRONTEND_URI=$(aws ecr describe-repositories --repository-names $FRONTEND_ECR_REPO --region $AWS_REGION --query 'repositories[0].repositoryUri' --output text)
    echo -e "${GREEN}✅ Frontend repository exists: $FRONTEND_URI${NC}"
else
    echo -e "${RED}❌ Frontend repository '$FRONTEND_ECR_REPO' not found${NC}"
    exit 1
fi

# Login to ECR
echo -e "${YELLOW}🔐 Logging into AWS ECR...${NC}"
if aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $REGISTRY_URL; then
    echo -e "${GREEN}✅ Successfully logged into ECR${NC}"
else
    echo -e "${RED}❌ Failed to login to ECR${NC}"
    exit 1
fi

# Build and push backend image
echo -e "${YELLOW}🔨 Building and pushing backend Docker image...${NC}"
cd ../backend

echo -e "${BLUE}Building backend image...${NC}"
if docker build -t $BACKEND_ECR_REPO:latest .; then
    echo -e "${GREEN}✅ Backend image built successfully${NC}"
else
    echo -e "${RED}❌ Failed to build backend image${NC}"
    exit 1
fi

echo -e "${BLUE}Tagging and pushing backend image to ECR...${NC}"
docker tag $BACKEND_ECR_REPO:latest $BACKEND_URI:latest
if docker push $BACKEND_URI:latest; then
    echo -e "${GREEN}✅ Backend image pushed to ECR successfully${NC}"
else
    echo -e "${RED}❌ Failed to push backend image to ECR${NC}"
    exit 1
fi

# Build and push frontend image
echo -e "${YELLOW}🔨 Building and pushing frontend Docker image...${NC}"
cd ../frontend

echo -e "${BLUE}Building frontend image...${NC}"
if docker build -t $FRONTEND_ECR_REPO:latest .; then
    echo -e "${GREEN}✅ Frontend image built successfully${NC}"
else
    echo -e "${RED}❌ Failed to build frontend image${NC}"
    exit 1
fi

echo -e "${BLUE}Tagging and pushing frontend image to ECR...${NC}"
docker tag $FRONTEND_ECR_REPO:latest $FRONTEND_URI:latest
if docker push $FRONTEND_URI:latest; then
    echo -e "${GREEN}✅ Frontend image pushed to ECR successfully${NC}"
else
    echo -e "${RED}❌ Failed to push frontend image to ECR${NC}"
    exit 1
fi

cd ../minikube

# Create namespace and ECR secret for Kubernetes
echo -e "${YELLOW}🔐 Creating ECR secret for Kubernetes...${NC}"
kubectl create namespace applications --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret docker-registry ecr-secret \
    --docker-server=$REGISTRY_URL \
    --docker-username=AWS \
    --docker-password=$(aws ecr get-login-password --region $AWS_REGION) \
    --namespace=applications \
    --dry-run=client -o yaml | kubectl apply -f -

echo -e "${GREEN}✅ ECR secret created/updated successfully${NC}"

# Deploy backend application
echo -e "${YELLOW}📦 Deploying backend application...${NC}"
helm upgrade --install backend-api ../k8s/charts/backend \
    --namespace applications \
    --create-namespace \
    --set image.repository=$BACKEND_URI \
    --set image.tag=latest \
    --set image.pullPolicy=Always \
    --set imagePullSecrets[0].name=ecr-secret \
    --set ingress.enabled=true \
    --set ingress.hosts[0].host=api.local \
    --set ingress.hosts[0].paths[0].path="/" \
    --set ingress.hosts[0].paths[0].pathType=Prefix

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Backend application deployed successfully${NC}"
else
    echo -e "${RED}❌ Failed to deploy backend application${NC}"
    exit 1
fi

# Deploy frontend application
echo -e "${YELLOW}📦 Deploying frontend application...${NC}"
helm upgrade --install frontend-app ../k8s/charts/frontend \
    --namespace applications \
    --create-namespace \
    --set image.repository=$FRONTEND_URI \
    --set image.tag=latest \
    --set image.pullPolicy=Always \
    --set imagePullSecrets[0].name=ecr-secret \
    --set ingress.enabled=true \
    --set ingress.hosts[0].host=app.local \
    --set ingress.hosts[0].paths[0].path="/" \
    --set ingress.hosts[0].paths[0].pathType=Prefix \
    --set env[0].name=NEXT_PUBLIC_BACKEND_URL \
    --set env[0].value="http://api.local"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Frontend application deployed successfully${NC}"
else
    echo -e "${RED}❌ Failed to deploy frontend application${NC}"
    exit 1
fi

# Wait for deployments to be ready
echo -e "${YELLOW}⏳ Waiting for deployments to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/backend-api-backend -n applications 2>/dev/null || \
kubectl wait --for=condition=available --timeout=300s deployment/backend-api -n applications
kubectl wait --for=condition=available --timeout=300s deployment/frontend-app-frontend -n applications 2>/dev/null || \
kubectl wait --for=condition=available --timeout=300s deployment/frontend-app -n applications

# Show deployment status
echo -e "${BLUE}📊 Deployment Status:${NC}"
echo "===================="
kubectl get pods -n applications
echo ""
kubectl get services -n applications
echo ""
kubectl get ingress -n applications

echo -e "${GREEN}🎉 Applications deployed successfully!${NC}"
echo ""
echo -e "${BLUE}Access Information:${NC}"
echo "=================="
echo ""
echo "Add these entries to your /etc/hosts file (or C:\\Windows\\System32\\drivers\\etc\\hosts on Windows):"
CLUSTER_IP=$(minikube ip -p application-cluster)
echo "$CLUSTER_IP api.local"
echo "$CLUSTER_IP app.local"
echo ""
echo -e "${YELLOW}Application URLs:${NC}"
echo "  Frontend: http://app.local"
echo "  Backend API: http://api.local/api/hello"
echo "  Backend Health: http://api.local/health"
echo ""
echo -e "${BLUE}Testing the API:${NC}"
echo "curl http://api.local/api/hello"
echo ""
echo -e "${BLUE}ECR Repository Information:${NC}"
echo "  Backend Repository: $BACKEND_URI"
echo "  Frontend Repository: $FRONTEND_URI"
echo ""
echo -e "${GREEN}🎉 Deployment complete!${NC}"
