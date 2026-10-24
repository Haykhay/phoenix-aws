output "namespace" {
  value = local.namespace
}

output "grafana_service" {
  description = "In-cluster Grafana service."
  value       = local.config.enabled ? "grafana.${local.namespace}.svc" : null
}

output "endpoints" {
  description = "Where other components send signals."
  value = local.config.enabled ? {
    mimir_remote_write = "http://mimir-gateway.${local.namespace}.svc/api/v1/push"
    loki_push          = "http://loki-gateway.${local.namespace}.svc/loki/api/v1/push"
    otlp_grpc          = "alloy.${local.namespace}.svc:4317"
  } : null
}

output "resource_summary" {
  value = {
    environment    = local.environment
    region         = local.region
    cluster        = local.cluster_key
    resource_set   = "grafana-stack"
    bucket         = local.bucket
    chart_versions = local.chart_versions
  }
}
