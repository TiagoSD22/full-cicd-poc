#!/bin/bash

# ECR Image Lifecycle and Security Automation Script
# Integrates with ArgoCD for automated image promotion and vulnerability scanning

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ECR_BACKEND_REPO="backend-api"
ECR_FRONTEND_REPO="frontend-app"
TRIVY_SEVERITY_THRESHOLD="CRITICAL,HIGH"

echo -e "${BLUE}🔒 ECR Image Lifecycle and Security Automation${NC}"

# Function to check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}🔧 Checking prerequisites...${NC}"
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}❌ AWS CLI not found${NC}"
        exit 1
    fi
    
    # Check Trivy
    if ! command -v trivy &> /dev/null; then
        echo -e "${YELLOW}📥 Installing Trivy...${NC}"
        curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
        echo -e "${GREEN}✅ Trivy installed${NC}"
    else
        echo -e "${GREEN}✅ Trivy already installed${NC}"
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}❌ kubectl not found${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Prerequisites check completed${NC}"
}

# Function to get AWS information
get_aws_info() {
    echo -e "${YELLOW}📋 Getting AWS information...${NC}"
    
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region || echo "us-west-2")
    ECR_REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    
    echo -e "${GREEN}✅ AWS Account: $AWS_ACCOUNT_ID${NC}"
    echo -e "${GREEN}✅ AWS Region: $AWS_REGION${NC}"
    echo -e "${GREEN}✅ ECR Registry: $ECR_REGISTRY_URL${NC}"
}

