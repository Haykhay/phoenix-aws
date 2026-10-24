output "cluster" {
  description = "The Valkey cluster and where its credentials are published."
  value = local.config.enabled ? {
    name           = local.vk_cluster_name
    namespace      = local.config.namespace
    address        = local.service_host
    port           = local.port
    default_secret = module.credentials.secret_names["default"]
    user_secrets   = { for name, u in local.users : name => module.credentials.secret_names["user-${name}"] }
  } : null
}

output "resource_summary" {
  value = {
    environment  = local.environment
    region       = local.region
    cluster      = local.cluster_key
    resource_set = "valkey-redis-cluster"
    instance     = local.instance
  }
}
