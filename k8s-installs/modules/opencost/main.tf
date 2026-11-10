# OpenCost: what each node, namespace and model costs per hour, from AWS list
# prices. It reads the cluster's own Mimir (grafana-stack) instead of running a
# Prometheus of its own, and Alloy scrapes its cost metrics back into Mimir
# for the Cost dashboard.
resource "helm_release" "this" {
  count            = local.config.enabled ? 1 : 0
  name             = "opencost"
  repository       = "https://opencost.github.io/opencost-helm-chart"
  chart            = "opencost"
  version          = local.config.chart_version
  namespace        = local.namespace
  create_namespace = true

  values = [yamlencode({
    podAnnotations = { "prometheus.io/scrape" = "true", "prometheus.io/port" = "9003" }
    opencost = {
      exporter = { defaultClusterId = local.cluster_name }
      prometheus = {
        internal = { enabled = false }
        external = { enabled = true, url = "http://mimir-gateway.monitoring.svc/prometheus" }
      }
    }
  })]
}
