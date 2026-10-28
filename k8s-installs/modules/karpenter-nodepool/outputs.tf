output "node_pool" {
  description = "NodePool name (gpu-<type>)."
  value       = local.pool_name
}

output "node_selector" {
  description = "What a GPU workload sets to land on this pool (plus a toleration for nvidia.com/gpu)."
  value       = { "phoenix/gpu" = local.gpu_type }
}

output "efa" {
  description = "Whether the pool's nodes have EFA (label phoenix/efa=true): multi-node serving needs it."
  value       = local.config.efa
}

output "capacity_reservations" {
  description = "Reservations or Capacity Blocks the pool uses first ([] = on-demand only)."
  value       = local.config.capacity_reservations
}

output "resource_summary" {
  value = {
    environment  = local.environment
    region       = local.region
    cluster      = local.cluster_key
    resource_set = "karpenter-nodepool"
    gpu_type     = local.gpu_type
    families     = local.config.instance_families
    capacity     = local.capacity_types
    efa          = local.config.efa
  }
}
