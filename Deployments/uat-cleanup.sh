#!/bin/bash

echo "🧹 UAT DEPLOYMENT CLEANUP"
echo "========================="
echo
echo "⚠️  WARNING: RESOURCE DESTRUCTION"
echo "This script will DESTROY all UAT deployment resources:"
echo "   - VPC with all subnets and networking"
echo "   - Jenkins Master + Agents (Auto Scaling Groups)"
echo "   - Nessus Scanners (Auto Scaling Groups)"
echo "   - Application Servers (Auto Scaling Groups)"
echo "   - Application Load Balancer"
echo "   - NAT Gateways, Internet Gateway, Route Tables"
echo "   - Security Groups, NACLs"
echo "   - EFS File Systems, S3 Buckets"
echo "   - Route53 DNS records and hosted zone"
echo "   - SSL Certificates"
echo "   - GuardDuty detector"
echo "   - AWS Config recorder and rules"
echo "   - Security Hub configuration and standards"
echo "   - Drift detection Lambda functions and EventBridge rules"
echo "   - WAF Web ACL"
echo "   - CloudWatch logs and alarms"
echo "   - SNS topics and subscriptions"
echo "   - IAM roles and policies"
echo "   - Secrets Manager secrets"
echo "   - EC2 Key Pairs"
echo
echo "💰 COST IMPACT:"
echo "   - Will STOP all hourly charges (~$0.60/hour)"
echo "   - Some storage costs may persist briefly"
echo "   - DNS hosted zone charges may continue until domain transfer"
echo
echo "🚨 SAFETY CHECKS"
echo "   - Terraform state will be preserved"
echo "   - S3 backend bucket will remain (contains state)"
echo "   - This action CANNOT be undone easily"
echo

# Check for dry-run mode
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "🧪 DRY RUN MODE - No resources will be destroyed"
    echo
fi

# First confirmation
if [ "$DRY_RUN" = false ]; then
    read -p "Are you sure you want to DESTROY all UAT resources? (type 'yes' to confirm): " -r
    echo
    if [[ ! $REPLY == "yes" ]]; then
        echo "❌ Cleanup cancelled - type 'yes' to confirm destruction"
        exit 0
    fi

    # Second confirmation with cost impact
    echo "🚨 FINAL CONFIRMATION"
    echo "This will permanently destroy infrastructure that took 45-60 minutes to deploy."
    echo "You will need to run the full UAT deployment again to recreate resources."
    echo
    read -p "Type 'DESTROY' to proceed with resource destruction: " -r
    echo
    if [[ ! $REPLY == "DESTROY" ]]; then
        echo "❌ Cleanup cancelled - type 'DESTROY' to confirm"
        exit 0
    fi
fi

echo
echo "🚀 STARTING UAT CLEANUP"
echo "======================="

# Check AWS credentials
echo "🔍 Validating AWS credentials..."
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "❌ AWS credentials not configured"
    echo "Please configure AWS CLI: aws configure"
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

# Check if UAT deployment state exists
if [ ! -f "uat-enhanced-security.tfvars" ]; then
    echo "⚠️ UAT tfvars file not found, creating from deployment script..."
    # This should exist from the deployment, but create it if missing
    echo "❌ UAT deployment tfvars not found"
    echo "Please run the UAT deployment first, or manually create uat-enhanced-security.tfvars"
    exit 1
fi

# Initialize Terraform with UAT backend
echo "🔧 Initializing Terraform with UAT backend..."
if [ ! -f "backend-uat-enhanced.tf" ]; then
    echo "Creating UAT backend configuration..."
    cat > backend-uat-enhanced.tf << EOF
