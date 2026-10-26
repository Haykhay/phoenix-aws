output "transit_gateway_id" {
  description = "This region's transit gateway."
  value       = aws_ec2_transit_gateway.this.id
}

output "transit_gateway_arn" {
  description = "Transit gateway ARN."
  value       = aws_ec2_transit_gateway.this.arn
}

output "amazon_side_asn" {
  description = "Transit gateway BGP ASN."
  value       = aws_ec2_transit_gateway.this.amazon_side_asn
}

output "route_table_ids" {
  description = "Route table per segment: { production, non-production, shared }."
  value       = { for k, t in aws_ec2_transit_gateway_route_table.this : k => t.id }
}

output "blocks" {
  description = "This region's block per segment (from ipam)."
  value       = local.blocks
}

output "pool_ids" {
  description = "This region's IPAM pool per segment (from ipam)."
  value       = local.pool_ids
}

output "egress_mode" {
  description = "central or independent."
  value       = local.network.egress_mode
}

output "egress_attachment_id" {
  description = "Central egress VPC attachment; null in independent mode."
  value       = try(aws_ec2_transit_gateway_vpc_attachment.egress[0].id, null)
}
