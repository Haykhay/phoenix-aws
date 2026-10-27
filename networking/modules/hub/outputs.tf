output "dns_vpc_id" {
  description = "Hub DNS VPC; the dns unit associates internal zones with it."
  value       = module.dns_vpc.vpc_id
}

output "dns_vpc_region" {
  description = "Region of the hub DNS VPC."
  value       = local.region
}

output "inbound_endpoint_ips" {
  description = "Addresses on-prem forwards the platform's zones to."
  value       = flatten([for e in aws_route53_resolver_endpoint.inbound : [for a in e.ip_address : a.ip]])
}

output "resolver_rule_ids" {
  description = "Forwarding rule per on-prem domain: { <domain> = <rule id> }."
  value       = { for d, r in aws_route53_resolver_rule.forward : d => r.id }
}
