# Main Terraform configuration for Optum UK AWS Demo

# AWS Secrets Manager secrets for secure credential storage
module "secrets" {
  source = "./modules/secrets"

  project_name = var.project_name
  environment  = var.environment

  secrets = local.secrets

  tags = local.common_tags
}

# VPC infrastructure for each region
module "vpc" {
  source = "./modules/vpc"

  for_each = local.regional_configs

  vpc_name           = "${local.name_prefix}-${each.key}"
  vpc_cidr           = each.value.vpc_cidr
  availability_zones = slice(data.aws_availability_zones.available[each.key].names, 0, each.value.az_count)
  num_azs            = each.value.az_count
  deployment_mode    = var.deployment_mode

  enable_nat_gateway     = each.value.enable_nat
  single_nat_gateway     = var.deployment_mode == "demo" ? true : false
  one_nat_gateway_per_az = var.deployment_mode == "demo" ? false : true

  enable_dns_hostnames = true
  enable_dns_support   = true
  enable_flow_logs     = var.enable_monitoring
  enable_vpc_endpoints = true

  tags = local.common_tags

  depends_on = [module.secrets]
}

# Security groups for all services
module "security_groups" {
  source = "./modules/security"

  for_each = local.regional_configs

  name_prefix          = "${local.name_prefix}-${each.key}"
  vpc_id               = module.vpc[each.key].vpc_id
  vpc_cidr             = each.value.vpc_cidr
  public_subnet_ids    = module.vpc[each.key].public_subnet_ids
  private_subnet_ids   = module.vpc[each.key].private_subnet_ids
  private_subnet_cidrs = [for subnet in module.vpc[each.key].private_subnet_ids : cidrsubnet(each.value.vpc_cidr, 8, index(module.vpc[each.key].private_subnet_ids, subnet) + 10)]

  # Security restrictions
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  allowed_web_cidrs = var.allowed_web_cidrs

  common_tags = local.common_tags

  depends_on = [module.vpc]
}

# IAM roles and policies
module "iam" {
  source = "./modules/iam"

  project_name = var.project_name
  environment  = var.environment
  common_tags  = local.common_tags
  iam_path     = var.iam_path

  # Demo mode configuration
  demo_mode = var.deployment_mode == "demo" ? true : false

  # Secrets Manager configuration
  secrets_manager_secret_arns = [
    "arn:aws:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}-${var.environment}-*"
  ]
}

# Application Load Balancer for external access to internal services
module "alb" {
  source = "./modules/alb"

  for_each = local.regional_configs

  name_prefix = "${local.name_prefix}-${each.key}"
  vpc_id      = module.vpc[each.key].vpc_id
  # Use public subnets for demo mode, private subnets for production
  subnet_ids        = var.deployment_mode == "demo" ? module.vpc[each.key].public_subnet_ids : module.vpc[each.key].private_subnet_ids
  security_group_id = var.use_enhanced_security_groups ? module.security_groups[each.key].enhanced_security_group_ids["alb"] : module.security_groups[each.key].security_group_ids["alb"]
  # Internet-facing for demo mode, internal for production
  internal = var.deployment_mode == "demo" ? false : true

  domain_name     = var.domain_name
  route53_zone_id = var.create_dns_zone ? module.route53[0].zone_id : ""
  zone_id         = var.create_dns_zone ? module.route53[0].zone_id : ""

  # WAF Integration (Security Enhancement)
  enable_waf_association = var.enable_security_enhancements
  waf_web_acl_arn        = var.enable_security_enhancements ? module.waf[each.key].web_acl_arn : null

  common_tags = local.common_tags

  depends_on = [module.vpc, module.security_groups, module.route53]
}

# SSL certificates are created by the ALB module when domain_name is provided

# Route53 DNS for public domain resolution
module "route53" {
  source = "./modules/route53"
  count  = var.create_dns_zone ? 1 : 0

  domain_name  = var.domain_name
  private_zone = false # Public zone for external access

  tags = merge(local.common_tags, {
    Service = "DNS"
  })
}

