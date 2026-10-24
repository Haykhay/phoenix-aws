locals {
  defaults = {
    enabled       = true
    chart_version = "2.1.4" # Langfuse 4.50.0
    # The group's environment holding the observability unit (as grafana-stack).
    observability_environment = "shared"
  }

  config = merge(local.defaults, module.context.spec)

  # Must match core-platform's Pod Identity binding (langfuse/langfuse).
  namespace       = "langfuse"
  service_account = "langfuse"

  dns      = module.cluster.dns
  hostname = "langfuse-${local.cluster_key}.${try(local.dns.internal_zone_name, "dns-missing")}"

  observability = try(data.terraform_remote_state.observability.outputs, {})
  bucket        = try(local.observability.bucket_name, "observability-missing")
  # The langfuse writer role may only touch langfuse/<cluster name>/.
  blob_prefix = "${try(local.observability.signal_prefixes.langfuse, "langfuse/")}${local.cluster_name}/"
}
