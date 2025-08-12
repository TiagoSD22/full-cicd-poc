#!/bin/bash

# Minikube clusters setup script for Infrastructure Kata

set -e

echo "🚀 Setting up Minikube clusters for Infrastructure Kata..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if minikube is installed
if ! command -v minikube &> /dev/null; then
    echo -e "${RED}❌ Minikube is not installed. Please install minikube first.${NC}"
    echo "Visit: https://minikube.sigs.k8s.io/docs/start/"
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl is not installed. Please install kubectl first.${NC}"
    exit 1
fi

# Function to check if cluster exists and its status
check_cluster_status() {
    local cluster_name=$1
    local status=$(minikube status -p $cluster_name 2>/dev/null | grep "host:" | awk '{print $2}')
    if [ -z "$status" ]; then
        status="NotFound"
    fi
    echo $status
}

# Function to start existing cluster
start_existing_cluster() {
    local cluster_name=$1
    local purpose=$2
    
    echo -e "${YELLOW}🔄 Starting existing ${cluster_name} cluster for ${purpose}...${NC}"
    
    if minikube start -p $cluster_name; then
        echo -e "${GREEN}✅ ${cluster_name} cluster is now running!${NC}"
        return 0
    else
        echo -e "${RED}❌ Failed to start ${cluster_name} cluster${NC}"
        return 1
    fi
}

# Function to create and configure a cluster
setup_cluster() {
    local cluster_name=$1
    local cpus=$2
    local memory=$3
    local nodes=$4
    local purpose=$5
    
    echo -e "${YELLOW}📦 Setting up ${cluster_name} cluster for ${purpose}...${NC}"
    
    # Start minikube cluster
    minikube start \
        --profile=${cluster_name} \
        --cpus=${cpus} \
        --memory=${memory} \
        --nodes=${nodes} \
        --driver=docker \
        --kubernetes-version=v1.28.0 \
        --addons=dns,metrics-server
    
    # Configure kubectl context
    kubectl config use-context ${cluster_name}
    
    echo -e "${GREEN}✅ ${cluster_name} cluster is ready!${NC}"
}

# Function to handle cluster setup or reuse
handle_cluster() {
    local cluster_name=$1
    local cpus=$2
    local memory=$3
    local nodes=$4
    local purpose=$5
    
    local status=$(check_cluster_status $cluster_name)
    
    case $status in
        "Running")
            echo -e "${GREEN}✅ ${cluster_name} cluster is already running!${NC}"
            kubectl config use-context ${cluster_name}
            ;;
        "Stopped")
            start_existing_cluster $cluster_name "$purpose"
            kubectl config use-context ${cluster_name}
            ;;
        "NotFound")
            setup_cluster $cluster_name $cpus $memory $nodes "$purpose"
            ;;
        *)
            echo -e "${YELLOW}⚠️  ${cluster_name} cluster status: $status. Attempting to recreate...${NC}"
            # Delete potentially corrupted cluster
            minikube delete -p $cluster_name 2>/dev/null || true
            setup_cluster $cluster_name $cpus $memory $nodes "$purpose"
            ;;
    esac
}

# Handle infrastructure cluster (Jenkins + OpenTofu)
echo -e "${BLUE}🏗️  Handling Infrastructure Cluster...${NC}"
handle_cluster "infra-cluster" 4 2200 2 "Infrastructure (Jenkins + OpenTofu)"

# Handle application cluster (Backend + Frontend + Monitoring)
echo -e "${BLUE}🚀 Handling Application Cluster...${NC}"
handle_cluster "application-cluster" 4 2200 3 "Applications (Backend + Frontend + Monitoring)"

echo -e "${GREEN}🎉 All clusters are ready!${NC}"
echo ""
echo "Cluster Information:"
echo "==================="
echo -e "${YELLOW}Infrastructure Cluster:${NC}"
minikube profile infra-cluster
minikube status
echo ""
echo -e "${YELLOW}Application Cluster:${NC}"
minikube profile application-cluster
minikube status
echo ""
echo -e "${BLUE}Available Kubernetes Contexts:${NC}"
kubectl config get-contexts
echo ""
echo -e "${GREEN}✅ Setup complete! You can now deploy applications.${NC}"
echo "Next steps:"
echo "  1. Deploy infrastructure: ./deploy-components.sh"
echo "  2. Deploy applications: ./deploy-apps.sh"
