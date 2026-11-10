output "claim_name" {
  description = "PersistentVolumeClaim name, in the namespace below."
  value       = local.instance
}

output "namespace" {
  description = "Namespace the claim lives in."
  value       = local.config.namespace
}

output "resource_summary" {
  value = {
    environment   = local.environment
    region        = local.region
    cluster       = local.cluster_key
    resource_set  = "volume"
    claim         = local.instance
    storage_class = local.config.storage_class
    size_gib      = local.size
  }
}
