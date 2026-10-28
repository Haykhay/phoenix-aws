locals {
  defaults = {
    enabled = true
    # instance_families and gpu_count_max come from Backstage's phoenix-gpu
    # entity for this GPU type (the file's instance name, e.g. l4).
    instance_families = []
    gpu_count_max     = 1
    gpu_limit         = null # default: max(8, two nodes of gpu_count_max)
    capacity_types    = ["on-demand"]
    # ODCRs or Capacity Blocks the engineer already holds: [{ id = "cr-…" }] or
    # [{ tags = { … } }]. Phoenix never buys any.
    capacity_reservations = []
    efa                   = false           # multi-node serving; EFA-capable families only
    accelerator           = "nvidia"        # or neuron (Trainium/Inferentia)
    ami_alias             = "al2023@latest" # Karpenter picks the NVIDIA or Neuron variant
    volume_size           = "200Gi"         # model images and weights are large
    expire_after          = "168h"
    consolidate_after     = "5m"
  }

  config    = merge(local.defaults, module.context.spec)
  karpenter = module.cluster.karpenter
  gpu_type  = coalesce(local.instance, "missing")
  pool_name = "gpu-${local.gpu_type}"
  # Total devices the pool may hold. Two full nodes by default, so a big node
  # (trn2: 16) or a two-node replica can launch; raise it for more.
  gpu_limit = coalesce(local.config.gpu_limit, max(8, 2 * local.config.gpu_count_max))

  # Reserved first; on-demand (or spot) after it only if capacity_types lists it.
  capacity_types = length(local.config.capacity_reservations) > 0 ? concat(
    ["reserved"], [for t in local.config.capacity_types : t if t != "reserved"]
  ) : local.config.capacity_types

  # https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa.html, GPU families.
  efa_families = ["p4d", "p4de", "p5", "p5e", "p5en", "p6-b200", "p6e-gb200"]
  efa_plugin   = "v0.5.33" # aws-efa-k8s-device-plugin chart, 2026-09-15

  # Taint, device resource and count label per accelerator. The al2023 alias
  # resolves to the NVIDIA or Neuron AMI variant from the instance type.
  accelerators = {
    nvidia = { name = "nvidia", taint = "nvidia.com/gpu", resource = "nvidia.com/gpu", countLabel = "karpenter.k8s.aws/instance-gpu-count" }
    neuron = { name = "neuron", taint = "aws.amazon.com/neuron", resource = "aws.amazon.com/neuron", countLabel = "karpenter.k8s.aws/instance-accelerator-count" }
  }
  accelerator = lookup(local.accelerators, local.config.accelerator, local.accelerators.nvidia)
}
