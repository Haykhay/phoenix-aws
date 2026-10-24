resource "terraform_data" "validation" {
  lifecycle {
    precondition {
      condition     = !local.config.enabled || local.instance != null
      error_message = "valkey-redis-cluster is per cluster: name the file valkey-redis-cluster.<name>.yaml."
    }
  }
}

# Passwords at <organisation>/<env_id>/redis/in-cluster/<instance>[/<user>],
# where external-secrets may read them.
module "credentials" {
  source = "../../../infrastructure/modules/credentials"

  organisation = local.organisation

  credentials = local.config.enabled ? merge(
    { default = { policy = "redis_incluster", username = "default" } },
    { for name, u in local.users : "user-${name}" => { policy = "redis_incluster", username = name } },
  ) : {}

  publish = local.config.enabled ? merge(
    {
      default = {
        environment = local.environment
        service     = "redis"
        binding     = "in-cluster"
        instance    = local.name
        description = "Default user of ${local.vk_cluster_name}"
        payload     = { address = local.service_host, port = tostring(local.port), endpoint = "${local.service_host}:${local.port}", engine = "valkey" }
      }
    },
    {
      for name, u in local.users : "user-${name}" => {
        environment = local.environment
        service     = "redis"
        binding     = "in-cluster"
        instance    = "${local.name}/${name}"
        description = "User ${name} of ${local.vk_cluster_name}"
        payload     = { address = local.service_host, port = tostring(local.port), endpoint = "${local.service_host}:${local.port}", engine = "valkey" }
      }
    },
  ) : {}
}

resource "helm_release" "cluster" {
  count            = local.config.enabled ? 1 : 0
  name             = local.vk_cluster_name
  chart            = "${path.module}/manifests/cluster"
  namespace        = local.config.namespace
  create_namespace = true
  wait             = true
  wait_for_jobs    = true
  timeout          = 600
  atomic           = true
  cleanup_on_fail  = true

  values = [yamlencode({
    clusterName         = local.vk_cluster_name
    shards              = local.config.shards
    replicas            = local.config.replicas
    storageSize         = local.config.storage_size
    defaultSmSecretName = module.credentials.secret_names["default"]
    users = [
      for name, u in local.users : {
        name         = name
        smSecretName = module.credentials.secret_names["user-${name}"]
        permissions  = u.permissions
      }
    ]
  })]

  depends_on = [terraform_data.validation, module.credentials]
}
