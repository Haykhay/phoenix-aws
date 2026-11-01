# Neuron counterpart of nvidia-gpu-operator for pools from karpenter-nodepool
# with accelerator: neuron. The AL2023 Neuron AMI carries the driver; this adds
# the device plugin (aws.amazon.com/neuron resources) and neuron-monitor
# (Neuron metrics, scraped by Alloy).
resource "helm_release" "plugin" {
  count      = local.config.enabled ? 1 : 0
  name       = "neuron"
  repository = "oci://public.ecr.aws/neuron"
  chart      = "neuron-helm-chart"
  version    = local.config.chart_version
  namespace  = "kube-system"

  values = [yamlencode({
    devicePlugin = {
      tolerations = [{ key = "CriticalAddonsOnly", operator = "Exists" }, local.neuron_toleration]
    }
  })]
}

resource "helm_release" "monitor" {
  count            = local.config.enabled ? 1 : 0
  name             = "neuron-monitor"
  chart            = "${path.module}/manifests/neuron-monitor"
  namespace        = "neuron-monitor"
  create_namespace = true

  values = [yamlencode({
    image        = local.config.monitor_image
    nodeSelector = { "phoenix/accelerator" = "neuron" }
    tolerations  = [local.neuron_toleration]
    # grafana-stack's Alloy scrapes pods that ask for it.
    podAnnotations = { "prometheus.io/scrape" = "true", "prometheus.io/port" = "8000" }
  })]
}
