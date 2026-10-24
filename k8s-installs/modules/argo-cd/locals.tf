locals {
  defaults = {
    enabled       = true
    chart_version = "7.9.1" # Argo CD 2.14; Argo CD 3 is a separate upgrade
    app_version   = ""
    # Git repository the bootstrap app watches (GitHub). Required.
    repo_url       = null
    bootstrap_path = "clusters/helm"
    # ECR pull-through cache prefix for OCI Helm charts (infrastructure's ecr unit).
    ecr_cache_prefix = "artifactory"
    settings         = {}
  }

  config    = merge(local.defaults, module.context.spec)
  namespace = "argocd"

  service_account_name = "argocd-repo-server"
  role_name            = "${local.name_prefix}-argocd-repo-server"

  repo_url = local.config.repo_url
  # One Argo CD per cluster; its values file in the repo is per cluster too.
  shard       = "${local.environment}-${local.cluster_key}"
  values_file = "clusters/${local.shard}.yaml"

  dns      = module.cluster.dns
  hostname = "argocd-${local.cluster_key}.${try(local.dns.internal_zone_name, "dns-missing")}"

  # Secrets for humans (admin login) and the deploy key, per cluster.
  secret_path = "${local.organisation}/${local.environment}/argo-cd/${local.cluster_key}"

  ecr_pull_arns = concat(
    ["arn:aws:ecr:${local.region}:${local.account_id}:repository/${local.config.ecr_cache_prefix}/*"],
    [for repo in try(local.config.settings.extra_ecr_pull_repos, []) : "arn:aws:ecr:${local.region}:${local.account_id}:repository/${repo}"],
  )
}