terraform {
  backend "s3" {
    bucket = "optum-uat-demo-terraform-state"
    key    = "uat-demo/terraform.tfstate"
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

# Show current state
echo "📋 Checking current infrastructure state..."
terraform show 2>/dev/null | head -10

# Generate destroy plan
echo "📋 Generating destruction plan..."
if [ "$DRY_RUN" = true ]; then
    echo "🧪 DRY RUN: Would run: terraform plan -destroy -var-file=uat-enhanced-security.tfvars"
    terraform plan -destroy -var-file=uat-enhanced-security.tfvars
    echo
    echo "✅ DRY RUN COMPLETE"
    echo "=================="
    echo "No resources were destroyed (dry run mode)"
    echo "To actually destroy resources, run without --dry-run flag"
    exit 0
else
    terraform plan -destroy -var-file=uat-enhanced-security.tfvars -out=uat-destroy.tfplan
fi

echo
echo "🎯 READY TO DESTROY UAT INFRASTRUCTURE"
echo "======================================"
echo
echo "⚠️  FINAL WARNING: This will destroy:"
echo "   - All compute resources (EC2 instances, Auto Scaling Groups)"
echo "   - All networking (VPC, subnets, NAT gateways, load balancers)"
echo "   - All storage (EFS, S3 buckets with data)"
echo "   - All security services (GuardDuty, Config, WAF)"
echo "   - All DNS records and SSL certificates"
echo "   - All monitoring and logging"
echo
echo "💰 Cost savings: ~$8-12/hour will stop accruing"
echo
read -p "Execute destruction plan? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Destruction cancelled"
    echo "💡 Destroy plan saved as uat-destroy.tfplan - can be applied later"
    exit 0
fi

# Execute destruction
echo
echo "🧹 DESTROYING UAT INFRASTRUCTURE"
echo "================================"
echo "Started at: $(date)"
echo "This may take 15-30 minutes..."
echo

terraform apply uat-destroy.tfplan

if [ $? -eq 0 ]; then
    echo
    echo "🎉 UAT CLEANUP SUCCESSFUL!"
    echo "========================="
    echo
    echo "✅ RESOURCES DESTROYED:"
    echo "   ✅ All EC2 instances and Auto Scaling Groups"
    echo "   ✅ VPC and all networking components"
    echo "   ✅ Load balancers and target groups"
    echo "   ✅ Security services (GuardDuty, Config, WAF)"
    echo "   ✅ DNS records and SSL certificates"
    echo "   ✅ Storage (EFS, S3 buckets)"
    echo "   ✅ IAM roles and policies"
    echo "   ✅ CloudWatch logs and monitoring"
    echo
    echo "💰 COST IMPACT:"
    echo "   ✅ Hourly charges stopped (~$8-12/hour savings)"
    echo "   ⚠️  S3 backend bucket preserved (contains Terraform state)"
    echo "   ⚠️  Some minimal storage charges may persist briefly"
    echo
    echo "📋 WHAT'S LEFT:"
    echo "   - Terraform state file (in S3 backend)"
    echo "   - AWS credentials and CLI configuration"
    echo "   - Local Terraform configuration files"
    echo
    echo "🔄 TO REDEPLOY:"
    echo "   Run: ./uat-deployment.sh"
    echo "   Full deployment will take 45-60 minutes"
    echo
    echo "✅ UAT environment successfully cleaned up!"
    
else
    echo
    echo "❌ UAT CLEANUP FAILED"
    echo "===================="
    echo "Some resources may not have been destroyed"
    echo "Common issues:"
    echo "1. Resources still in use (dependencies)"
    echo "2. S3 buckets not empty"
    echo "3. ENIs attached to instances"
    echo "4. Security groups still referenced"
    echo
    echo "🆘 MANUAL CLEANUP:"
    echo "1. Check AWS Console for remaining resources"
    echo "2. Delete S3 bucket contents manually"
    echo "3. Retry: terraform destroy -var-file=uat-enhanced-security.tfvars"
    echo "4. Force destroy individual resources if needed"
    echo
    echo "💰 WARNING: Resources may still be accruing charges!"
    echo "Please verify in AWS Console that all resources are destroyed"
    exit 1
fi
