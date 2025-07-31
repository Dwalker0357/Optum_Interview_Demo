#!/bin/bash

echo "🧪 UAT STAGED DEPLOYMENT - Step-by-step with dependency management"
echo "=================================================================="
echo
echo "This deployment breaks down the infrastructure into stages to avoid dependency conflicts:"
echo "1. Secrets & VPC foundation"
echo "2. Security groups & IAM"
echo "3. Route53 (optional)"
echo "4. ALB & WAF"
echo "5. Compute resources (Jenkins, Nessus, Apps)"
echo "6. Security services (GuardDuty, Config, CloudTrail, Drift Detection, Security Hub)"
echo

# Check for dry-run mode
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "🧪 DRY RUN MODE - Will show what would be deployed"
    echo
fi

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

# Check/Create S3 backend bucket
if ! aws s3 ls s3://optum-uat-demo-terraform-state >/dev/null 2>&1; then
    echo "Creating S3 backend bucket for UAT staged deployment..."
    aws s3 mb s3://optum-uat-demo-terraform-state --region eu-west-1
    aws s3api put-bucket-versioning --bucket optum-uat-demo-terraform-state --versioning-configuration Status=Enabled
    echo "✅ S3 backend bucket created"
fi

# Check/Create DynamoDB lock table
if ! aws dynamodb describe-table --table-name optum-uat-demo-tf-locks --region eu-west-1 >/dev/null 2>&1; then
    echo "Creating DynamoDB lock table for UAT state locking..."
    aws dynamodb create-table \
        --table-name optum-uat-demo-tf-locks \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region eu-west-1
    echo "✅ DynamoDB lock table created"
fi

# Create UAT configuration file if it doesn't exist
if [ ! -f "uat-enhanced-security.tfvars" ]; then
    echo "Creating UAT configuration file..."
    cat > uat-enhanced-security.tfvars << 'EOF'
# Enhanced Security UAT Demo Infrastructure Configuration
deployment_mode = "demo"
project_name    = "optum"
environment     = "demo"
owner          = "example@gmail.com"
iam_path       = "/"

# SECURITY ENHANCEMENTS - Enable all 4 enhancements
enable_security_enhancements = true
use_enhanced_security_groups = true

# Regional Configuration - Single region for demo
primary_region    = "eu-west-1"
enabled_regions   = ["eu-west-1"]

# Network Configuration - HA across 2 AZs
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
domain_name      = "optum-demo.com"

# Service Configuration
enable_monitoring = true

# Email Configuration
demo_email_address = "example@gmail.com"
alert_email_addresses = ["example@gmail.com"]

# Jenkins Configuration
jenkins_agents = {
  min_size         = 1
  max_size         = 3
  desired_capacity = 2
}

# Nessus Configuration
nessus_scanners = {
  min_size         = 1
  max_size         = 3
  desired_capacity = 2
}

# Application Servers
app_servers = {
  count            = 2
  instance_type    = "t3.micro"
  min_size         = 1
  max_size         = 2
  desired_capacity = 2
}

# Instance Configuration
key_pair_name = "optum-demo-key"
nessus_license_key = "DEMO-NESSUS-LICENSE-KEY"

# Feature Flags
enable_transit_gateway = false
enable_multi_region   = false

# Demo-specific Configuration
enable_demo_mode = true
demo_duration_hours = 6
enable_cost_alerts = true
daily_budget_limit = 80
enable_detailed_monitoring = true
enable_vulnerability_testing = true
create_intentional_vulns = true

# New Features (Weekend Implementation)
enable_drift_detection = true
enable_security_hub = false  # Disabled by default for cost control
enable_guardduty = false     # Disabled by default for cost control

# Common Tags
common_tags = {
  Environment   = "demo"
  Project       = "optum-interview"
  Owner         = "example@gmail.com"
  Purpose       = "enhanced-security-demo"
  AutoCleanup   = "6hours"
  Email         = "example@gmail.com"
  SecurityLevel = "enhanced"
}
EOF
fi

# Initialize Terraform with UAT backend
echo "🔧 Initializing Terraform with UAT backend..."
cat > backend-uat-enhanced.tf << EOF
terraform {
  backend "s3" {
    bucket         = "optum-uat-demo-terraform-state"
    key            = "uat-demo/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "optum-uat-demo-tf-locks"
    encrypt        = true
  }
}
EOF

terraform init -reconfigure

if [ "$DRY_RUN" = true ]; then
    echo "🧪 DRY RUN: Validating configuration and showing what would be deployed..."
    terraform validate
    terraform plan -var-file=uat-enhanced-security.tfvars
    echo
    echo "✅ DRY RUN COMPLETE - Configuration is valid"
    echo "To deploy, run without --dry-run flag"
    exit 0
fi

