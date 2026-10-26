output "mode" {
  description = "management or spoke."
  value       = local.config.enabled ? local.mode : null
}

output "shard" {
  description = "This cluster's shard name (<env_id>-<cluster>)."
  value       = local.shard
}

output "remote_kubeconfig_secret" {
  description = "Management only: Secrets Manager secret with the kubeconfig spokes use. Spokes read this from this unit's state."
  value       = try(aws_secretsmanager_secret.remote_kubeconfig[0].name, null)
}

output "url" {
  description = "Kargo UI; management cluster only."
  value       = local.is_management ? "https://${local.api_host}" : null
}

output "resource_summary" {
  value = {
    environment   = local.environment
    region        = local.region
    cluster       = local.cluster_key
    resource_set  = "kargo"
    mode          = local.mode
    chart_version = local.config.chart_version
  }
}
