output "attachment_id" {
  description = "Peering attachment ID (the same on both sides)."
  value       = aws_ec2_transit_gateway_peering_attachment.this.id
}

output "routes" {
  description = "Static routes per side: { local|peer = [\"<table>/<cidr>\", ...] }."
  value       = { for side, r in local.routes : side => keys(r) }
}
