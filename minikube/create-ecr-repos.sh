#!/bin/bash

# Script to manually create ECR repositories

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

echo -e "${BLUE}🏗️  Creating ECR repositories for Infrastructure Kata...${NC}"

# Check AWS CLI and credentials
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI is not installed. Please install AWS CLI first.${NC}"
    exit 1
fi

if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}❌ AWS credentials not configured or invalid.${NC}"
    echo "Please run 'aws configure' or export AWS credentials"
    exit 1
fi

# Get AWS account ID and region
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region || echo "us-west-2")

echo -e "${YELLOW}📋 AWS Account ID: $AWS_ACCOUNT_ID${NC}"
echo -e "${YELLOW}📋 AWS Region: $AWS_REGION${NC}"
echo ""

# Function to create repository
create_repository() {
    local repo_name=$1
    
    echo -e "${YELLOW}🔍 Checking if repository '$repo_name' exists...${NC}"
    
    if aws ecr describe-repositories --repository-names $repo_name --region $AWS_REGION &>/dev/null; then
        echo -e "${GREEN}✅ Repository '$repo_name' already exists${NC}"
        
        # Get repository URI
        REPO_URI=$(aws ecr describe-repositories --repository-names $repo_name --region $AWS_REGION --query 'repositories[0].repositoryUri' --output text)
        echo -e "${BLUE}   URI: $REPO_URI${NC}"
    else
        echo -e "${YELLOW}📦 Creating repository '$repo_name'...${NC}"
        
        if aws ecr create-repository --repository-name $repo_name --region $AWS_REGION; then
            echo -e "${GREEN}✅ Repository '$repo_name' created successfully${NC}"
            
            # Get repository URI
            REPO_URI=$(aws ecr describe-repositories --repository-names $repo_name --region $AWS_REGION --query 'repositories[0].repositoryUri' --output text)
            echo -e "${BLUE}   URI: $REPO_URI${NC}"
            
            # Enable scan on push (optional security feature)
            echo -e "${YELLOW}🔒 Enabling scan on push for repository '$repo_name'...${NC}"
            aws ecr put-image-scanning-configuration --repository-name $repo_name --image-scanning-configuration scanOnPush=true --region $AWS_REGION
            echo -e "${GREEN}✅ Scan on push enabled${NC}"
            
        else
            echo -e "${RED}❌ Failed to create repository '$repo_name'${NC}"
            return 1
        fi
    fi
    echo ""
}

# Create repositories
# Create repositories
create_repository "infra-kata-be-app"
create_repository "infra-kata-fe-app"

echo -e "${GREEN}🎉 ECR repository setup completed!${NC}"
echo ""
echo -e "${BLUE}📋 Next steps:${NC}"
echo "1. Run './deploy-apps.sh' to build and deploy applications"
echo "2. The script will automatically push images to these repositories"
echo ""
echo -e "${YELLOW}💡 Repository Information:${NC}"
echo "Registry URL: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
echo ""
echo -e "${YELLOW}🔐 To manually login to ECR:${NC}"
echo "aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
echo ""
echo -e "${YELLOW}📦 To manually push images:${NC}"
echo "docker tag $BACKEND_ECR_REPO:latest ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/$BACKEND_ECR_REPO:latest"
echo "docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/$BACKEND_ECR_REPO:latest"
