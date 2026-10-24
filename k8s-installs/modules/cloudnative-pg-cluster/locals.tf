locals {
  defaults = {
    enabled      = true
    namespace    = "cnpg-system"
    instances    = 1
    storage_size = "10Gi"
    # One database named after the instance unless the request lists some.
    databases   = []
    nlb_enabled = false
  }

  config = merge(local.defaults, module.context.spec)

  # One unit = one Postgres cluster: cloudnative-pg-cluster.<instance>.yaml
  name            = coalesce(local.instance, "missing")
  pg_cluster_name = "cnpg-${local.name}"
  port            = 5432
  service_host    = "${local.pg_cluster_name}-rw.${local.config.namespace}.svc.cluster.local"

  databases = {
    for db in(length(local.config.databases) > 0 ? local.config.databases : [{ name = replace(local.name, "-", "_") }]) :
    db.name => { name = db.name, role = try(db.owner, db.name) }
  }

  nlb_hostname = local.config.nlb_enabled ? coalesce(
    try(local.config.nlb_hostname, null),
    "${local.pg_cluster_name}.${try(module.cluster.dns.internal_zone_name, "dns-missing")}",
  ) : null
}
