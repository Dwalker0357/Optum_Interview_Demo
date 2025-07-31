# Transit Gateway Module
# Provides multi-region VPC connectivity

resource "aws_ec2_transit_gateway" "main" {
  description                     = "Transit Gateway for ${var.name_prefix}"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-tgw"
  })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "main" {
  for_each = var.vpc_attachments

  subnet_ids         = each.value.subnet_ids
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = each.value.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-tgw-attachment-${each.key}"
  })
}

resource "aws_ec2_transit_gateway_route_table" "main" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-tgw-rt"
  })
}