# DNS records for ALB (created separately to avoid circular dependencies)
resource "aws_route53_record" "alb" {
  for_each = var.create_dns_zone ? local.regional_configs : {}

  zone_id = module.route53[0].zone_id
  name    = each.key == var.primary_region ? var.domain_name : "${each.key}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = module.alb[each.key].alb_dns_name
    zone_id                = module.alb[each.key].alb_zone_id
    evaluate_target_health = true
  }

  depends_on = [module.route53, module.alb]
}

# Wait for Route53 propagation before proceeding with applications
resource "time_sleep" "route53_propagation" {
  count = var.create_dns_zone ? 1 : 0

  create_duration = "120s"

  depends_on = [aws_route53_record.alb]
}

# CNAME records for services
resource "aws_route53_record" "jenkins" {
  for_each = var.create_dns_zone ? local.regional_configs : {}

  zone_id = module.route53[0].zone_id
  name    = each.key == var.primary_region ? "jenkins.${var.domain_name}" : "jenkins.${each.key}.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [each.key == var.primary_region ? var.domain_name : "${each.key}.${var.domain_name}"]

  depends_on = [aws_route53_record.alb]
}

resource "aws_route53_record" "nessus" {
  for_each = var.create_dns_zone ? local.regional_configs : {}

  zone_id = module.route53[0].zone_id
  name    = each.key == var.primary_region ? "nessus.${var.domain_name}" : "nessus.${each.key}.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [each.key == var.primary_region ? var.domain_name : "${each.key}.${var.domain_name}"]

  depends_on = [aws_route53_record.alb]
}

# Bastion hosts in each region
module "bastion" {
  source = "./modules/bastion"

  for_each = local.regional_configs

  name_prefix       = "${local.name_prefix}-${each.key}"
  vpc_id            = module.vpc[each.key].vpc_id
  subnet_ids        = module.vpc[each.key].public_subnet_ids # Use all public subnets for HA
  security_group_id = var.use_enhanced_security_groups ? module.security_groups[each.key].enhanced_security_group_ids["bastion"] : module.security_groups[each.key].security_group_ids["bastion"]
  aws_region        = each.key

  instance_type = local.instance_types.bastion
  key_pair_name = var.key_pair_name
  ami_id        = data.aws_ami.amazon_linux[each.key].id

  # IAM Configuration (from IAM module)
  bastion_instance_profile = module.iam.bastion_instance_profile_name
  bastion_role_arn         = module.iam.bastion_role_arn

  common_tags = local.common_tags

  depends_on = [module.vpc, module.security_groups, module.iam]
}

# Jenkins infrastructure
module "jenkins" {
  source = "./modules/jenkins"

  # Jenkins master only in primary region
  for_each = var.deployment_mode == "demo" ? { (var.primary_region) = local.regional_configs[var.primary_region] } : local.regional_configs

  # Core Configuration
  project         = var.project_name
  environment     = var.environment
  region          = each.key
  deployment_mode = var.deployment_mode

  # Network Configuration
  vpc_id                    = module.vpc[each.key].vpc_id
  private_subnet_ids        = module.vpc[each.key].private_subnet_ids
  public_subnet_ids         = module.vpc[each.key].public_subnet_ids
  alb_security_group_id     = var.use_enhanced_security_groups ? module.security_groups[each.key].enhanced_security_group_ids["alb"] : module.security_groups[each.key].security_group_ids["alb"]
  bastion_security_group_id = var.use_enhanced_security_groups ? module.security_groups[each.key].enhanced_security_group_ids["bastion"] : module.security_groups[each.key].security_group_ids["bastion"]

  # Load balancer
  alb_target_group_arn = module.alb[each.key].target_group_arns["jenkins"]

  # Instance Configuration
  ami_id        = data.aws_ami.amazon_linux[each.key].id
  key_pair_name = var.key_pair_name

  # Agent configuration
  agents_config = {
    min_size         = var.jenkins_agents.min_size
    max_size         = var.jenkins_agents.max_size
    desired_capacity = var.jenkins_agents.desired_capacity
  }

