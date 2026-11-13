output "cluster_name" {
  description = "EKS cluster name."
  value       = local.cluster_name
}

output "cluster_endpoint" {
  description = "API endpoint; a placeholder when core-platform has no such cluster (the plan then fails)."
  value       = try(local.cluster.cluster_endpoint, "https://cluster-missing.invalid")
}

output "cluster_ca_data" {
  description = "Base64 certificate authority data."
  value       = try(local.cluster.cluster_certificate_authority_data, "")
}

output "cluster_kms_key_arn" {
  description = "The cluster's KMS key."
  value       = try(local.cluster.cluster_kms_key_arn, null)
}

output "vpc_id" {
  description = "The cluster's VPC."
  value       = try(local.cluster.vpc_id, null)
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
  description = "Node security group ID."
  value       = try(local.cluster.node_security_group_id, null)
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


output "exec" {
  description = "Kubernetes/Helm provider exec block: a fresh token per call, signed with the job's own credentials (Terraform-Role or Terraform-Plan-Role)."
  value = {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", var.region, "--output", "json"]
  }
}
