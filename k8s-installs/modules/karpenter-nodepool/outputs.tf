output "node_pool" {
  value = local.pool_name
}

output "node_selector" {
  description = "What a GPU workload sets to land on this pool (plus a toleration for nvidia.com/gpu)."
  value       = { "phoenix/gpu" = local.gpu_type }
}

output "resource_summary" {
  value = {
    environment  = local.environment
    region       = local.region
    cluster      = local.cluster_key
    resource_set = "karpenter-nodepool"
    gpu_type     = local.gpu_type
    families     = local.config.instance_families
  }
}