  # IAM Configuration (from IAM module)
  jenkins_master_instance_profile = module.iam.jenkins_master_instance_profile_name
  jenkins_agent_instance_profile  = module.iam.jenkins_agent_instance_profile_name
  jenkins_master_role_arn         = module.iam.jenkins_master_role_arn
  jenkins_agent_role_arn          = module.iam.jenkins_agent_role_arn

  # Secrets
  jenkins_secrets_arn       = module.secrets.secret_arns["jenkins_admin_password"]
  nessus_webhook_secret_arn = module.secrets.secret_arns["api_keys"]

  depends_on = [module.vpc, module.security_groups, module.iam, module.alb, module.secrets, time_sleep.route53_propagation]
}

# Nessus vulnerability scanners
module "nessus" {
  source = "./modules/nessus"

  for_each = local.regional_configs

  # Core Configuration
  project_name = var.project_name
  environment  = var.environment
  aws_region   = each.key

  # Networking
  vpc_id                    = module.vpc[each.key].vpc_id
  private_subnet_ids        = module.vpc[each.key].private_subnet_ids
  public_subnet_ids         = module.vpc[each.key].public_subnet_ids
  bastion_security_group_id = var.use_enhanced_security_groups ? module.security_groups[each.key].enhanced_security_group_ids["bastion"] : module.security_groups[each.key].security_group_ids["bastion"]
  nessus_security_group_id  = var.use_enhanced_security_groups ? module.security_groups[each.key].enhanced_security_group_ids["nessus"] : ""
  internal_lb               = var.deployment_mode == "full" ? true : false

  # Auto Scaling Configuration
  min_capacity     = var.nessus_scanners.min_size
  max_capacity     = var.nessus_scanners.max_size
  desired_capacity = var.nessus_scanners.desired_capacity

  # Instance Configuration
  instance_type = local.instance_types.nessus
  key_pair_name = var.key_pair_name

  # Nessus Configuration
  nessus_activation_code = var.nessus_activation_code

  # Jenkins integration
  jenkins_webhook_url = "https://${var.domain_name}/jenkins/generic-webhook-trigger/invoke"

  # Demo Mode
  demo_mode = var.deployment_mode == "demo"

  # Cost optimization
  enable_spot_instances = local.cost_optimization[var.deployment_mode].use_spot_instances

  # Common tags
  common_tags = merge(local.common_tags, {
    Service = "Nessus"
    Role    = "SecurityScanner"
  })

  depends_on = [module.vpc, module.security_groups, module.iam, module.alb, module.secrets, module.jenkins]
}

# Application servers for testing
module "app_servers" {
  source = "./modules/app-servers"

  for_each = local.regional_configs

  name_prefix       = "${local.name_prefix}-${each.key}"
  vpc_id            = module.vpc[each.key].vpc_id
  subnet_ids        = module.vpc[each.key].private_subnet_ids
  security_group_id = var.use_enhanced_security_groups ? module.security_groups[each.key].enhanced_security_group_ids["app"] : module.security_groups[each.key].security_group_ids["app"]
  aws_region        = each.key

  # Instance configuration
  min_size         = 1
  max_size         = var.deployment_mode == "demo" ? 2 : 3
  desired_capacity = var.deployment_mode == "demo" ? 2 : 3
  instance_type    = local.instance_types.app_server
  ami_id           = data.aws_ami.amazon_linux[each.key].id
  key_pair_name    = var.key_pair_name

  # Load balancer
  target_group_arn = module.alb[each.key].target_group_arns["app_servers"]

  # IAM Configuration (from IAM module)
  app_server_instance_profile = module.iam.app_server_instance_profile_name
  app_server_role_arn         = module.iam.app_server_role_arn

  # Vulnerability testing
  create_vulnerable_s3 = true

  common_tags = merge(local.common_tags, {
    Service = "Application"
    Role    = "WebServer"
  })

  depends_on = [module.vpc, module.security_groups, module.iam, module.alb]
}

