locals {
  defaults = {
    enabled = true
    # instance_families and gpu_count_max come from Backstage's phoenix-gpu
    # entity for this GPU type (the file's instance name, e.g. l4).
    instance_families = []
    gpu_count_max     = 1
    gpu_limit         = 8
    capacity_types    = ["on-demand"]
    # ODCRs or Capacity Blocks the engineer already holds: [{ id = "cr-…" }] or
    # [{ tags = { … } }]. Phoenix never buys any.
    capacity_reservations = []
    efa                   = false           # multi-node serving; EFA-capable families only
    ami_alias             = "al2023@latest" # Karpenter picks the NVIDIA variant for GPU instances
    volume_size           = "200Gi"         # model images and weights are large
    expire_after          = "168h"
    consolidate_after     = "5m"
  }

  config    = merge(local.defaults, module.context.spec)
  karpenter = module.cluster.karpenter
  gpu_type  = coalesce(local.instance, "missing")
  pool_name = "gpu-${local.gpu_type}"

  # Reserved first; on-demand (or spot) after it only if capacity_types lists it.
  capacity_types = length(local.config.capacity_reservations) > 0 ? concat(
    ["reserved"], [for t in local.config.capacity_types : t if t != "reserved"]
  ) : local.config.capacity_types

  # https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa.html, GPU families.
  efa_families = ["p4d", "p4de", "p5", "p5e", "p5en", "p6-b200", "p6e-gb200"]
  efa_plugin   = "v0.5.33" # aws-efa-k8s-device-plugin chart, 2026-09-15
}
