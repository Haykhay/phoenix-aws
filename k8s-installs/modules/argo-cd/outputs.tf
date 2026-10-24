output "url" {
  value = local.config.enabled ? "https://${local.hostname}" : null
}

output "repo_public_key" {
  description = "Add to the GitHub repository (spec.repo_url) as a read-only deploy key."
  value       = try(tls_private_key.repo[0].public_key_openssh, null)
}

output "admin_secret" {
  description = "Secrets Manager secret holding the local admin password."
  value       = try(aws_secretsmanager_secret.admin[0].name, null)
}

output "resource_summary" {
  value = {
    environment   = local.environment
    region        = local.region
    cluster       = local.cluster_key
    resource_set  = "argo-cd"
    chart_version = try(helm_release.this[0].version, null)
    role_arn      = try(aws_iam_role.repo_server[0].arn, null)
  }
}