# Function to setup ECR lifecycle policies
setup_lifecycle_policies() {
    echo -e "${YELLOW}🔄 Setting up ECR lifecycle policies...${NC}"
    
    # Create advanced lifecycle policy
    cat > lifecycle-policy.json <<EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Keep last 10 production images",
            "selection": {
                "tagStatus": "tagged",
                "tagPrefixList": ["prod", "stable", "release"],
                "countType": "imageCountMoreThan",
                "countNumber": 10
            },
            "action": {
                "type": "expire"
            }
        },
        {
            "rulePriority": 2,
            "description": "Keep last 5 staging images",
            "selection": {
                "tagStatus": "tagged",
                "tagPrefixList": ["staging", "stage"],
                "countType": "imageCountMoreThan",
                "countNumber": 5
            },
            "action": {
                "type": "expire"
            }
        },
        {
            "rulePriority": 3,
            "description": "Keep last 3 development images",
            "selection": {
                "tagStatus": "tagged",
                "tagPrefixList": ["dev", "latest"],
                "countType": "imageCountMoreThan",
                "countNumber": 3
            },
            "action": {
                "type": "expire"
            }
        },
        {
            "rulePriority": 4,
            "description": "Delete untagged images older than 1 day",
            "selection": {
                "tagStatus": "untagged",
                "countType": "sinceImagePushed",
                "countUnit": "days",
                "countNumber": 1
            },
            "action": {
                "type": "expire"
            }
        },
        {
            "rulePriority": 5,
            "description": "Delete any other images older than 30 days",
            "selection": {
                "tagStatus": "any",
                "countType": "sinceImagePushed",
                "countUnit": "days",
                "countNumber": 30
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
EOF

    # Apply to backend repository
    echo -e "${YELLOW}📦 Applying lifecycle policy to backend repository...${NC}"
    aws ecr put-lifecycle-policy \
        --repository-name $ECR_BACKEND_REPO \
        --lifecycle-policy-text file://lifecycle-policy.json \
        --region $AWS_REGION
    
    # Apply to frontend repository
    echo -e "${YELLOW}📦 Applying lifecycle policy to frontend repository...${NC}"
    aws ecr put-lifecycle-policy \
        --repository-name $ECR_FRONTEND_REPO \
        --lifecycle-policy-text file://lifecycle-policy.json \
        --region $AWS_REGION
    
    rm lifecycle-policy.json
    echo -e "${GREEN}✅ ECR lifecycle policies configured${NC}"
}

# Function to scan image with Trivy
scan_image_with_trivy() {
    local image_uri=$1
    local image_name=$2
    
    echo -e "${YELLOW}🔍 Scanning $image_name for vulnerabilities...${NC}"
    
    # Login to ECR for Trivy
    aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY_URL
    
    # Create scan results directory
    mkdir -p scan-results
    
    # Scan for vulnerabilities
    trivy image \
        --severity $TRIVY_SEVERITY_THRESHOLD \
        --format json \
        --output "scan-results/${image_name}-vulnerabilities.json" \
        $image_uri
    
    # Scan for secrets
    trivy image \
        --scanners secret \
        --format json \
        --output "scan-results/${image_name}-secrets.json" \
        $image_uri
    
    # Generate human-readable report
    trivy image \
        --severity $TRIVY_SEVERITY_THRESHOLD \
        --format table \
        --output "scan-results/${image_name}-report.txt" \
        $image_uri
    
    # Check if vulnerabilities were found
    VULN_COUNT=$(jq '.Results[0].Vulnerabilities | length' "scan-results/${image_name}-vulnerabilities.json" 2>/dev/null || echo "0")
    SECRET_COUNT=$(jq '.Results[0].Secrets | length' "scan-results/${image_name}-secrets.json" 2>/dev/null || echo "0")
    
    if [ "$VULN_COUNT" -gt 0 ]; then
        echo -e "${RED}❌ Found $VULN_COUNT critical/high vulnerabilities in $image_name${NC}"
        return 1
    elif [ "$SECRET_COUNT" -gt 0 ]; then
        echo -e "${RED}❌ Found $SECRET_COUNT secrets in $image_name${NC}"
        return 1
    else
        echo -e "${GREEN}✅ No critical/high vulnerabilities or secrets found in $image_name${NC}"
        return 0
    fi
}

# Function to scan all latest images
scan_latest_images() {
    echo -e "${YELLOW}🔍 Scanning latest images...${NC}"
    
    local backend_image="${ECR_REGISTRY_URL}/${ECR_BACKEND_REPO}:latest"
    local frontend_image="${ECR_REGISTRY_URL}/${ECR_FRONTEND_REPO}:latest"
    
    local scan_passed=true
    
    # Scan backend image
    if ! scan_image_with_trivy "$backend_image" "backend"; then
        scan_passed=false
    fi
    
    # Scan frontend image
    if ! scan_image_with_trivy "$frontend_image" "frontend"; then
        scan_passed=false
    fi
    
    if [ "$scan_passed" = true ]; then
        echo -e "${GREEN}✅ All images passed security scan${NC}"
        return 0
    else
        echo -e "${RED}❌ Some images failed security scan${NC}"
        return 1
    fi
}

# Function to promote images based on scan results
promote_images() {
    echo -e "${YELLOW}🚀 Promoting images based on scan results...${NC}"
    
    if scan_latest_images; then
        echo -e "${GREEN}✅ Security scans passed, promoting images...${NC}"
        
        # Get current timestamp for tagging
        TIMESTAMP=$(date +%Y%m%d-%H%M%S)
        
        # Tag and push backend image as staging
        echo -e "${YELLOW}📦 Promoting backend image to staging...${NC}"
        docker pull "${ECR_REGISTRY_URL}/${ECR_BACKEND_REPO}:latest"
        docker tag "${ECR_REGISTRY_URL}/${ECR_BACKEND_REPO}:latest" "${ECR_REGISTRY_URL}/${ECR_BACKEND_REPO}:staging-${TIMESTAMP}"
        docker push "${ECR_REGISTRY_URL}/${ECR_BACKEND_REPO}:staging-${TIMESTAMP}"
        
        # Tag and push frontend image as staging
        echo -e "${YELLOW}📦 Promoting frontend image to staging...${NC}"
        docker pull "${ECR_REGISTRY_URL}/${ECR_FRONTEND_REPO}:latest"
        docker tag "${ECR_REGISTRY_URL}/${ECR_FRONTEND_REPO}:latest" "${ECR_REGISTRY_URL}/${ECR_FRONTEND_REPO}:staging-${TIMESTAMP}"
        docker push "${ECR_REGISTRY_URL}/${ECR_FRONTEND_REPO}:staging-${TIMESTAMP}"
        
        echo -e "${GREEN}✅ Images promoted to staging with tag: staging-${TIMESTAMP}${NC}"
        
        # Update ArgoCD applications to use staging images
        update_argocd_staging_images "staging-${TIMESTAMP}"
        
    else
        echo -e "${RED}❌ Security scans failed, blocking image promotion${NC}"
        # Send notification or create alert
        create_security_alert
        return 1
    fi
}

# Function to update ArgoCD staging applications
update_argocd_staging_images() {
    local staging_tag=$1
    
    echo -e "${YELLOW}🎯 Updating ArgoCD staging applications...${NC}"
    
    # Check if ArgoCD CLI is available
    if command -v argocd &> /dev/null; then
        # Update backend staging app
        argocd app set backend-api-staging \
            --parameter image.tag="$staging_tag" \
            --parameter image.repository="${ECR_REGISTRY_URL}/${ECR_BACKEND_REPO}" \
            2>/dev/null || echo "Backend staging app not found"
        
        # Update frontend staging app
        argocd app set frontend-app-staging \
            --parameter image.tag="$staging_tag" \
            --parameter image.repository="${ECR_REGISTRY_URL}/${ECR_FRONTEND_REPO}" \
            2>/dev/null || echo "Frontend staging app not found"
        
        echo -e "${GREEN}✅ ArgoCD staging applications updated${NC}"
    else
        echo -e "${YELLOW}⚠️  ArgoCD CLI not available, skipping application update${NC}"
    fi
}

# Function to create security alert
create_security_alert() {
    echo -e "${RED}🚨 Creating security alert...${NC}"
    
    # Create alert file
    cat > scan-results/security-alert.json <<EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "alert_type": "SECURITY_SCAN_FAILED",
    "severity": "HIGH",
    "repository": ["$ECR_BACKEND_REPO", "$ECR_FRONTEND_REPO"],
    "message": "Image security scan failed - vulnerabilities or secrets detected",
    "action_required": "Review scan results and fix vulnerabilities before promotion"
}
EOF
    
    echo -e "${YELLOW}📄 Security alert created: scan-results/security-alert.json${NC}"
    
    # Send to Kubernetes event
    kubectl create event security-scan-failed \
        --namespace=applications \
        --message="Image security scan failed for latest images" \
        --reason="SecurityScanFailed" \
        --type="Warning" \
        2>/dev/null || true
}

