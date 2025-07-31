#!/bin/bash

echo "🏭 PRODUCTION STAGED DEPLOYMENT - Multi-region with dependency management"
echo "========================================================================"
echo
echo "This deployment breaks down production infrastructure into stages across 5 regions:"
echo "1. Foundation (Secrets, VPC, IAM) - All regions"
echo "2. Security groups & baseline networking"
echo "3. Route53 global DNS & SSL"
echo "4. Load balancers & WAF per region"
echo "5. Compute resources region by region"
echo "6. Security services, automation & compliance across all regions"
echo

# Check for dry-run mode
DRY_RUN=false
VALIDATION_MODE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --validate|--validation)
      VALIDATION_MODE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      echo "Unknown option $1"
      echo "Usage: $0 [--validate] [--dry-run]"
      echo "  --validate    Run validation only (no deployment)"
      echo "  --dry-run     Generate plan only (no apply)"
      exit 1
      ;;
  esac
done

# Quick validation mode check
if [ "$VALIDATION_MODE" = true ]; then
    echo "🔍 VALIDATION MODE - Terraform validation only"
    cd ../terraform
    if terraform validate; then
        echo "✅ Terraform configuration is valid"
    else
        echo "❌ Terraform validation failed"
        exit 1
    fi
    exit 0
fi

echo "🌍 PRODUCTION DEPLOYMENT SCOPE:"
echo "   - 5 REGIONS: Ireland, N.Virginia, Oregon, Singapore, Canada"
echo "   - Enhanced security enabled across all regions"
echo "   - Estimated cost: ~$12/hour (~$8,700/month) - See README for details"
echo "   - Deployment time: 90-120 minutes (staged)"

if [ "$DRY_RUN" = false ]; then
    echo
    echo "🚨 COST CONFIRMATION"
    echo "This production deployment will cost approximately $12 per hour (~$8,700/month)"
    echo "Enhanced security and multi-region redundancy significantly increase costs"
    echo
    read -p "Do you understand this will cost ~$12/HOUR (~$8,700/month) and want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Deployment cancelled"
        echo "💡 Consider using UAT deployment instead"
        exit 0
    fi
fi

# Check AWS credentials
echo "🔍 Validating AWS credentials..."
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "❌ AWS credentials not configured"
    echo "Run: aws configure"
    exit 1
fi

# Navigate to terraform directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

cd "$TERRAFORM_DIR"

# Check/Create S3 backend bucket
if ! aws s3 ls s3://optum-production-terraform-state >/dev/null 2>&1; then
    echo "Creating S3 backend bucket for production..."
    aws s3 mb s3://optum-production-terraform-state --region eu-west-1
    aws s3api put-bucket-versioning --bucket optum-production-terraform-state --versioning-configuration Status=Enabled
    aws s3api put-bucket-encryption --bucket optum-production-terraform-state --server-side-encryption-configuration '{
        "Rules": [
            {
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }
        ]
    }'
    echo "✅ S3 backend bucket created with encryption and versioning"
fi

# Check/Create DynamoDB lock table
if ! aws dynamodb describe-table --table-name optum-terraform-locks --region eu-west-1 >/dev/null 2>&1; then
    echo "Creating DynamoDB lock table for production state locking..."
    aws dynamodb create-table \
        --table-name optum-terraform-locks \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region eu-west-1 \
        --tags Key=Project,Value=optum-production Key=Environment,Value=production
    echo "✅ DynamoDB lock table created"
fi

# Create production configuration if it doesn't exist
if [ ! -f "production.tfvars" ]; then
    echo "Creating production configuration file..."
    cat > production.tfvars << 'EOF'
# Production Infrastructure Configuration
deployment_mode = "full"
project_name    = "optum-production"
environment     = "production"
owner          = "optum-enterprise"

# SECURITY ENHANCEMENTS - Enable all security features for production
enable_security_enhancements = true
use_enhanced_security_groups = true

# Regional Configuration - All 5 regions
primary_region    = "eu-west-1"
enabled_regions   = ["eu-west-1", "us-east-1", "us-west-2", "ap-southeast-1", "ca-central-1"]

# Network Configuration
enable_nat_gateway      = true
single_nat_gateway     = false
one_nat_gateway_per_az = true
enable_dns_hostnames   = true
enable_dns_support     = true
enable_flow_logs       = true
enable_vpc_endpoints   = true

# Security Configuration
allowed_web_cidrs = ["203.45.67.89/32"]
allowed_ssh_cidrs = ["203.45.67.89/32"]
create_dns_zone   = true
domain_name      = "optum-production.com"

# Service Configuration
enable_monitoring = true

