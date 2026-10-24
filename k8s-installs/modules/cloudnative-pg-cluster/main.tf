resource "terraform_data" "validation" {
  lifecycle {
    precondition {
      condition     = !local.config.enabled || local.instance != null
      error_message = "cloudnative-pg-cluster is per database cluster: name the file cloudnative-pg-cluster.<name>.yaml."
    }
    precondition {
      condition     = !local.config.nlb_enabled || module.cluster.dns != null
      error_message = "nlb_enabled needs the cluster's DNS zone for the NLB hostname."
    }
  }
}

# Passwords and their Secrets Manager entries, on the platform's shared policy,
# at <organisation>/<env_id>/postgres/in-cluster/<instance>[/<database>] —
# where external-secrets may read them.
module "credentials" {
  source = "../../../infrastructure/modules/credentials"

  organisation = local.organisation

  credentials = local.config.enabled ? merge(
    { superuser = { policy = "postgres_incluster", username = "postgres" } },
    { for name, db in local.databases : "db-${name}" => { policy = "postgres_incluster", username = db.role } },
  ) : {}

  publish = local.config.enabled ? merge(
    {
      superuser = {
        environment = local.environment
        service     = "postgres"
        binding     = "in-cluster"
        instance    = local.name
        description = "Superuser of ${local.pg_cluster_name}"
        payload     = { address = local.service_host, port = tostring(local.port), engine = "postgres" }
      }
    },
    {
      for name, db in local.databases : "db-${name}" => {
        environment = local.environment
        service     = "postgres"
        binding     = "in-cluster"
        instance    = "${local.name}/${name}"
        description = "Database ${name} on ${local.pg_cluster_name}"
        payload = merge(
          {
            database = name
            address  = local.service_host
            port     = tostring(local.port)
            endpoint = "${local.service_host}:${local.port}"
            engine   = "postgres"
          },
          local.nlb_hostname == null ? {} : { nlb_address = local.nlb_hostname, nlb_endpoint = "${local.nlb_hostname}:${local.port}" },
        )
      }
    },
  ) : {}
}

resource "helm_release" "cluster" {
  count            = local.config.enabled ? 1 : 0
  name             = local.pg_cluster_name
  chart            = "${path.module}/manifests/cluster"
  namespace        = local.config.namespace
  create_namespace = true
  wait             = true
  wait_for_jobs    = true
  timeout          = 300
  atomic           = true
  cleanup_on_fail  = true

  values = [yamlencode({
    clusterName           = local.pg_cluster_name
    superuserSmSecretName = module.credentials.secret_names["superuser"]
    instances             = local.config.instances
    storageSize           = local.config.storage_size
    nlb = {
      enabled  = local.config.nlb_enabled
      hostname = local.nlb_hostname == null ? "" : local.nlb_hostname
    }
    databases = [
      for name, db in local.databases : {
        name         = name
        role         = db.role
        smSecretName = module.credentials.secret_names["db-${name}"]
      }
    ]
  })]

  depends_on = [terraform_data.validation, module.credentials]
}
