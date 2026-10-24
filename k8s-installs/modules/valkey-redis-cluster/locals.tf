locals {
  defaults = {
    enabled      = true
    namespace    = "valkey-operator"
    shards       = 1
    replicas     = 0
    storage_size = "5Gi"
    users        = []
  }

  config = merge(local.defaults, module.context.spec)

  # One unit = one Valkey cluster: valkey-redis-cluster.<instance>.yaml
  name            = coalesce(local.instance, "missing")
  vk_cluster_name = "valkey-${local.name}"
  port            = 6379
  service_host    = "${local.vk_cluster_name}.${local.config.namespace}.svc.cluster.local"

  users = { for u in local.config.users : u.name => { permissions = try(u.permissions, "+@all ~* &*") } }
}