# Email Configuration for Production Alerts
demo_email_address = "example@gmail.com"

# Cost Protection
enable_cost_alerts = true
daily_budget_limit = 200
alert_email_addresses = ["example@gmail.com"]
enable_detailed_monitoring = true

# Demo-specific Configuration (disabled for production)
enable_demo_mode = false
enable_vulnerability_testing = false
create_intentional_vulns = false

# Jenkins Configuration
jenkins_agents = {
  min_size         = 1
  max_size         = 3
  desired_capacity = 1
}

# Nessus Configuration  
nessus_scanners = {
  min_size         = 1
  max_size         = 2
  desired_capacity = 1
}

# Instance Configuration (Production sizing)
key_pair_name = "optum-production-key"

# Feature Flags
enable_transit_gateway = false
enable_multi_region   = true

# New Features (Weekend Implementation)
enable_drift_detection = true
enable_security_hub = true    # Enable for production compliance
enable_guardduty = true       # Enable for production security

# Common Tags
common_tags = {
  Environment = "production"
  Project     = "optum-enterprise"
  Owner       = "optum-demo"
  CostCenter  = "infrastructure"
  Deployment  = "production"
}
EOF
fi

# Initialize Terraform with production backend
echo "🔧 Initializing Terraform with production backend..."
cat > backend-production.tf << EOF
terraform {
  backend "s3" {
    bucket = "optum-production-terraform-state"
    key    = "production/terraform.tfstate"
    region = "eu-west-1"
    
    dynamodb_table = "optum-terraform-locks"
    encrypt        = true
  }
}
EOF

terraform init -reconfigure

# Validate configuration
echo "📋 Validating Terraform configuration..."
terraform validate

if [ $? -ne 0 ]; then
    echo "❌ Terraform validation failed"
    exit 1
fi

if [ "$DRY_RUN" = true ]; then
    echo "🧪 DRY RUN: Planning production deployment..."
    terraform plan -var-file=production.tfvars
    echo
    echo "✅ DRY RUN COMPLETE"
    echo "=================="
    echo "Plan shows what would be deployed"
    echo "Cost: ~$12/hour (~$8,700/month) across 5 regions"
    exit 0
fi

# Create key pairs in all regions
echo "🔑 Setting up key pairs in all regions..."
REGIONS=("eu-west-1" "us-east-1" "us-west-2" "ap-southeast-1" "ca-central-1")

# Create primary key pair
if ! aws ec2 describe-key-pairs --key-names optum-production-key --region eu-west-1 >/dev/null 2>&1; then
    echo "Creating production key pair in primary region..."
    aws ec2 create-key-pair --key-name optum-production-key --region eu-west-1 --query 'KeyMaterial' --output text > ~/.ssh/optum-production-key.pem
    chmod 400 ~/.ssh/optum-production-key.pem
    echo "✅ Primary key pair created"
fi

# Import to other regions
for region in "${REGIONS[@]}"; do
    if [[ "$region" != "eu-west-1" ]]; then
        echo "Setting up key pair in $region..."
        if ! aws ec2 describe-key-pairs --key-names optum-production-key --region $region >/dev/null 2>&1; then
            aws ec2 import-key-pair --key-name optum-production-key --public-key-material fileb://<(ssh-keygen -y -f ~/.ssh/optum-production-key.pem) --region $region >/dev/null
        fi
    fi
done

echo "✅ Key pairs configured in all regions"

echo
echo "🚀 STARTING STAGED PRODUCTION DEPLOYMENT"
echo "========================================"
echo "⏱️ Estimated total time: 90-120 minutes"
echo "💰 Estimated cost: ~$12/hour (~$8,700/month)"

read -p "Proceed with staged production deployment? (yes/NO): " final_confirm

if [[ "$final_confirm" != "yes" ]]; then
    echo "❌ Deployment cancelled"
    exit 0
fi

echo
echo "📋 STAGE 1: Foundation - All Regions (Secrets, VPC, IAM)"
echo "========================================================="
echo "Deploying core infrastructure across 5 regions..."

terraform apply -var-file=production.tfvars \
  -target=module.secrets \
  -target=module.vpc \
  -target=module.iam \
  -auto-approve

if [ $? -ne 0 ]; then
    echo "❌ Stage 1 failed"
    exit 1
fi

echo "✅ Stage 1 complete - Foundation deployed across all regions"
echo

echo "📋 STAGE 2: Security Groups & Networking - All Regions"
echo "======================================================="
echo "Deploying enhanced security groups across all regions..."

terraform apply -var-file=production.tfvars \
  -target=module.security_groups \
  -auto-approve

