#!/bin/bash

# ECR Lifecycle Management and Security Scanning Script
# This script manages ECR lifecycle policies and integrates with security scanning tools

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 ECR Lifecycle Management and Security Scanning${NC}"

# Configuration
BACKEND_ECR_REPO="backend-api"
FRONTEND_ECR_REPO="frontend-app"

# Get AWS account details
get_aws_info() {
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region || echo "us-east-1")
    REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    
    echo -e "${GREEN}✅ AWS Account ID: $AWS_ACCOUNT_ID${NC}"
    echo -e "${GREEN}✅ AWS Region: $AWS_REGION${NC}"
    echo -e "${GREEN}✅ ECR Registry: $REGISTRY_URL${NC}"
}

# Function to install Trivy if not present
install_trivy() {
    if ! command -v trivy &> /dev/null; then
        echo -e "${YELLOW}📦 Installing Trivy security scanner...${NC}"
        curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
        echo -e "${GREEN}✅ Trivy installed successfully${NC}"
    else
        echo -e "${GREEN}✅ Trivy already installed${NC}"
    fi
}

# Function to setup ECR lifecycle policies
setup_lifecycle_policies() {
    echo -e "${YELLOW}🔄 Setting up ECR lifecycle policies...${NC}"
    
    # Create comprehensive lifecycle policy
    cat > lifecycle-policy.json <<EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Keep last 10 production images",
            "selection": {
                "tagStatus": "tagged",
                "tagPrefixList": ["prod", "release"],
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
                "tagPrefixList": ["staging", "dev"],
                "countType": "imageCountMoreThan",
                "countNumber": 5
            },
            "action": {
                "type": "expire"
            }
        },
        {
            "rulePriority": 3,
            "description": "Keep last 3 latest images",
            "selection": {
                "tagStatus": "tagged",
                "tagPrefixList": ["latest"],
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
            "description": "Delete images older than 30 days except production",
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
    
    # Apply lifecycle policy to all repositories
    for repo in $BACKEND_ECR_REPO $FRONTEND_ECR_REPO; do
        echo -e "${YELLOW}📋 Applying lifecycle policy to $repo...${NC}"
        aws ecr put-lifecycle-policy \
            --repository-name $repo \
            --lifecycle-policy-text file://lifecycle-policy.json \
            --region $AWS_REGION
        echo -e "${GREEN}✅ Lifecycle policy applied to $repo${NC}"
    done
    
    rm lifecycle-policy.json
}

# Function to enable ECR image scanning
enable_image_scanning() {
    echo -e "${YELLOW}🔍 Enabling ECR image scanning...${NC}"
    
    for repo in $BACKEND_ECR_REPO $FRONTEND_ECR_REPO; do
        echo -e "${YELLOW}📋 Enabling scan on push for $repo...${NC}"
        aws ecr put-image-scanning-configuration \
            --repository-name $repo \
            --image-scanning-configuration scanOnPush=true \
            --region $AWS_REGION
        echo -e "${GREEN}✅ Image scanning enabled for $repo${NC}"
    done
}

# Function to scan specific image with Trivy
scan_image_with_trivy() {
    local repo=$1
    local tag=${2:-latest}
    local image_uri="$REGISTRY_URL/$repo:$tag"
    
    echo -e "${YELLOW}🔍 Scanning $image_uri with Trivy...${NC}"
    
    # Login to ECR
    aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $REGISTRY_URL
    
    # Run Trivy scan
    trivy image \
        --format json \
        --output "$repo-$tag-scan-results.json" \
        --severity HIGH,CRITICAL \
        "$image_uri"
    
    # Create human-readable report
    trivy image \
        --format table \
        --severity HIGH,CRITICAL \
        "$image_uri" > "$repo-$tag-scan-report.txt"
    
    echo -e "${GREEN}✅ Scan completed for $image_uri${NC}"
    echo -e "${BLUE}📄 Results saved to:${NC}"
    echo "  • JSON: $repo-$tag-scan-results.json"
    echo "  • Report: $repo-$tag-scan-report.txt"
    
    # Check if critical vulnerabilities found
    critical_count=$(jq '.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")' "$repo-$tag-scan-results.json" | jq -s length)
    high_count=$(jq '.Results[]?.Vulnerabilities[]? | select(.Severity == "HIGH")' "$repo-$tag-scan-results.json" | jq -s length)
    
    echo -e "${BLUE}📊 Vulnerability Summary:${NC}"
    echo "  • Critical: $critical_count"
    echo "  • High: $high_count"
    
    if [ "$critical_count" -gt 0 ]; then
        echo -e "${RED}❌ Critical vulnerabilities found! Review required.${NC}"
        return 1
    elif [ "$high_count" -gt 5 ]; then
        echo -e "${YELLOW}⚠️  High number of high-severity vulnerabilities. Consider updating base images.${NC}"
        return 2
    else
        echo -e "${GREEN}✅ Security scan passed${NC}"
        return 0
    fi
}

# Function to scan all latest images
scan_all_images() {
    echo -e "${YELLOW}🔍 Scanning all repository images...${NC}"
    
    local scan_results=()
    
    for repo in $BACKEND_ECR_REPO $FRONTEND_ECR_REPO; do
        echo -e "${BLUE}🔍 Scanning $repo...${NC}"
        scan_image_with_trivy "$repo" "latest"
        scan_results+=($?)
    done
    
    # Summary
    echo -e "${BLUE}📊 Overall Scan Summary:${NC}"
    echo "======================="
    
    local total_repos=${#scan_results[@]}
    local passed_repos=0
    local failed_repos=0
    local warning_repos=0
    
    for result in "${scan_results[@]}"; do
        case $result in
            0) ((passed_repos++)) ;;
            1) ((failed_repos++)) ;;
            2) ((warning_repos++)) ;;
        esac
    done
    
    echo "  • Total repositories scanned: $total_repos"
    echo "  • Passed (low risk): $passed_repos"
    echo "  • Warnings (high vulns): $warning_repos"
    echo "  • Failed (critical vulns): $failed_repos"
    
    if [ $failed_repos -gt 0 ]; then
        echo -e "${RED}❌ Some images have critical vulnerabilities!${NC}"
        return 1
    elif [ $warning_repos -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Some images have high-severity vulnerabilities${NC}"
        return 2
    else
        echo -e "${GREEN}✅ All images passed security scan${NC}"
        return 0
    fi
}

