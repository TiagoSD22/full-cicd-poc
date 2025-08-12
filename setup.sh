#!/bin/bash

# Complete setup script for Infrastructure Kata

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${PURPLE}╔════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║         Infrastructure Kata           ║${NC}"
echo -e "${PURPLE}║      Complete Setup Script            ║${NC}"
echo -e "${PURPLE}╚════════════════════════════════════════╝${NC}"
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "${BLUE}🔍 Checking prerequisites...${NC}"

MISSING_DEPS=()

if ! command_exists minikube; then
    MISSING_DEPS+=("minikube")
fi

if ! command_exists kubectl; then
    MISSING_DEPS+=("kubectl")
fi

if ! command_exists helm; then
    MISSING_DEPS+=("helm")
fi

if ! command_exists docker; then
    MISSING_DEPS+=("docker")
fi

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    echo -e "${RED}❌ Missing dependencies: ${MISSING_DEPS[*]}${NC}"
    echo "Please install the missing dependencies and run this script again."
    echo ""
    echo "Installation links:"
    echo "- Minikube: https://minikube.sigs.k8s.io/docs/start/"
    echo "- kubectl: https://kubernetes.io/docs/tasks/tools/"
    echo "- Helm: https://helm.sh/docs/intro/install/"
    echo "- Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

echo -e "${GREEN}✅ All prerequisites are installed!${NC}"

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}❌ Docker is not running. Please start Docker and run this script again.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Docker is running!${NC}"
echo ""

# Setup clusters
echo -e "${BLUE}🚀 Setting up Minikube clusters...${NC}"
cd minikube
chmod +x setup-clusters.sh
./setup-clusters.sh

echo ""

# Deploy infrastructure components
echo -e "${BLUE}📦 Deploying infrastructure components...${NC}"
chmod +x deploy-components.sh
./deploy-components.sh

echo ""

# Deploy applications
echo -e "${BLUE}🌐 Deploying applications...${NC}"
chmod +x deploy-apps.sh
./deploy-apps.sh

echo ""

# Final information
APP_IP=$(minikube ip -p application-cluster)
INFRA_IP=$(minikube ip -p infra-cluster)

echo -e "${PURPLE}╔════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║          Setup Complete! 🎉           ║${NC}"
echo -e "${PURPLE}╚════════════════════════════════════════╝${NC}"
echo ""

echo -e "${YELLOW}📝 IMPORTANT: Add these entries to your hosts file:${NC}"
echo "   ${APP_IP} api.local"
echo "   ${APP_IP} app.local"
echo ""
echo -e "${BLUE}Hosts file locations:${NC}"
echo "   Linux/macOS: /etc/hosts"
echo "   Windows: C:\\Windows\\System32\\drivers\\etc\\hosts"
echo ""

echo -e "${GREEN}🌐 Application URLs:${NC}"
echo "   Frontend:        http://app.local"
echo "   Backend API:     http://api.local/api/hello"
echo "   Backend Health:  http://api.local/health"
echo ""

echo -e "${GREEN}🛠️  Infrastructure URLs:${NC}"
echo "   Jenkins:         http://${INFRA_IP}:32000"
echo "   Grafana:         http://${APP_IP}:30030"
echo "   Prometheus:      http://${APP_IP}:30090"
echo "   AlertManager:    http://${APP_IP}:30093"
echo ""

echo -e "${GREEN}🔐 Default Credentials:${NC}"
echo "   Jenkins:         admin / admin123"
echo "   Grafana:         admin / admin123"
echo ""

echo -e "${YELLOW}🧪 Test the setup:${NC}"
echo "   curl http://api.local/api/hello"
echo "   curl http://api.local/health"
echo ""

echo -e "${BLUE}📚 Next Steps:${NC}"
echo "1. Configure Jenkins pipelines for CI/CD"
echo "2. Set up Grafana dashboards for monitoring"
echo "3. Test the complete application flow"
echo "4. Explore the monitoring metrics"
echo ""

echo -e "${GREEN}🎉 Infrastructure Kata is ready to use!${NC}"
