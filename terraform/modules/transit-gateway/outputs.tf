output "transit_gateway_id" {
  description = "ID of the Transit Gateway"
  value       = aws_ec2_transit_gateway.main.id
}

output "route_table_id" {
  description = "ID of the Transit Gateway route table"
  value       = aws_ec2_transit_gateway_route_table.main.id
}

output "vpc_attachments" {
  description = "Transit Gateway VPC attachment IDs"
  value = {
    for k, v in aws_ec2_transit_gateway_vpc_attachment.main : k => v.id
  }
}