# Function to setup automated scanning cronjob
setup_scanning_cronjob() {
    echo -e "${YELLOW}⏰ Setting up automated scanning cronjob...${NC}"
    
    # Create scan script for cronjob
    cat > /tmp/image-scan-cronjob.sh <<'EOF'
#!/bin/bash
cd /opt/infra-kata/minikube
./ecr-lifecycle.sh scan
EOF
    
    # Create cronjob manifest
    cat > scan-cronjob.yaml <<EOF
apiVersion: batch/v1
kind: CronJob
metadata:
  name: image-security-scan
  namespace: infrastructure
spec:
  schedule: "0 */6 * * *"  # Every 6 hours
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: image-scanner
            image: aquasec/trivy:latest
            command:
            - /bin/sh
            - -c
            - |
              # Install AWS CLI
              apk add --no-cache aws-cli curl
              
              # Configure AWS (assumes IAM role or env vars)
              aws configure set region ${AWS_REGION:-us-west-2}
              
              # Run scan
              trivy image --severity CRITICAL,HIGH ${ECR_REGISTRY_URL}/${ECR_BACKEND_REPO}:latest
              trivy image --severity CRITICAL,HIGH ${ECR_REGISTRY_URL}/${ECR_FRONTEND_REPO}:latest
            env:
            - name: AWS_REGION
              value: "$AWS_REGION"
            - name: ECR_REGISTRY_URL
              value: "$ECR_REGISTRY_URL"
            - name: ECR_BACKEND_REPO
              value: "$ECR_BACKEND_REPO"
            - name: ECR_FRONTEND_REPO
              value: "$ECR_FRONTEND_REPO"
          restartPolicy: OnFailure
          serviceAccountName: image-scanner
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: image-scanner
  namespace: infrastructure
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: infrastructure
  name: image-scanner
rules:
- apiGroups: [""]
  resources: ["events"]
  verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: image-scanner
  namespace: infrastructure
subjects:
- kind: ServiceAccount
  name: image-scanner
  namespace: infrastructure
roleRef:
  kind: Role
  name: image-scanner
  apiGroup: rbac.authorization.k8s.io
EOF
    
    # Apply cronjob
    kubectl apply -f scan-cronjob.yaml
    
    echo -e "${GREEN}✅ Automated scanning cronjob created${NC}"
}

# Function to check scan results
check_scan_results() {
    echo -e "${BLUE}📊 Scan Results Summary:${NC}"
    echo "======================="
    
    if [ -d "scan-results" ]; then
        echo -e "${YELLOW}📁 Scan results directory:${NC}"
        ls -la scan-results/
        echo ""
        
        # Show summary of latest scans
        for report in scan-results/*-report.txt; do
            if [ -f "$report" ]; then
                echo -e "${YELLOW}📄 $(basename "$report"):${NC}"
                head -20 "$report" 2>/dev/null || echo "Unable to read report"
                echo ""
            fi
        done
    else
        echo -e "${YELLOW}⚠️  No scan results found${NC}"
    fi
}

# Function to cleanup old scan results
cleanup_old_scans() {
    echo -e "${YELLOW}🧹 Cleaning up old scan results...${NC}"
    
    if [ -d "scan-results" ]; then
        # Keep only last 10 scan results
        find scan-results/ -name "*.json" -type f -mtime +7 -delete 2>/dev/null || true
        find scan-results/ -name "*.txt" -type f -mtime +7 -delete 2>/dev/null || true
        
        echo -e "${GREEN}✅ Old scan results cleaned up${NC}"
    fi
}

# Main function
main() {
    case "${1:-scan}" in
        "setup")
            check_prerequisites
            get_aws_info
            setup_lifecycle_policies
            setup_scanning_cronjob
            ;;
        "scan")
            check_prerequisites
            get_aws_info
            scan_latest_images
            check_scan_results
            ;;
        "promote")
            check_prerequisites
            get_aws_info
            promote_images
            ;;
        "results")
            check_scan_results
            ;;
        "cleanup")
            cleanup_old_scans
            ;;
        "lifecycle")
            get_aws_info
            setup_lifecycle_policies
            ;;
        *)
            echo -e "${BLUE}Usage:${NC}"
            echo "  $0 setup    - Complete setup of ECR lifecycle and scanning"
            echo "  $0 scan     - Scan latest images for vulnerabilities"
            echo "  $0 promote  - Promote images based on scan results"
            echo "  $0 results  - Show scan results"
            echo "  $0 cleanup  - Clean up old scan results"
            echo "  $0 lifecycle - Setup ECR lifecycle policies"
            ;;
    esac
}

# Run main function
main "$@"
