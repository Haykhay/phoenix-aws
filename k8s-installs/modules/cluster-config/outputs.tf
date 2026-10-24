output "resource_summary" {
  value = {
    environment   = local.environment
    region        = local.region
    cluster       = local.cluster_key
    resource_set  = "cluster-config"
    storage_class = "gp3"
  }
}
