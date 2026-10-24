output "resource_summary" {
  value = {
    environment   = local.environment
    region        = local.region
    cluster       = local.cluster_key
    resource_set  = "clickhouse-operator"
    chart_version = local.config.chart_version
  }
}
