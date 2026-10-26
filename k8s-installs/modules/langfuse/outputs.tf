output "url" {
  description = "Langfuse UI, on istio's internal gateway."
  value       = local.config.enabled ? "https://${local.hostname}" : null
}

output "otel_endpoint" {
  description = "Where applications send traces (Langfuse's OpenTelemetry endpoint)."
  value       = local.config.enabled ? "http://langfuse-web.${local.namespace}.svc:3000/api/public/otel" : null
}

output "resource_summary" {
  value = {
    environment   = local.environment
    region        = local.region
    cluster       = local.cluster_key
    resource_set  = "langfuse"
    chart_version = local.config.chart_version
    blob_prefix   = local.blob_prefix
  }
}
