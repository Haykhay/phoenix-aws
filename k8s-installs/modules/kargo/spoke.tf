# ── Spoke cluster: report to the environment's management cluster ────────────
# Same environment = same account and (assumed) same VPC, so no cross-account
# provider: the management cluster's facts come from core-platform's state and
# its kargo unit's state.

module "management_cluster" {
  source = "../cluster"

  state   = module.context.state
  env_id  = module.context.env_id
  region  = module.context.region
  cluster = local.management_cluster
}

data "terraform_remote_state" "management" {
  count   = local.is_spoke ? 1 : 0
  backend = "s3"
  config = {
    bucket = module.context.state.bucket
    region = module.context.state.region
    key    = "${local.environment}/${local.region}/k8s/${local.management_cluster}/kargo/terraform.tfstate"
  }
  defaults = {}
}

data "aws_secretsmanager_secret_version" "remote_kubeconfig" {
  count     = local.is_spoke ? 1 : 0
  secret_id = try(data.terraform_remote_state.management[0].outputs.remote_kubeconfig_secret, "kargo-management-missing")

  depends_on = [terraform_data.validation]
}

# This spoke's nodes (only) may reach the management cluster's API. One rule
# per spoke, keyed by its own node security group, so spokes never collide.
resource "aws_security_group_rule" "management_api_access" {
  count                    = local.is_spoke ? 1 : 0
  type                     = "ingress"
  security_group_id        = module.management_cluster.cluster_security_group_id
  source_security_group_id = module.cluster.node_security_group_id
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  description              = "Kargo spoke ${local.shard} to the management cluster API"
}

# The namespace exists before helm_release.this (which waits on the secret below).
resource "kubernetes_namespace_v1" "kargo" {
  count = local.config.enabled ? 1 : 0
  metadata {
    name   = local.namespace
    labels = { name = local.namespace }
  }
}

resource "kubernetes_secret_v1" "kargo_management_kubeconfig" {
  count      = local.is_spoke ? 1 : 0
  depends_on = [kubernetes_namespace_v1.kargo]
  metadata {
    name      = "kargo-management-kubeconfig"
    namespace = local.namespace
  }
  data = {
    "kubeconfig.yaml" = data.aws_secretsmanager_secret_version.remote_kubeconfig[0].secret_string
  }
}