# Function to get ECR repository information
get_repo_info() {
    echo -e "${YELLOW}📋 ECR Repository Information${NC}"
    echo "============================="
    
    for repo in $BACKEND_ECR_REPO $FRONTEND_ECR_REPO; do
        echo -e "${BLUE}Repository: $repo${NC}"
        
        # Get repository info
        repo_info=$(aws ecr describe-repositories --repository-names $repo --region $AWS_REGION)
        created_at=$(echo "$repo_info" | jq -r '.repositories[0].createdAt')
        registry_id=$(echo "$repo_info" | jq -r '.repositories[0].registryId')
        repository_uri=$(echo "$repo_info" | jq -r '.repositories[0].repositoryUri')
        
        echo "  • Created: $created_at"
        echo "  • Registry ID: $registry_id"
        echo "  • URI: $repository_uri"
        
        # Get image count
        image_count=$(aws ecr list-images --repository-name $repo --region $AWS_REGION | jq '.imageIds | length')
        echo "  • Total images: $image_count"
        
        # Get latest image info
        latest_image=$(aws ecr describe-images --repository-name $repo --region $AWS_REGION --image-ids imageTag=latest 2>/dev/null || echo "null")
        if [ "$latest_image" != "null" ]; then
            image_size=$(echo "$latest_image" | jq -r '.imageDetails[0].imageSizeInBytes')
            pushed_at=$(echo "$latest_image" | jq -r '.imageDetails[0].imagePushedAt')
            size_mb=$((image_size / 1024 / 1024))
            echo "  • Latest image size: ${size_mb}MB"
            echo "  • Last pushed: $pushed_at"
        else
            echo "  • No 'latest' tag found"
        fi
        
        # Get scan results if available
        scan_results=$(aws ecr describe-image-scan-findings --repository-name $repo --image-id imageTag=latest --region $AWS_REGION 2>/dev/null || echo "null")
        if [ "$scan_results" != "null" ]; then
            scan_status=$(echo "$scan_results" | jq -r '.imageScanStatus.status')
            if [ "$scan_status" == "COMPLETE" ]; then
                critical_count=$(echo "$scan_results" | jq '.imageScanFindings.findingCounts.CRITICAL // 0')
                high_count=$(echo "$scan_results" | jq '.imageScanFindings.findingCounts.HIGH // 0')
                medium_count=$(echo "$scan_results" | jq '.imageScanFindings.findingCounts.MEDIUM // 0')
                echo "  • Scan status: $scan_status"
                echo "  • Critical vulns: $critical_count"
                echo "  • High vulns: $high_count"
                echo "  • Medium vulns: $medium_count"
            else
                echo "  • Scan status: $scan_status"
            fi
        else
            echo "  • Scan: Not available"
        fi
        echo ""
    done
}

# Function to promote image (tag as production-ready)
promote_image() {
    local repo=$1
    local source_tag=${2:-latest}
    local target_tag=${3:-prod-$(date +%Y%m%d-%H%M%S)}
    
    echo -e "${YELLOW}🚀 Promoting $repo:$source_tag to $target_tag...${NC}"
    
    # Get image manifest
    manifest=$(aws ecr batch-get-image --repository-name $repo --image-ids imageTag=$source_tag --region $AWS_REGION --query 'images[0].imageManifest' --output text)
    
    # Tag image with production tag
    aws ecr put-image --repository-name $repo --image-manifest "$manifest" --image-tag $target_tag --region $AWS_REGION
    
    echo -e "${GREEN}✅ Image promoted: $repo:$source_tag → $repo:$target_tag${NC}"
}

