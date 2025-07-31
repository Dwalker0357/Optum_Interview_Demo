#!/bin/bash

echo "🏭 PRODUCTION DEPLOYMENT CLEANUP"
echo "================================"
echo
echo "🚨 CRITICAL WARNING: PRODUCTION RESOURCE DESTRUCTION"
echo "This script will DESTROY ALL production infrastructure across 5 AWS regions:"
echo
echo "🌍 REGIONS AFFECTED:"
echo "   - Ireland (eu-west-1)"
echo "   - N.Virginia (us-east-1)" 
echo "   - Oregon (us-west-2)"
echo "   - Singapore (ap-southeast-1)"
echo "   - Canada (ca-central-1)"
echo
echo "💥 RESOURCES TO BE DESTROYED:"
echo "   - 5x VPCs with all subnets and networking"
echo "   - 1x Jenkins Master + 4x Jenkins Slaves"
echo "   - 5x Nessus Scanners across regions"
echo "   - 4x Application Servers per region"
echo "   - 5x Application Load Balancers (internal)"
echo "   - 5x NAT Gateways (~$1.125/hour savings)"
echo "   - Transit Gateway and VPN endpoints"
echo "   - Route53 DNS zones and SSL certificates"
echo "   - 5x GuardDuty detectors"
echo "   - 5x AWS Config recorders"
echo "   - Security Hub configuration and compliance standards"
echo "   - Drift detection Lambda functions and EventBridge rules"
echo "   - 5x WAF Web ACLs"
echo "   - All EFS File Systems and S3 buckets"
echo "   - All CloudWatch logs, alarms, and dashboards"
echo "   - All SNS topics and email subscriptions"
echo "   - All IAM roles, policies, and instance profiles"
echo "   - All Secrets Manager secrets"
echo "   - All EC2 Key Pairs"
echo
echo "💰 MASSIVE COST IMPACT:"
echo "   - Will STOP ~$35-50/HOUR in charges"
echo "   - Daily savings: ~$840-1200"
echo "   - Monthly savings: ~$25,000-36,000"
echo "   - Some storage costs may persist briefly"
echo
echo "⚠️  IRREVERSIBLE DESTRUCTION:"
echo "   - This action CANNOT be undone"
echo "   - Full redeployment takes 90-120 minutes"
echo "   - All data in EFS and S3 will be lost"
echo "   - All configurations will be lost"
echo

# Check for dry-run mode
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "🧪 DRY RUN MODE - No resources will be destroyed"
    echo
fi

# Multiple safety confirmations for production
if [ "$DRY_RUN" = false ]; then
    echo "🚨 PRODUCTION SAFETY CHECK #1"
    echo "This is PRODUCTION infrastructure destruction."
    echo "Are you absolutely certain you want to proceed?"
    echo
    read -p "Type 'production' to continue: " -r
    echo
    if [[ ! $REPLY == "production" ]]; then
        echo "❌ Cleanup cancelled - type 'production' to confirm"
        exit 0
    fi

    echo "🚨 PRODUCTION SAFETY CHECK #2"
    echo "This will destroy infrastructure across 5 AWS regions."
    echo "All production data and configurations will be permanently lost."
    echo "Cost savings: ~$12/hour (~$288/day)"
    echo
    read -p "Type 'destroy-all-regions' to continue: " -r
    echo
    if [[ ! $REPLY == "destroy-all-regions" ]]; then
        echo "❌ Cleanup cancelled - type 'destroy-all-regions' to confirm"
        exit 0
    fi

    echo "🚨 FINAL PRODUCTION SAFETY CHECK #3"
    echo "LAST CHANCE TO ABORT!"
    echo "This will PERMANENTLY DELETE:"
    echo "  - All production workloads"
    echo "  - All production data"
    echo "  - All production configurations" 
    echo "  - Multi-region infrastructure"
    echo
    echo "Estimated time to rebuild: 90-120 minutes"
    echo "Estimated rebuild cost: $105-200 just for deployment"
    echo
    read -p "Type 'PERMANENTLY-DESTROY-PRODUCTION' to proceed: " -r
    echo
    if [[ ! $REPLY == "PERMANENTLY-DESTROY-PRODUCTION" ]]; then
        echo "❌ Production cleanup cancelled"
        echo "💡 Consider using --dry-run first to see what would be destroyed"
        exit 0
    fi
