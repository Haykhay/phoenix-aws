output "cache_prefix" {
  value = local.cache_prefix
}

output "registry_url_prefix" {
  description = "Image references start with this: <registry_url_prefix>/<repo>:<tag>."
  value       = "${local.account_id}.dkr.ecr.${local.region}.amazonaws.com/${local.cache_prefix}"
}

output "pull_through_role_arn" {
  description = "Role ECR assumes to pull from the hub; the hub's registry policy must allow it."
  value       = local.role_arn
}

output "node_pull_policy_arn" {
  description = "Attach to node roles (core-platform node_role_additional_policies)."
  value       = aws_iam_policy.node_pull.arn
}
