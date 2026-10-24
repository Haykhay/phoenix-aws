output "cluster" {
  description = "The Postgres cluster and where its credentials are published."
  value = local.config.enabled ? {
    name             = local.pg_cluster_name
    namespace        = local.config.namespace
    address          = local.service_host
    port             = local.port
    superuser_secret = module.credentials.secret_names["superuser"]
    database_secrets = { for name, db in local.databases : name => module.credentials.secret_names["db-${name}"] }
  } : null
}

output "resource_summary" {
  value = {
    environment  = local.environment
    region       = local.region
    cluster      = local.cluster_key
    resource_set = "cloudnative-pg-cluster"
    instance     = local.instance
    databases    = keys(local.databases)
  }
}