fi

echo
echo "🚀 STARTING PRODUCTION CLEANUP"
echo "=============================="

# Check AWS credentials
echo "🔍 Validating AWS credentials..."
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "❌ AWS credentials not configured"
    echo "Please configure AWS CLI: aws configure"
    exit 1
fi

# Verify permissions for multi-region destruction
echo "🔍 Checking multi-region AWS permissions..."
if ! aws iam get-user >/dev/null 2>&1; then
    echo "❌ Insufficient AWS permissions for production cleanup"
    echo "Required: Full permissions across all 5 regions"
    exit 1
fi

# Get current region
CURRENT_REGION=$(aws configure get region)
if [ -z "$CURRENT_REGION" ]; then
    echo "⚠️ No default region set, using eu-west-1"
    export AWS_DEFAULT_REGION=eu-west-1
else
    echo "✅ Using region: $CURRENT_REGION"
fi

echo "✅ AWS validation complete"
echo

# Navigate to terraform directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

echo "🔍 Script location: $SCRIPT_DIR"
echo "🔍 Project root: $PROJECT_ROOT"
echo "🔍 Terraform directory: $TERRAFORM_DIR"

if [ ! -d "$TERRAFORM_DIR" ]; then
    echo "❌ Terraform directory not found at: $TERRAFORM_DIR"
    exit 1
fi

cd "$TERRAFORM_DIR"
echo "✅ Changed to terraform directory: $(pwd)"

# Check if production deployment state exists
if [ ! -f "production.tfvars" ]; then
    echo "⚠️ Production tfvars file not found, checking for existing deployment..."
    echo "❌ Production deployment tfvars not found"
    echo "Please run the production deployment first, or manually create production.tfvars"
    echo "Cannot destroy what hasn't been deployed."
    exit 1
fi

# Initialize Terraform with production backend
echo "🔧 Initializing Terraform with production backend..."
if [ ! -f "backend-production.tf" ]; then
    echo "Creating production backend configuration..."
    cat > backend-production.tf << EOF
terraform {
  backend "s3" {
    bucket = "optum-production-terraform-state"
    key    = "production/terraform.tfstate"
    region = "eu-west-1"
    
    encrypt = true
  }
}
EOF
fi

terraform init -reconfigure

# Validate configuration
echo "🔍 Validating Terraform configuration..."
if ! terraform validate; then
    echo "❌ Terraform validation failed"
    exit 1
fi

echo "✅ Terraform validation passed"

# Show current state overview
echo "📋 Checking current production infrastructure state..."
terraform show 2>/dev/null | grep -E "resource|data" | wc -l | xargs echo "Resources in state:"

# Generate destroy plan
echo "📋 Generating destruction plan for all 5 regions..."
if [ "$DRY_RUN" = true ]; then
    echo "🧪 DRY RUN: Would run: terraform plan -destroy -var-file=production.tfvars"
    terraform plan -destroy -var-file=production.tfvars
    echo
    echo "✅ DRY RUN COMPLETE"
    echo "=================="
    echo "No resources were destroyed (dry run mode)"
    echo "To actually destroy production, run without --dry-run flag"
    echo
    echo "💰 POTENTIAL SAVINGS: ~$12/hour (~$288/day)"
    exit 0
else
    terraform plan -destroy -var-file=production.tfvars -out=prod-destroy.tfplan
fi

echo
echo "🎯 READY TO DESTROY PRODUCTION INFRASTRUCTURE"
echo "============================================="
echo
echo "🌍 DESTRUCTION SCOPE:"
echo "   - 5 AWS regions will be cleaned"
echo "   - All enterprise infrastructure will be destroyed"
echo "   - All production data will be permanently lost"
echo "   - All security services will be removed"
echo "   - All monitoring and alerting will stop"
echo
echo "💰 IMMEDIATE COST SAVINGS:"
echo "   - ~$12/hour charges will stop"
echo "   - ~$288/day savings"
echo "   - GuardDuty, Config, WAF charges across 5 regions"
echo "   - Compute, networking, storage charges"
echo
echo "⏱️ DESTRUCTION TIME: 30-45 minutes"
echo
read -p "Execute PRODUCTION destruction plan? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Production destruction cancelled"
    echo "💡 Destroy plan saved as prod-destroy.tfplan"
    echo "💰 Production charges continue: ~$12/hour"
    exit 0
