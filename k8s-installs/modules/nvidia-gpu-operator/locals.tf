locals {
  defaults = {
    enabled       = true
    chart_version = "v26.7.1"
    # Time-slicing profiles a GPU pool can pick with time_slice_replicas
    # (karpenter-nodepool labels its nodes nvidia.com/device-plugin.config=ts-<n>).
    time_slice_profiles = [2, 4]
  }

  config    = merge(local.defaults, module.context.spec)
  namespace = "gpu-operator"

  # One device-plugin config per profile; unlabelled nodes share nothing.
  # failRequestsGreaterThanOne: a pod asking for 2 shares of one GPU is refused
  # rather than given slices that don't add up to more memory.
  device_plugin_config = length(local.config.time_slice_profiles) == 0 ? null : {
    create  = true
    name    = "time-slicing"
    default = "none"
    data = merge({ none = "version: v1\n" }, { for n in local.config.time_slice_profiles : "ts-${n}" => yamlencode({
      version = "v1"
      sharing = { timeSlicing = { failRequestsGreaterThanOne = true, resources = [{ name = "nvidia.com/gpu", replicas = n }] } }
    }) })
  }
}
