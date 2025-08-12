#!/bin/bash

# Test script to verify Jenkins deployment after the fix

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧪 Testing Jenkins deployment after configuration fix...${NC}"

# Switch to infra cluster
kubectl config use-context infra-cluster

# Check if Jenkins deployment exists
echo -e "${YELLOW}📊 Checking Jenkins deployment status...${NC}"
if kubectl get deployment jenkins -n jenkins >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Jenkins deployment found${NC}"
    
    # Check deployment status
    kubectl get deployment jenkins -n jenkins
    
    # Check pod status
    echo -e "${YELLOW}📋 Jenkins pod status:${NC}"
    kubectl get pods -n jenkins -l app.kubernetes.io/name=jenkins
    
    # Get service information
    echo -e "${YELLOW}🌐 Jenkins service information:${NC}"
    kubectl get svc jenkins -n jenkins
    
    # Wait for Jenkins to be ready
    echo -e "${YELLOW}⏳ Waiting for Jenkins to be ready...${NC}"
    kubectl wait --for=condition=available --timeout=300s deployment/jenkins -n jenkins
    
    # Get Minikube IP
    INFRA_IP=$(minikube ip -p infra-cluster)
    
    echo -e "${GREEN}✅ Jenkins is ready!${NC}"
    echo ""
    echo -e "${BLUE}Access Information:${NC}"
    echo "  URL: http://${INFRA_IP}:32000"
    echo "  Username: admin"
    echo "  Password: admin123"
    echo ""
    echo -e "${YELLOW}💡 You can also get the initial admin password with:${NC}"
    echo "  kubectl exec -n jenkins deployment/jenkins -- cat /var/jenkins_home/secrets/initialAdminPassword"
    
else
    echo -e "${RED}❌ Jenkins deployment not found. Running deployment...${NC}"
    
    # Run the updated deployment script
    ./deploy-components.sh
fi

echo -e "${GREEN}🎉 Jenkins test completed!${NC}"
