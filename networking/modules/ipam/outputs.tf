output "ipam_id" {
  description = "IPAM ID."
  value       = aws_vpc_ipam.this.id
}

output "segments" {
  description = "Segment blocks: { production, non-production, shared }."
  value       = local.segments
}

output "regional_blocks" {
  description = "Each joined region's block per segment: { <region> = { <segment> = <cidr> } }."
  value = {
    for region in local.regions : region => {
      for segment in keys(local.segments) : segment => aws_vpc_ipam_pool_cidr.regional["${region}/${segment}"].cidr
    }
  }
}

output "regional_pool_ids" {
  description = "Each joined region's pool per segment: { <region> = { <segment> = <pool id> } }."
  value = {
    for region in local.regions : region => {
      for segment in keys(local.segments) : segment => aws_vpc_ipam_pool.regional["${region}/${segment}"].id
    }
  }
}
