# NVIDIA GPU operator for GPU nodes from karpenter-nodepool. The AL2023 NVIDIA
# AMIs Karpenter launches already carry the driver and container toolkit, so
# the operator only adds the device plugin (nvidia.com/gpu resources), GPU
# feature discovery and the DCGM exporter (GPU metrics, scraped by Alloy).
resource "helm_release" "this" {
  count            = local.config.enabled ? 1 : 0
  name             = "gpu-operator"
  repository       = "https://helm.ngc.nvidia.com/nvidia"
  chart            = "gpu-operator"
  version          = local.config.chart_version
  namespace        = local.namespace
  create_namespace = true
  timeout          = 900

  values = [yamlencode({
    driver       = { enabled = false }
    toolkit      = { enabled = false }
    devicePlugin = { enabled = true }
    dcgmExporter = {
      enabled = true
      # grafana-stack's Alloy scrapes pods that ask for it.
      annotations = { "prometheus.io/scrape" = "true", "prometheus.io/port" = "9400" }
    }
  })]
}
