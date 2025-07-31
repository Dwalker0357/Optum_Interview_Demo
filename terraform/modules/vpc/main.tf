# VPC Module Main Configuration

locals {
  # Use provided AZs or take first N from available AZs
  azs = length(var.availability_zones) > 0 ? slice(var.availability_zones, 0, var.num_azs) : slice(data.aws_availability_zones.available.names, 0, var.num_azs)

  # Common tags
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project
    Module      = "vpc"
    ManagedBy   = "terraform"
  })

  # Calculate subnet CIDRs
  vpc_cidr_block  = var.vpc_cidr
  newbits_public  = 8 # /24 subnets from /16 VPC
  newbits_private = 8 # /24 subnets from /16 VPC
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  tags = merge(local.common_tags, {
    Name = var.vpc_name
    Type = "vpc"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-igw"
    Type = "internet-gateway"
  })
}

# Public Subnets - 2 public subnets for HA redundancy
resource "aws_subnet" "public" {
  count = 2 # 2 public subnets for HA (one per AZ)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(local.vpc_cidr_block, local.newbits_public, count.index)
  availability_zone       = local.azs[count.index] # Use first 2 AZs for public subnets
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-public-${count.index + 1}"
    Type = "public"
    AZ   = local.azs[count.index]
  })
}

# Private Subnets - Exactly 2 private subnets per region as required
resource "aws_subnet" "private" {
  count = 2 # Fixed to exactly 2 private subnets per region

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(local.vpc_cidr_block, local.newbits_private, count.index + length(local.azs))
  availability_zone = local.azs[count.index % length(local.azs)]

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-private-${count.index + 1}"
    Type = "private"
    AZ   = local.azs[count.index % length(local.azs)]
  })
}

# Database Subnets - REMOVED: Using private subnets for database access instead

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : (var.one_nat_gateway_per_az ? length(local.azs) : 1)) : 0

  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-nat-eip-${count.index + 1}"
    Type = "nat-eip"
  })
}

# NAT Gateways
resource "aws_nat_gateway" "main" {
  count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : (var.one_nat_gateway_per_az ? length(local.azs) : 1)) : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[var.single_nat_gateway ? 0 : count.index].id

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-nat-${var.single_nat_gateway ? "single" : local.azs[count.index]}"
    Type = "nat-gateway"
  })

  depends_on = [aws_internet_gateway.main]
}

# Route Tables - Public
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-public-rt"
    Type = "public-route-table"
  })
}

# Route Tables - Private
resource "aws_route_table" "private" {
  count = var.enable_nat_gateway ? length(local.azs) : 1

  vpc_id = aws_vpc.main.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.main[0].id : aws_nat_gateway.main[count.index].id
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-private-rt-${var.enable_nat_gateway ? local.azs[count.index] : "main"}"
    Type = "private-route-table"
  })
}

# Route Tables - Database - REMOVED: Using private route tables for database access

# Route Table Associations - Public
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route Table Associations - Private
resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = var.enable_nat_gateway ? aws_route_table.private[count.index].id : aws_route_table.private[0].id
}

# Route Table Associations - Database - REMOVED

# Database Subnet Group - Updated to use private subnets
resource "aws_db_subnet_group" "main" {
  name       = "${var.vpc_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-db-subnet-group"
    Type = "db-subnet-group"
  })
}

# VPC Flow Logs
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/flowlogs/${var.vpc_name}"
  retention_in_days = var.flow_logs_retention_days

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-flow-logs"
    Type = "cloudwatch-log-group"
  })
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name               = "${var.vpc_name}-flow-logs-role"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume_role[0].json

  tags = local.common_tags
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name   = "${var.vpc_name}-flow-logs-policy"
  role   = aws_iam_role.flow_logs[0].id
  policy = data.aws_iam_policy_document.flow_logs_policy[0].json
}

resource "aws_flow_log" "vpc" {
  count = var.enable_flow_logs ? 1 : 0

  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-flow-logs"
    Type = "vpc-flow-log"
  })
}

# VPC Endpoints
# S3 VPC endpoint removed - NAT Gateway already provides S3 access
# resource "aws_vpc_endpoint" "s3" {
#   count = var.enable_vpc_endpoints && contains(var.vpc_endpoints_services, "s3") ? 1 : 0
#
#   vpc_id            = aws_vpc.main.id
#   service_name      = data.aws_vpc_endpoint_service.s3[0].service_name
#   vpc_endpoint_type = "Gateway"
#   route_table_ids   = concat(aws_route_table.private[*].id, [aws_route_table.public.id])
#
#   tags = merge(local.common_tags, {
#     Name = "${var.vpc_name}-s3-endpoint"
#     Type = "vpc-endpoint"
#   })
# }

