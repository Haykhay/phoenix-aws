# Binds each cluster's in-cluster observability stack (deployed from the
# in-cluster repo) to the group's long-lived observability roles. The roles
# and bucket belong to the `observability` resource set of the group's shared
# environment; Pod Identity tags each session with the cluster name, which is
# what confines a cluster to its own <signal prefix><cluster name>/ path (loki-<cluster>/ for Loki).

locals {
  observability_enabled = try(local.config.observability.enabled, false) && length(local.clusters) > 0

  # The group's shared environment holding the observability resource set.
  observability_env_id = "${module.context.group}-${try(local.config.observability.environment, "shared")}"

  # Where each writer's pods run unless spec.observability.service_accounts
  # says otherwise. The in-cluster repo deploys to these names.
  observability_service_accounts = merge(
    {
      mimir    = { namespace = "monitoring", service_account = "mimir" }
      loki     = { namespace = "monitoring", service_account = "loki" }
      tempo    = { namespace = "monitoring", service_account = "tempo" }
      grafana  = { namespace = "monitoring", service_account = "grafana" }
      langfuse = { namespace = "langfuse", service_account = "langfuse" }
    },
    try(local.config.observability.service_accounts, {}),
  )

  observability_role_arns = local.observability_enabled ? merge(
    data.terraform_remote_state.observability[0].outputs.writer_role_arns,
    { grafana = data.terraform_remote_state.observability[0].outputs.grafana_cloudwatch_role_arn },
  ) : {}

  observability_associations = !local.observability_enabled ? {} : merge([
    for cluster_key, cluster in local.clusters : {
      for writer, binding in local.observability_service_accounts :
      "${cluster_key}/${writer}" => merge(binding, {
        cluster_key = cluster_key
        role_arn    = local.observability_role_arns[writer]
      })
    }
  ]...)
}

data "terraform_remote_state" "observability" {
  count   = local.observability_enabled ? 1 : 0
  backend = "s3"

  config = {
    bucket = module.context.state.bucket
    region = module.context.state.region
    key    = "${local.observability_env_id}/${local.scope}/observability/terraform.tfstate"
  }
}

resource "aws_eks_pod_identity_association" "observability" {
  for_each = local.observability_associations

  cluster_name    = module.eks[each.value.cluster_key].cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = each.value.role_arn

  tags = local.tags[each.value.cluster_key]
}