if [ $? -ne 0 ]; then
    echo "❌ Stage 2 failed"
    exit 1
fi

echo "✅ Stage 2 complete - Security groups deployed"
echo

echo "📋 STAGE 3: Global DNS & SSL"
echo "============================"
echo "Deploying Route53 and global SSL certificates..."

terraform apply -var-file=production.tfvars \
  -target=module.route53 \
  -target=time_sleep.route53_propagation \
  -auto-approve

if [ $? -ne 0 ]; then
    echo "❌ Stage 3 failed"
    exit 1
fi

echo "✅ Stage 3 complete - Global DNS configured"
echo

echo "📋 STAGE 4: Load Balancers & WAF - All Regions"
echo "==============================================="
echo "Deploying ALB and WAF across all regions..."

terraform apply -var-file=production.tfvars \
  -target=module.alb \
  -target=module.waf \
  -auto-approve

if [ $? -ne 0 ]; then
    echo "❌ Stage 4 failed"
    exit 1
fi

echo "✅ Stage 4 complete - Load balancers and WAF deployed"
echo

echo "📋 STAGE 5: Compute Resources - Region by Region"
echo "================================================"
echo "Deploying compute resources across all regions..."

# Deploy bastion hosts first (they're simpler)
terraform apply -var-file=production.tfvars \
  -target=module.bastion \
  -auto-approve

if [ $? -ne 0 ]; then
    echo "❌ Stage 5a (Bastion) failed"
    exit 1
fi

echo "✅ Bastion hosts deployed"

# Deploy Jenkins (primary region first, then agents)
terraform apply -var-file=production.tfvars \
  -target=module.jenkins \
  -auto-approve

if [ $? -ne 0 ]; then
    echo "❌ Stage 5b (Jenkins) failed"
    exit 1
fi

echo "✅ Jenkins infrastructure deployed"

# Deploy Nessus scanners
terraform apply -var-file=production.tfvars \
  -target=module.nessus \
  -auto-approve

if [ $? -ne 0 ]; then
    echo "❌ Stage 5c (Nessus) failed"
    exit 1
fi

echo "✅ Nessus scanners deployed"

# Deploy application servers
terraform apply -var-file=production.tfvars \
  -target=module.app_servers \
  -auto-approve

if [ $? -ne 0 ]; then
    echo "❌ Stage 5d (App Servers) failed"
    exit 1
fi

echo "✅ Stage 5 complete - All compute resources deployed"
echo

echo "📋 STAGE 6: Security Services, Automation & Compliance - All Regions"
echo "===================================================================="
echo "Deploying security services, drift detection, and compliance automation across all regions..."

terraform apply -var-file=production.tfvars \
  -target=module.guardduty \
  -target=module.config \
  -target=module.cloudtrail \
  -target=module.patch_management \
  -target=module.drift_detection \
  -target=module.security_hub \
  -auto-approve

if [ $? -ne 0 ]; then
    echo "❌ Stage 6 failed"
    exit 1
fi

echo "✅ Stage 6 complete - Security services deployed"
echo

echo "📋 FINAL STAGE: Complete Production Deployment"
echo "=============================================="
echo "Running final terraform apply to ensure consistency..."

terraform apply -var-file=production.tfvars -auto-approve

if [ $? -eq 0 ]; then
    echo
    echo "🎉 PRODUCTION STAGED DEPLOYMENT SUCCESSFUL!"
    echo "==========================================="
    echo
    echo "✅ All stages completed successfully"
    echo "✅ 5 regions fully deployed"
    echo "✅ Enhanced security enabled across all regions"
    echo "✅ Production infrastructure ready"
    echo
    echo "🌍 DEPLOYMENT SUMMARY:"
    echo "   Regions: 5 (Ireland, N.Virginia, Oregon, Singapore, Canada)"
    echo "   Security: Enhanced (GuardDuty, Config, WAF, CloudTrail)"
    echo "   Cost: ~$12/hour (~$8,700/month)"
    echo "   Status: ACTIVE"
    echo
    echo "🔗 ACCESS POINTS:"
    terraform output
    echo
    echo "📧 Email alerts configured for: example@gmail.com"
    echo "💰 Current cost: ~$12/hour (~$8,700/month)"
    echo "🧹 Manual cleanup required: ./prod-cleanup.sh"
    echo
    echo "🎬 PRODUCTION ENVIRONMENT READY!"
else
    echo
    echo "❌ Final production deployment stage failed"
    echo "Some resources may be in an inconsistent state"
    echo "Check the Terraform output above for details"
    echo "💰 WARNING: Resources may still be accruing charges!"
    exit 1
fi