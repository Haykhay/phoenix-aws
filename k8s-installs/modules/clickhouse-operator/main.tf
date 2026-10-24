# ClickHouse's own operator (ClickHouseCluster / KeeperCluster CRDs). The
# Langfuse chart (2.x) deploys its ClickHouse through it and refuses to install
# without the CRDs. Cluster-wide; needs cert-manager for its webhook.
resource "helm_release" "this" {
  count            = local.config.enabled ? 1 : 0
  name             = "clickhouse-operator"
  repository       = "oci://ghcr.io/clickhouse"
  chart            = "clickhouse-operator-helm"
  version          = local.config.chart_version
  namespace        = local.namespace
  create_namespace = true
  wait             = true
}