# Function to setup automated scanning workflow
setup_scanning_workflow() {
    echo -e "${YELLOW}🔄 Setting up automated scanning workflow...${NC}"
    
    # Create a script for automated scanning
    cat > ecr-scan-automation.sh <<'EOF'
#!/bin/bash

# Automated ECR scanning workflow
# This script can be run as a cron job or triggered by CI/CD

REPOS=("backend-api" "frontend-app")
AWS_REGION=${AWS_REGION:-"us-east-1"}
SLACK_WEBHOOK=${SLACK_WEBHOOK:-""}

# Function to send Slack notification
send_slack_notification() {
    local message=$1
    local color=${2:-"good"}
    
    if [ -n "$SLACK_WEBHOOK" ]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"attachments\":[{\"color\":\"$color\",\"text\":\"$message\"}]}" \
            "$SLACK_WEBHOOK"
    fi
}

# Scan all repositories
for repo in "${REPOS[@]}"; do
    echo "Scanning $repo..."
    
    # Trigger ECR scan
    aws ecr start-image-scan --repository-name $repo --image-id imageTag=latest --region $AWS_REGION
    
    # Wait for scan to complete (max 5 minutes)
    for i in {1..30}; do
        status=$(aws ecr describe-image-scan-findings --repository-name $repo --image-id imageTag=latest --region $AWS_REGION --query 'imageScanStatus.status' --output text 2>/dev/null || echo "IN_PROGRESS")
        
        if [ "$status" == "COMPLETE" ]; then
            echo "Scan completed for $repo"
            break
        fi
        
        echo "Waiting for scan to complete... ($i/30)"
        sleep 10
    done
    
    # Get scan results
    if [ "$status" == "COMPLETE" ]; then
        scan_results=$(aws ecr describe-image-scan-findings --repository-name $repo --image-id imageTag=latest --region $AWS_REGION)
        critical_count=$(echo "$scan_results" | jq '.imageScanFindings.findingCounts.CRITICAL // 0')
        high_count=$(echo "$scan_results" | jq '.imageScanFindings.findingCounts.HIGH // 0')
        
        if [ "$critical_count" -gt 0 ]; then
            message="🚨 CRITICAL: $repo has $critical_count critical vulnerabilities!"
            send_slack_notification "$message" "danger"
            echo "$message"
        elif [ "$high_count" -gt 5 ]; then
            message="⚠️  WARNING: $repo has $high_count high-severity vulnerabilities"
            send_slack_notification "$message" "warning"
            echo "$message"
        else
            message="✅ PASS: $repo security scan completed successfully"
            send_slack_notification "$message" "good"
            echo "$message"
        fi
    else
        message="❌ ERROR: Scan failed or timed out for $repo"
        send_slack_notification "$message" "danger"
        echo "$message"
    fi
done
EOF
    
    chmod +x ecr-scan-automation.sh
    
    echo -e "${GREEN}✅ Automated scanning workflow created: ecr-scan-automation.sh${NC}"
    echo -e "${BLUE}💡 To schedule automated scans, add to crontab:${NC}"
    echo "# Run every day at 2 AM"
    echo "0 2 * * * /path/to/ecr-scan-automation.sh"
    echo ""
    echo -e "${BLUE}💡 To enable Slack notifications, set SLACK_WEBHOOK environment variable${NC}"
}

# Main function
main() {
    local action=${1:-"help"}
    
    case $action in
        "lifecycle")
            get_aws_info
            setup_lifecycle_policies
            ;;
        "scanning")
            get_aws_info
            enable_image_scanning
            ;;
        "install-trivy")
            install_trivy
            ;;
        "scan")
            get_aws_info
            install_trivy
            local repo=${2:-"all"}
            if [ "$repo" == "all" ]; then
                scan_all_images
            else
                scan_image_with_trivy "$repo" "${3:-latest}"
            fi
            ;;
        "info")
            get_aws_info
            get_repo_info
            ;;
        "promote")
            get_aws_info
            promote_image "$2" "$3" "$4"
            ;;
        "workflow")
            setup_scanning_workflow
            ;;
        "all")
            get_aws_info
            setup_lifecycle_policies
            enable_image_scanning
            install_trivy
            scan_all_images
            setup_scanning_workflow
            ;;
        "help"|*)
            echo -e "${BLUE}ECR Lifecycle Management and Security Scanning${NC}"
            echo "=============================================="
            echo ""
            echo "Usage: $0 <action> [parameters]"
            echo ""
            echo "Actions:"
            echo "  lifecycle                    - Setup ECR lifecycle policies"
            echo "  scanning                     - Enable ECR image scanning"
            echo "  install-trivy               - Install Trivy security scanner"
            echo "  scan [repo] [tag]           - Scan specific image (use 'all' for all repos)"
            echo "  info                        - Show ECR repository information"
            echo "  promote <repo> [src] [dest] - Promote image to production tag"
            echo "  workflow                    - Setup automated scanning workflow"
            echo "  all                         - Run all setup actions"
            echo "  help                        - Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 scan all                 - Scan all repositories"
            echo "  $0 scan backend-api latest  - Scan specific image"
            echo "  $0 promote backend-api      - Promote latest to production"
            echo "  $0 info                     - Show repository information"
            ;;
    esac
}

# Run main function with all arguments
main "$@"