fi

# Execute destruction
echo
echo "🧹 DESTROYING PRODUCTION INFRASTRUCTURE"
echo "======================================="
echo "Started at: $(date)"
echo "Destroying across 5 regions..."
echo "This will take 30-45 minutes..."
echo "💰 Stopping ~$12/hour in charges..."
echo

terraform apply prod-destroy.tfplan

if [ $? -eq 0 ]; then
    echo
    echo "🎉 PRODUCTION CLEANUP SUCCESSFUL!"
    echo "================================"
    echo
    echo "✅ REGIONS CLEANED:"
    echo "   ✅ Ireland (eu-west-1) - All resources destroyed"
    echo "   ✅ N.Virginia (us-east-1) - All resources destroyed"
    echo "   ✅ Oregon (us-west-2) - All resources destroyed"
    echo "   ✅ Singapore (ap-southeast-1) - All resources destroyed"
    echo "   ✅ Canada (ca-central-1) - All resources destroyed"
    echo
    echo "✅ INFRASTRUCTURE DESTROYED:"
    echo "   ✅ All VPCs and networking across 5 regions"
    echo "   ✅ All compute resources (Jenkins, Nessus, Apps)"
    echo "   ✅ All load balancers and auto scaling groups"
    echo "   ✅ All security services (GuardDuty, Config, WAF)"
    echo "   ✅ All storage (EFS, S3 buckets)"
    echo "   ✅ All DNS and SSL certificates"
    echo "   ✅ All monitoring and alerting"
    echo "   ✅ All IAM roles and policies"
    echo "   ✅ Transit Gateway and VPN endpoints"
    echo
    echo "💰 MASSIVE COST SAVINGS:"
    echo "   ✅ ~$12/hour charges STOPPED"
    echo "   ✅ ~$288/day savings achieved"
    echo "   ✅ ~$8,700/month savings"
    echo "   ⚠️  S3 backend bucket preserved (contains Terraform state)"
    echo
    echo "📋 WHAT'S PRESERVED:"
    echo "   - Terraform state files (in S3 backend)"
    echo "   - AWS account and credentials"
    echo "   - Local Terraform configuration"
    echo "   - Deployment scripts"
    echo
    echo "🔄 TO REBUILD PRODUCTION:"
    echo "   Run: ./prod-deployment.sh"
    echo "   Rebuild time: 90-120 minutes"
    echo "   Rebuild cost: ~$105-200 for deployment time"
    echo
    echo "✅ PRODUCTION ENVIRONMENT SUCCESSFULLY DESTROYED!"
    echo "✅ COST HEMORRHAGING STOPPED!"
    
else
    echo
    echo "❌ PRODUCTION CLEANUP FAILED"
    echo "============================"
    echo "🚨 CRITICAL: Some production resources may still be running!"
    echo
    echo "Common issues:"
    echo "1. Cross-region dependencies not resolved"
    echo "2. Transit Gateway connections still active"
    echo "3. S3 buckets not empty in some regions"
    echo "4. Security groups still referenced"
    echo "5. Route53 hosted zones with external dependencies"
    echo
    echo "🆘 IMMEDIATE ACTIONS REQUIRED:"
    echo "1. Check AWS Console in ALL 5 REGIONS for remaining resources"
    echo "2. Manually delete S3 bucket contents in all regions"
    echo "3. Disconnect Transit Gateway attachments"
    echo "4. Retry: terraform destroy -var-file=production.tfvars"
    echo "5. Use AWS Config/CloudFormation to find orphaned resources"
    echo
    echo "💰 URGENT: Production charges may still be accruing!"
    echo "💰 Check AWS Cost Explorer immediately!"
    echo "💰 Consider emergency AWS support case if charges continue"
    echo
    echo "🏥 EMERGENCY CLEANUP:"
    echo "   1. AWS Console → Resource Groups → Tag Editor"
    echo "   2. Search for tags: Project=optum-enterprise"
    echo "   3. Manually delete remaining resources"
    echo "   4. Check all 5 regions individually"
    exit 1
fi