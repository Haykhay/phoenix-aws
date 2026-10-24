output "cluster_name" {
  value = local.cluster_name
}

output "cluster_endpoint" {
  value = try(local.cluster.cluster_endpoint, "https://cluster-missing.invalid")
}

output "cluster_ca_data" {
  description = "Base64 certificate authority data."
  value       = try(local.cluster.cluster_certificate_authority_data, "")
}

output "cluster_kms_key_arn" {
  value = try(local.cluster.cluster_kms_key_arn, null)
}

output "vpc_id" {
  value = try(local.cluster.vpc_id, null)
}

output "node_subnet_ids" {
  description = "Subnets the cluster's nodes run in."
  value       = try(local.cluster.node_subnet_ids, [])
}

output "cluster_security_group_id" {
  description = "The EKS cluster security group (guards the API endpoint)."
  value       = try(local.cluster.cluster_security_group_id, null)
}

output "node_security_group_id" {
  value = try(local.cluster.node_security_group_id, null)
}

output "karpenter" {
  description = "core-platform's Karpenter facts for this cluster, or null when it is not enabled."
  value       = try(local.cluster.karpenter, null)
}

output "dns" {
  description = "public/internal zone id and name of the cluster's zone, or null when the environment has none."
  value       = local.dns
}

output "dns_zones" {
  description = "Every hosted zone pair of the environment, keyed by name (dns unit's zones), or {}."
  value       = try(data.terraform_remote_state.dns.outputs.zones, {})
}

