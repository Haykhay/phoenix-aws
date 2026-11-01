output "resource_summary" {
  value = {
    environment   = local.environment
    region        = local.region
    cluster       = local.cluster_key
    resource_set  = "neuron-device-plugin"
    chart_version = try(helm_release.plugin[0].version, null)
  }
}
