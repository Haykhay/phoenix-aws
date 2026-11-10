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

# The management cluster's internal gateway, for global_receiver's route.
data "terraform_remote_state" "istio" {
  backend = "s3"
  config = {
    bucket = module.context.state.bucket
    region = module.context.state.region
    key    = "${local.environment}/${local.region}/k8s/${local.cluster_key}/istio/terraform.tfstate"
  }
  defaults = {}
}

resource "terraform_data" "validation" {
  lifecycle {
    precondition {
      condition     = !local.config.enabled || !local.global_on || startswith(local.global_url, "https://")
      error_message = "spec.global_metrics.remote_write_url must be https://: the write credential travels with every request."
    }
    precondition {
      condition     = !local.config.enabled || !local.receiver_on || local.internal_gw != null
      error_message = "spec.global_receiver needs istio's internal gateway on this cluster (its TLS listener and DNS): apply istio first."
    }
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
  values = concat(
    [templatefile("${path.module}/manifests/alloy.yaml.tpl", local.template_vars)],
    local.global_on ? [local.global_env_values] : [],
  )

  depends_on = [helm_release.mimir, helm_release.loki, helm_release.tempo, helm_release.global_metrics]
}

resource "helm_release" "grafana" {
  count      = local.config.enabled ? 1 : 0
  name       = "grafana"
  repository = local.community_repo
  chart      = "grafana"
  version    = local.chart_versions.grafana
  namespace  = local.namespace
  values = concat(
    [templatefile("${path.module}/manifests/grafana.yaml.tpl", local.template_vars)],
    local.config.model_serving ? [local.model_serving_values] : [],
    [local.cost_values],
    local.receiver_on ? [local.global_values] : [],
  )

  depends_on = [helm_release.mimir, helm_release.loki, helm_release.tempo]
}

# Pod start and Ready times and Pending reasons for the model-serving dashboard
# and alerts; Alloy scrapes it by annotation.
resource "helm_release" "kube_state_metrics" {
  count      = local.config.enabled && local.config.model_serving ? 1 : 0
  name       = "kube-state-metrics"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-state-metrics"
  version    = local.chart_versions.kube_state_metrics
  namespace  = local.namespace

  values = [yamlencode({
    podAnnotations = { "prometheus.io/scrape" = "true", "prometheus.io/port" = "8080" }
  })]

  depends_on = [helm_release.mimir]
}

# Cross-cluster metrics (ADR-0011): the sender's credential (an ExternalSecret
# from the environment's prefix), and on the management cluster the receiver:
# an nginx that checks a password file and forwards writes only to Mimir,
# reachable on the internal gateway's TLS listener.
resource "helm_release" "global_metrics" {
  count     = local.config.enabled && (local.global_on || local.receiver_on) ? 1 : 0
  name      = "global-metrics"
  chart     = "${path.module}/manifests/global-metrics"
  namespace = local.namespace

  values = [yamlencode({
    send = local.global_on ? { secretName = local.send_secret } : null
    receive = local.receiver_on ? {
      secretName = local.global_secret
      hostname   = local.receiver_host
      gateway    = { name = try(local.internal_gw.name, ""), namespace = try(local.internal_gw.namespace, "") }
      upstream   = "http://mimir-gateway.${local.namespace}.svc"
      # The image Mimir's own gateway runs.
      image = "docker.io/nginxinc/nginx-unprivileged:1.29-alpine"
    } : null
  })]

  depends_on = [terraform_data.validation, helm_release.mimir]
}
