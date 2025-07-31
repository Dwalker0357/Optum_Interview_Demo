# VPC Module Outputs

# VPC
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_arn" {
  description = "The ARN of the VPC"
  value       = aws_vpc.main.arn
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "vpc_owner_id" {
  description = "The ID of the AWS account that owns the VPC"
  value       = aws_vpc.main.owner_id
}

# Internet Gateway
output "igw_id" {
  description = "The ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "igw_arn" {
  description = "The ARN of the Internet Gateway"
  value       = aws_internet_gateway.main.arn
}

# Subnets
output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "public_subnet_ids" {
  description = "List of IDs of public subnets (alias for compatibility)"
  value       = aws_subnet.public[*].id
}

output "public_subnet_arns" {
  description = "List of ARNs of public subnets"
  value       = aws_subnet.public[*].arn
}

output "public_subnets_cidr_blocks" {
  description = "List of cidr_blocks of public subnets"
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = aws_subnet.private[*].id
}

output "private_subnet_ids" {
  description = "List of IDs of private subnets (alias for compatibility)"
  value       = aws_subnet.private[*].id
}

output "private_subnet_arns" {
  description = "List of ARNs of private subnets"
  value       = aws_subnet.private[*].arn
}

output "private_subnets_cidr_blocks" {
  description = "List of cidr_blocks of private subnets"
  value       = aws_subnet.private[*].cidr_block
}

# Database subnet outputs removed - using private subnets for database access
output "database_subnets" {
  description = "List of IDs of database subnets (using private subnets)"
  value       = aws_subnet.private[*].id
}

output "database_subnet_arns" {
  description = "List of ARNs of database subnets (using private subnets)"
  value       = aws_subnet.private[*].arn
}

output "database_subnets_cidr_blocks" {
  description = "List of cidr_blocks of database subnets (using private subnets)"
  value       = aws_subnet.private[*].cidr_block
}

output "database_subnet_group" {
  description = "ID of database subnet group"
  value       = aws_db_subnet_group.main.id
}

output "database_subnet_group_name" {
  description = "Name of database subnet group"
  value       = aws_db_subnet_group.main.name
}

# NAT Gateways
output "nat_ids" {
  description = "List of IDs of the NAT Gateways"
  value       = aws_nat_gateway.main[*].id
}

output "nat_public_ips" {
  description = "List of public Elastic IPs of NAT Gateways"
  value       = aws_eip.nat[*].public_ip
}

output "natgw_ids" {
  description = "List of IDs of the NAT Gateways"
  value       = aws_nat_gateway.main[*].id
}

# Route Tables
output "public_route_table_ids" {
  description = "List of IDs of the public route tables"
  value       = [aws_route_table.public.id]
}

output "private_route_table_ids" {
  description = "List of IDs of the private route tables"
  value       = aws_route_table.private[*].id
}

output "database_route_table_ids" {
  description = "List of IDs of the database route tables (using private route tables)"
  value       = aws_route_table.private[*].id
}

# VPC Endpoints
output "vpc_endpoint_s3_id" {
  description = "The ID of VPC endpoint for S3 (disabled - using NAT Gateway)"
  value       = ""
}

output "vpc_endpoint_ec2_id" {
  description = "The ID of VPC endpoint for EC2"
  value       = try(aws_vpc_endpoint.ec2[0].id, "")
}

output "vpc_endpoint_secretsmanager_id" {
  description = "The ID of VPC endpoint for Secrets Manager"
  value       = try(aws_vpc_endpoint.secretsmanager[0].id, "")
}

output "vpc_endpoints_security_group_id" {
  description = "The ID of the security group for VPC endpoints"
  value       = try(aws_security_group.vpc_endpoints[0].id, "")
}

# Client VPN
output "client_vpn_endpoint_id" {
  description = "The ID of the Client VPN endpoint"
  value       = try(aws_ec2_client_vpn_endpoint.main[0].id, "")
}

output "client_vpn_endpoint_arn" {
  description = "The ARN of the Client VPN endpoint"
  value       = try(aws_ec2_client_vpn_endpoint.main[0].arn, "")
}

output "client_vpn_endpoint_dns_name" {
  description = "The DNS name to be used by clients when establishing their VPN session"
  value       = try(aws_ec2_client_vpn_endpoint.main[0].dns_name, "")
}

# Flow Logs
output "vpc_flow_log_id" {
  description = "The ID of the Flow Log resource"
  value       = try(aws_flow_log.vpc[0].id, "")
}

output "vpc_flow_log_cloudwatch_iam_role_arn" {
  description = "The ARN of the IAM role used when pushing logs to Cloudwatch log group"
  value       = try(aws_iam_role.flow_logs[0].arn, "")
}

# Network ACLs
output "public_network_acl_id" {
  description = "ID of the public network ACL"
  value       = try(aws_network_acl.public[0].id, "")
}

output "public_network_acl_arn" {
  description = "ARN of the public network ACL"
  value       = try(aws_network_acl.public[0].arn, "")
}

output "private_network_acl_id" {
  description = "ID of the private network ACL"
  value       = try(aws_network_acl.private[0].id, "")
}

output "private_network_acl_arn" {
  description = "ARN of the private network ACL"
  value       = try(aws_network_acl.private[0].arn, "")
}

output "database_network_acl_id" {
  description = "ID of the database network ACL (using private network ACL)"
  value       = try(aws_network_acl.private[0].id, "")
}

output "database_network_acl_arn" {
  description = "ARN of the database network ACL (using private network ACL)"
  value       = try(aws_network_acl.private[0].arn, "")
}

# Availability Zones
output "azs" {
  description = "A list of availability zones specified as argument to this module"
  value       = local.azs
}

# General
output "name" {
  description = "The name of the VPC specified as argument to this module"
  value       = var.vpc_name
}

output "tags" {
  description = "A map of tags assigned to the VPC"
  value       = local.common_tags
}
