#!/bin/bash

# Terraform Deployment Validation Script
# Validates critical issues before deployment to prevent failures

echo "🔍 TERRAFORM DEPLOYMENT VALIDATION"
echo "=================================="
echo

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

echo "1. Checking AWS credentials and permissions..."
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo -e "${RED}❌ ERROR: AWS credentials not configured${NC}"
    ((ERRORS++))
else
    echo -e "${GREEN}✅ AWS credentials configured${NC}"
fi

echo
echo "2. Checking AWS service permissions..."

# Check VPC endpoint limits
CURRENT_ENDPOINTS=$(aws ec2 describe-vpc-endpoints --query 'length(VpcEndpoints[?State==`available`])' --output text 2>/dev/null || echo "0")
if [ "$CURRENT_ENDPOINTS" -gt 40 ]; then
    echo -e "${RED}❌ ERROR: Too many VPC endpoints exist ($CURRENT_ENDPOINTS/50). Risk of hitting AWS limit.${NC}"
    ((ERRORS++))
elif [ "$CURRENT_ENDPOINTS" -gt 30 ]; then
    echo -e "${YELLOW}⚠️  WARNING: High number of VPC endpoints ($CURRENT_ENDPOINTS/50). Monitor closely.${NC}"
    ((WARNINGS++))
else
    echo -e "${GREEN}✅ VPC endpoint count OK ($CURRENT_ENDPOINTS/50)${NC}"
fi

# Check Route53 permissions
if ! aws route53 list-hosted-zones >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  WARNING: Limited Route53 permissions. Certificate validation may fail.${NC}"
    ((WARNINGS++))
else
    echo -e "${GREEN}✅ Route53 permissions OK${NC}"
fi

# Check WAF permissions
if ! aws wafv2 list-web-acls --scope=REGIONAL >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  WARNING: Limited WAF permissions. WAF module may fail.${NC}"
    ((WARNINGS++))
else
    echo -e "${GREEN}✅ WAF permissions OK${NC}"
fi

echo
echo "3. Checking terraform configuration..."

# Check if terraform is initialized
if [ ! -d ".terraform" ]; then
    echo -e "${RED}❌ ERROR: Terraform not initialized. Run 'terraform init' first.${NC}"
    ((ERRORS++))
else
    echo -e "${GREEN}✅ Terraform initialized${NC}"
fi

# Validate terraform syntax
if terraform validate >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Terraform syntax valid${NC}"
else
    echo -e "${RED}❌ ERROR: Terraform validation failed${NC}"
    terraform validate
    ((ERRORS++))
fi

echo
echo "4. Checking for common deployment blockers..."

# Check for missing secrets module
if [ ! -d "modules/secrets" ]; then
    echo -e "${RED}❌ ERROR: Secrets module missing. This will cause deployment failure.${NC}"
    ((ERRORS++))
else
    echo -e "${GREEN}✅ Secrets module exists${NC}"
fi

# Check for certificate validation configuration
if grep -q "aws_acm_certificate_validation" modules/alb/main.tf; then
    echo -e "${GREEN}✅ Certificate validation properly configured${NC}"
else
    echo -e "${YELLOW}⚠️  WARNING: Certificate validation may not be configured properly${NC}"
    ((WARNINGS++))
fi

# Check for WAF naming conflicts
if grep -q "web-acl.*region.*environment" modules/waf/main.tf; then
    echo -e "${GREEN}✅ WAF resources use unique naming${NC}"
else
    echo -e "${YELLOW}⚠️  WARNING: WAF resources may have naming conflicts${NC}"
    ((WARNINGS++))
fi

echo
echo "5. Checking deployment variables..."

# Check if tfvars file exists
if [ -f "uat-enhanced-security.tfvars" ]; then
    echo -e "${GREEN}✅ UAT variables file exists${NC}"
    
    # Check critical variables
    if grep -q "domain_name.*=" uat-enhanced-security.tfvars; then
        DOMAIN=$(grep "domain_name" uat-enhanced-security.tfvars | cut -d'"' -f2)
        echo -e "${GREEN}✅ Domain configured: $DOMAIN${NC}"
    else
        echo -e "${YELLOW}⚠️  WARNING: No domain configured. HTTPS will be disabled.${NC}"
        ((WARNINGS++))
    fi
    
    if grep -q "enable_security_enhancements.*=.*true" uat-enhanced-security.tfvars; then
        echo -e "${GREEN}✅ Security enhancements enabled${NC}"
    else
        echo -e "${YELLOW}⚠️  WARNING: Security enhancements disabled${NC}"
        ((WARNINGS++))
    fi
else
    echo -e "${RED}❌ ERROR: UAT variables file not found${NC}"
    ((ERRORS++))
fi

echo
echo "6. Estimating deployment time..."

ESTIMATED_TIME="45-60"
if [ "$CURRENT_ENDPOINTS" -gt 30 ]; then
    ESTIMATED_TIME="60-90"
fi

echo -e "${GREEN}⏱️  Estimated deployment time: $ESTIMATED_TIME minutes${NC}"

echo
echo "📋 VALIDATION SUMMARY"
echo "===================="

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}🎉 PERFECT! No issues found. Ready for deployment.${NC}"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠️  $WARNINGS warnings found. Deployment should succeed but monitor closely.${NC}"
    echo
    echo "Proceed with deployment? (y/N)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        exit 0
    else
        exit 1
    fi
else
    echo -e "${RED}❌ $ERRORS critical errors found. Fix before deployment.${NC}"
    if [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Also $WARNINGS warnings that should be addressed.${NC}"
    fi
    echo
    echo "RECOMMENDED ACTIONS:"
    echo "1. Fix all critical errors listed above"
    echo "2. Address warnings to improve deployment reliability"
    echo "3. Re-run this validation script"
    echo "4. Consider deploying in stages (VPC first, then apps)"
    exit 1
fi
