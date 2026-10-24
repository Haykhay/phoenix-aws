locals {
  defaults = {
    enabled       = true
    chart_version = "2.6.0"
    app_version   = ""
    settings      = {}
  }

  config = merge(local.defaults, module.context.spec)

  namespace            = "external-secrets"
  service_account_name = "external-secrets"
  role_name            = "${local.name_prefix}-external-secrets"

  # Everything this cluster may read lives under <organisation>/<env_id>/ in
  # its own account and region — the credentials module's publish path — so a
  # cluster can never read another environment's secrets.
  secret_path = "${local.organisation}/${local.environment}"
  secrets_manager_arns = try(local.config.settings.secrets_manager_arns, [
    "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:${local.secret_path}/*",
  ])
  ssm_parameter_arns = try(local.config.settings.ssm_parameter_arns, [
    "arn:aws:ssm:${local.region}:${local.account_id}:parameter/${local.secret_path}/*",
  ])
  kms_key_arns = distinct(compact(concat(
    [module.cluster.cluster_kms_key_arn],
    try(local.config.settings.kms_key_arns, []),
  )))
  # Repositories in this account the operator may pull from (e.g. OCI Helm
  # charts behind the ECR pull-through cache), as repository names.
  ecr_pull_repos = try(local.config.settings.ecr_pull_repos, [])
}
