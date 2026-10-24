locals {
  defaults = {
    enabled = true
    # instance_families and gpu_count_max come from Backstage's phoenix-gpu
    # entity for this GPU type (the file's instance name, e.g. l4).
    instance_families = []
    gpu_count_max     = 1
    gpu_limit         = 8
    capacity_types    = ["on-demand"]
    ami_alias         = "al2023@latest" # Karpenter picks the NVIDIA variant for GPU instances
    volume_size       = "200Gi"         # model images and weights are large
    expire_after      = "168h"
    consolidate_after = "5m"
  }

  config    = merge(local.defaults, module.context.spec)
  karpenter = module.cluster.karpenter
  gpu_type  = coalesce(local.instance, "missing")
  pool_name = "gpu-${local.gpu_type}"
}