resource "aws_security_group" "vpc_endpoints" {
  count = var.enable_vpc_endpoints ? 1 : 0

  name_prefix = "${var.vpc_name}-vpc-endpoints-"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-vpc-endpoints-sg"
    Type = "security-group"
  })
}

resource "aws_vpc_endpoint" "ec2" {
  count = var.enable_vpc_endpoints && contains(var.vpc_endpoints_services, "ec2") ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = data.aws_vpc_endpoint_service.ec2[0].service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  depends_on = [aws_subnet.private]

  timeouts {
    create = "20m"
    delete = "10m"
  }

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-ec2-endpoint"
    Type = "vpc-endpoint"
  })
}

resource "aws_vpc_endpoint" "secretsmanager" {
  count = var.enable_vpc_endpoints && contains(var.vpc_endpoints_services, "secretsmanager") ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = data.aws_vpc_endpoint_service.secretsmanager[0].service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  depends_on = [aws_subnet.private]

  timeouts {
    create = "20m"
    delete = "10m"
  }

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-secretsmanager-endpoint"
    Type = "vpc-endpoint"
  })
}

# Client VPN Endpoint
resource "aws_security_group" "client_vpn" {
  count = var.enable_client_vpn ? 1 : 0

  name_prefix = "${var.vpc_name}-client-vpn-"
  description = "Security group for Client VPN"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.enable_client_vpn ? ["203.45.67.89/32"] : []
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-client-vpn-sg"
    Type = "security-group"
  })
}

resource "aws_ec2_client_vpn_endpoint" "main" {
  count = var.enable_client_vpn && var.client_vpn_server_certificate_arn != "" ? 1 : 0

  description            = "${var.vpc_name} Client VPN endpoint"
  server_certificate_arn = var.client_vpn_server_certificate_arn
  client_cidr_block      = var.client_vpn_cidr
  vpc_id                 = aws_vpc.main.id
  security_group_ids     = [aws_security_group.client_vpn[0].id]

  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = var.client_vpn_client_certificate_arn
  }

  connection_log_options {
    enabled = false
  }

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-client-vpn"
    Type = "client-vpn-endpoint"
  })
}

# Network ACLs
resource "aws_network_acl" "public" {
  count = var.enable_network_acls ? 1 : 0

  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.public[*].id

  # Allow inbound HTTP from testing IP only
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "203.45.67.89/32"
    from_port  = 80
    to_port    = 80
  }

  # Allow inbound HTTPS from testing IP only
  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "203.45.67.89/32"
    from_port  = 443
    to_port    = 443
  }

  # Allow inbound SSH from testing IP only
  ingress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = "203.45.67.89/32"
    from_port  = 22
    to_port    = 22
  }

  # Allow inbound ephemeral ports from testing IP only
  ingress {
    protocol   = "tcp"
    rule_no    = 130
    action     = "allow"
    cidr_block = "203.45.67.89/32"
    from_port  = 1024
    to_port    = 65535
  }

  # Allow traffic from VPC CIDR (needed for NAT Gateway functionality)
  ingress {
    protocol   = "-1"
    rule_no    = 140
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }

  # Allow return traffic for established connections (ephemeral ports)
  ingress {
    protocol   = "tcp"
    rule_no    = 150
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }



  # Allow all outbound
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-public-nacl"
    Type = "network-acl"
  })
}

resource "aws_network_acl" "private" {
  count = var.enable_network_acls ? 1 : 0

  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.private[*].id

  # Allow inbound from VPC
  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }

  # Allow inbound ephemeral ports from testing IP only
  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "203.45.67.89/32"
    from_port  = 1024
    to_port    = 65535
  }

  # Allow TCP return traffic for HTTPS connections (e.g., GitHub, package downloads)
  ingress {
    protocol   = "tcp"
    rule_no    = 111
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Allow UDP return traffic for DNS and other services
  ingress {
    protocol   = "udp"
    rule_no    = 115
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Allow DNS responses explicitly
  ingress {
    protocol   = "udp"
    rule_no    = 112
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 53
    to_port    = 53
  }

  # Allow DNS responses over TCP
  ingress {
    protocol   = "tcp"
    rule_no    = 113
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 53
    to_port    = 53
  }

  # Allow all outbound
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-private-nacl"
    Type = "network-acl"
  })
}

# Database Network ACL - REMOVED: Using private subnet security for database access
