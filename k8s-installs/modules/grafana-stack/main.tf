# Each cluster's own Grafana stack: Mimir (metrics), Loki (logs), Tempo
# (traces), Alloy (collection) and Grafana. History goes to the group's
# long-lived observability bucket, so it survives weekend teardowns.
data "terraform_remote_state" "observability" {
  backend = "s3"
  config = {
    bucket = module.context.state.bucket
    region = module.context.state.region
    key    = "${module.context.group}-${local.config.observability_environment}/${local.region}/observability/terraform.tfstate"
  }
  defaults = {}
}

resource "terraform_data" "validation" {
  lifecycle {
    precondition {
      condition     = !local.config.enabled || can(local.observability.bucket_name)
      error_message = "No observability state for ${module.context.group}-${local.config.observability_environment}/${local.region}. Apply infrastructure's observability unit for the group first."
    }
  }
}

locals {
  grafana_repo   = "https://grafana.github.io/helm-charts"
  community_repo = "https://grafana-community.github.io/helm-charts"
}

resource "helm_release" "mimir" {
  count            = local.config.enabled ? 1 : 0
  name             = "mimir"
  repository       = local.grafana_repo
  chart            = "mimir-distributed"
  version          = local.chart_versions.mimir
  namespace        = local.namespace
  create_namespace = true
  timeout          = 900
  values           = [templatefile("${path.module}/manifests/mimir.yaml.tpl", local.template_vars)]

  depends_on = [terraform_data.validation]
}

resource "helm_release" "loki" {
  count      = local.config.enabled ? 1 : 0
  name       = "loki"
  repository = local.grafana_repo
  chart      = "loki"
  version    = local.chart_versions.loki
  namespace  = local.namespace
  timeout    = 600
  values     = [templatefile("${path.module}/manifests/loki.yaml.tpl", local.template_vars)]

  depends_on = [helm_release.mimir]
}

resource "helm_release" "tempo" {
  count      = local.config.enabled ? 1 : 0
  name       = "tempo"
  repository = local.community_repo
  chart      = "tempo"
  version    = local.chart_versions.tempo
  namespace  = local.namespace
  timeout    = 600
  values     = [templatefile("${path.module}/manifests/tempo.yaml.tpl", local.template_vars)]

  depends_on = [helm_release.mimir]
}

resource "helm_release" "alloy" {
  count      = local.config.enabled ? 1 : 0
  name       = "alloy"
  repository = local.grafana_repo
  chart      = "alloy"
  version    = local.chart_versions.alloy
  namespace  = local.namespace
  values     = [templatefile("${path.module}/manifests/alloy.yaml.tpl", local.template_vars)]

  depends_on = [helm_release.mimir, helm_release.loki, helm_release.tempo]
}

resource "helm_release" "grafana" {
  count      = local.config.enabled ? 1 : 0
  name       = "grafana"
  repository = local.community_repo
  chart      = "grafana"
  version    = local.chart_versions.grafana
  namespace  = local.namespace
  values     = [templatefile("${path.module}/manifests/grafana.yaml.tpl", local.template_vars)]

  depends_on = [helm_release.mimir, helm_release.loki, helm_release.tempo]
}