# Create key pair if it doesn't exist
KEY_PAIR_NAME="optum-demo-key"
echo "🔑 Checking for key pair: $KEY_PAIR_NAME"
if ! aws ec2 describe-key-pairs --key-names "$KEY_PAIR_NAME" >/dev/null 2>&1; then
    echo "🔑 Creating new key pair: $KEY_PAIR_NAME"
    aws ec2 create-key-pair --key-name "$KEY_PAIR_NAME" --output text --query 'KeyMaterial' > "$KEY_PAIR_NAME.pem"
    chmod 400 "$KEY_PAIR_NAME.pem"
    echo "✅ Key pair created and saved to $KEY_PAIR_NAME.pem"
else
    echo "✅ Key pair already exists: $KEY_PAIR_NAME"
fi

echo
echo "🚀 STARTING STAGED UAT DEPLOYMENT"
echo "================================="
echo "⏱️ Estimated total time: 45-60 minutes"
echo "💰 Estimated cost: ~$0.60/hour (~$415/month) - See README for details"
echo

read -p "Proceed with staged UAT deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Deployment cancelled"
    exit 0
fi

echo
echo "📋 STAGE 1: Foundation (Secrets, VPC, IAM)"
echo "==========================================="
echo "Deploying core infrastructure components..."

terraform apply -var-file=uat-enhanced-security.tfvars \
  -target=module.secrets \
  -target=module.vpc \
  -target=module.iam \
  -auto-approve

if [ $? -ne 0 ]; then
    echo "❌ Stage 1 failed"
    exit 1
fi

echo "✅ Stage 1 complete"
echo

echo "📋 STAGE 2: Security Groups & Networking"
echo "========================================"
echo "Deploying security groups and network security..."

terraform apply -var-file=uat-enhanced-security.tfvars \
  -target=module.security_groups \
  -auto-approve

if [ $? -ne 0 ]; then
    echo "❌ Stage 2 failed"
    exit 1
fi

echo "✅ Stage 2 complete"
echo

echo "📋 STAGE 3: DNS & SSL (Optional)"
echo "================================"
echo "Deploying Route53 and SSL certificates..."

terraform apply -var-file=uat-enhanced-security.tfvars \
  -target=module.route53 \
  -target=time_sleep.route53_propagation \
  -auto-approve

if [ $? -ne 0 ]; then
    echo "❌ Stage 3 failed"
    exit 1
fi

echo "✅ Stage 3 complete"
echo

echo "📋 STAGE 4: Load Balancer & WAF"
echo "==============================="
echo "Deploying Application Load Balancer and Web Application Firewall..."

terraform apply -var-file=uat-enhanced-security.tfvars \
  -target=module.alb \
  -target=module.waf \
  -auto-approve

if [ $? -ne 0 ]; then
    echo "❌ Stage 4 failed"
    exit 1
fi

echo "✅ Stage 4 complete"
echo

echo "📋 STAGE 5: Compute Resources"
echo "============================="
echo "Deploying Bastion, Jenkins, Nessus, and Application servers..."

terraform apply -var-file=uat-enhanced-security.tfvars \
  -target=module.bastion \
  -target=module.jenkins \
  -target=module.nessus \
  -target=module.app_servers \
  -auto-approve

if [ $? -ne 0 ]; then
    echo "❌ Stage 5 failed"
    exit 1
fi

echo "✅ Stage 5 complete"
echo

echo "📋 STAGE 6: Security Services & Automation"
echo "=========================================="
echo "Deploying GuardDuty, Config, CloudTrail, Patch Management, Drift Detection, and Security Hub..."

terraform apply -var-file=uat-enhanced-security.tfvars \
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

echo "✅ Stage 6 complete"
echo

echo "📋 FINAL STAGE: Complete Deployment"
echo "==================================="
echo "Running final terraform apply to ensure all resources are properly configured..."

terraform apply -var-file=uat-enhanced-security.tfvars -auto-approve

if [ $? -eq 0 ]; then
    echo
    echo "🎉 UAT STAGED DEPLOYMENT SUCCESSFUL!"
    echo "===================================="
    echo
    echo "✅ All stages completed successfully"
    echo "✅ Enhanced security features enabled"
    echo "✅ Infrastructure ready for demo"
    echo
    echo "🌐 ACCESS INFORMATION:"
    terraform output
    echo
    echo "📧 Email alerts configured for: example@gmail.com"
    echo "💰 Current cost: ~$0.60/hour (~$415/month)"
    echo "🧹 Auto-cleanup after 6 hours"
    echo
    echo "🎬 UAT ENVIRONMENT READY FOR DEMO!"
else
    echo
    echo "❌ Final deployment stage failed"
    echo "Some resources may be in an inconsistent state"
    echo "Check the Terraform output above for details"
    exit 1
fi