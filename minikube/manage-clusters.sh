#!/bin/bash

# Cluster management utility script

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CLUSTERS=("infra-cluster" "application-cluster")

show_usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  status    - Show status of all clusters"
    echo "  start     - Start all stopped clusters"
    echo "  stop      - Stop all running clusters"
    echo "  restart   - Restart all clusters"
    echo "  delete    - Delete all clusters"
    echo "  info      - Show detailed cluster information"
    echo "  contexts  - Show kubectl contexts"
    echo "  help      - Show this help message"
}

show_status() {
    echo -e "${BLUE}📊 Cluster Status:${NC}"
    echo "=================="
    for cluster in "${CLUSTERS[@]}"; do
        echo -n "• $cluster: "
        status=$(minikube status -p $cluster 2>/dev/null | grep "host:" | awk '{print $2}')
        if [ -z "$status" ]; then
            status="NotFound"
        fi
        case $status in
            "Running")
                echo -e "${GREEN}✅ Running${NC}"
                ;;
            "Stopped")
                echo -e "${YELLOW}⏸️  Stopped${NC}"
                ;;
            "NotFound")
                echo -e "${RED}❌ Not Found${NC}"
                ;;
            *)
                echo -e "${RED}❓ $status${NC}"
                ;;
        esac
    done
}

start_clusters() {
    echo -e "${BLUE}🚀 Starting all clusters...${NC}"
    for cluster in "${CLUSTERS[@]}"; do
        status=$(minikube status -p $cluster 2>/dev/null | grep "host:" | awk '{print $2}' || echo "NotFound")
        if [[ $status == "Stopped" ]]; then
            echo -e "${YELLOW}Starting $cluster...${NC}"
            minikube start -p $cluster
        elif [[ $status == "Running" ]]; then
            echo -e "${GREEN}$cluster is already running${NC}"
        else
            echo -e "${RED}$cluster not found, skipping...${NC}"
        fi
    done
}

stop_clusters() {
    echo -e "${BLUE}⏹️  Stopping all clusters...${NC}"
    for cluster in "${CLUSTERS[@]}"; do
        status=$(minikube status -p $cluster 2>/dev/null | grep "host:" | awk '{print $2}' || echo "NotFound")
        if [[ $status == "Running" ]]; then
            echo -e "${YELLOW}Stopping $cluster...${NC}"
            minikube stop -p $cluster
        elif [[ $status == "Stopped" ]]; then
            echo -e "${YELLOW}$cluster is already stopped${NC}"
        else
            echo -e "${RED}$cluster not found, skipping...${NC}"
        fi
    done
}

restart_clusters() {
    echo -e "${BLUE}🔄 Restarting all clusters...${NC}"
    stop_clusters
    sleep 2
    start_clusters
}

delete_clusters() {
    echo -e "${RED}⚠️  This will permanently delete all clusters!${NC}"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        for cluster in "${CLUSTERS[@]}"; do
            echo -e "${RED}Deleting $cluster...${NC}"
            minikube delete -p $cluster 2>/dev/null || true
        done
        echo -e "${GREEN}✅ All clusters deleted${NC}"
    else
        echo -e "${YELLOW}❌ Operation cancelled${NC}"
    fi
}

show_info() {
    echo -e "${BLUE}📋 Detailed Cluster Information:${NC}"
    echo "================================="
    for cluster in "${CLUSTERS[@]}"; do
        echo -e "${YELLOW}$cluster:${NC}"
        minikube profile $cluster
        minikube status 2>/dev/null || echo "  Status: Not found"
        echo ""
    done
}

show_contexts() {
    echo -e "${BLUE}🔗 Kubectl Contexts:${NC}"
    echo "==================="
    kubectl config get-contexts
}

# Main command handling
case "${1:-help}" in
    "status")
        show_status
        ;;
    "start")
        start_clusters
        ;;
    "stop")
        stop_clusters
        ;;
    "restart")
        restart_clusters
        ;;
    "delete")
        delete_clusters
        ;;
    "info")
        show_info
        ;;
    "contexts")
        show_contexts
        ;;
    "help"|*)
        show_usage
        ;;
esac