# Transit Gateway - Commented out for basic validation

# CloudWatch monitoring - Commented out for basic validation

# Cost optimization - Commented out for basic validation

# SECURITY ENHANCEMENTS - All 6 recommended security improvements

# 1. CloudTrail - API Audit Logging (Critical for Compliance)
module "cloudtrail" {
  source = "./modules/cloudtrail"
  count  = var.enable_monitoring ? 1 : 0

  project_name                   = var.project_name
  environment                    = var.environment
  cloudwatch_log_group_retention = var.deployment_mode == "demo" ? 7 : 90
  enable_log_file_validation     = true
  enable_logging                 = true
  include_global_service_events  = true
  is_multi_region_trail          = length(var.enabled_regions) > 1
  enable_sns_notifications       = var.enable_monitoring

  common_tags = local.common_tags

  depends_on = [module.vpc]
}

# 2. Patch Management - Automated CVE Patching (Critical for Security)
module "patch_management" {
  source = "./modules/patch-management"

  for_each = var.enable_monitoring ? local.regional_configs : {}

  project_name = var.project_name
  environment  = var.environment

  # Patch baseline configuration
  critical_patch_days = var.deployment_mode == "demo" ? 7 : 3
  medium_patch_days   = var.deployment_mode == "demo" ? 30 : 14

  # Maintenance windows
  enable_maintenance_windows  = true
  maintenance_window_schedule = var.deployment_mode == "demo" ? "cron(0 2 ? * SUN *)" : "cron(0 2 ? * SAT *)"

  common_tags = local.common_tags

  depends_on = [module.vpc, module.iam]
}

# 3. GuardDuty - Advanced Threat Detection (Zero Risk - Pure Addition)
module "guardduty" {
  source = "./modules/guardduty"

  for_each = var.enable_security_enhancements ? local.regional_configs : {}

  project_name = var.project_name
  environment  = var.environment
  common_tags  = local.common_tags

  # GuardDuty Configuration
  finding_publishing_frequency = var.deployment_mode == "demo" ? "SIX_HOURS" : "FIFTEEN_MINUTES"
  enable_s3_protection         = true
  enable_kubernetes_protection = false
  enable_malware_protection    = var.deployment_mode == "demo" ? false : true
  log_retention_days           = var.deployment_mode == "demo" ? 30 : 90
  enable_auto_response         = var.deployment_mode == "demo" ? false : true

  depends_on = [module.vpc, module.secrets]
}

# 4. AWS Config - Continuous Compliance Monitoring (Low Risk - Monitoring Only)
module "config" {
  source = "./modules/config"

  for_each = var.enable_security_enhancements ? local.regional_configs : {}

  project_name = var.project_name
  environment  = var.environment
  common_tags  = local.common_tags

  # Config Configuration
  force_destroy_config_bucket = var.deployment_mode == "demo" ? true : false
  include_global_resources    = each.key == var.primary_region ? true : false
  delivery_frequency          = var.deployment_mode == "demo" ? "TwentyFour_Hours" : "Six_Hours"

  depends_on = [module.vpc, module.iam]
}

# 5. WAF - Web Application Firewall (Medium Risk - Requires ALB Integration)
module "waf" {
  source = "./modules/waf"

  for_each = var.enable_security_enhancements ? local.regional_configs : {}

  project_name = var.project_name
  environment  = var.environment
  region       = each.key
  common_tags  = local.common_tags

  # WAF Configuration
  enable_geo_blocking  = var.deployment_mode == "demo" ? false : true
  blocked_countries    = var.deployment_mode == "demo" ? [] : ["CN", "RU", "KP"]
  rate_limit           = var.deployment_mode == "demo" ? 5000 : 2000
  allowed_ip_addresses = var.allowed_web_cidrs
  log_retention_days   = var.deployment_mode == "demo" ? 7 : 30
  block_threshold      = var.deployment_mode == "demo" ? 500 : 100

  depends_on = [module.vpc, module.security_groups]
}
