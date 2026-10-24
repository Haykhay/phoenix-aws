resource "terraform_data" "validation" {
  lifecycle {
    precondition {
      condition     = !local.is_management || local.dns != null
      error_message = "the Kargo API route needs the cluster's DNS zone from infrastructure's dns unit."
    }
    precondition {
      condition     = !local.is_spoke || can(data.terraform_remote_state.management[0].outputs.remote_kubeconfig_secret)
      error_message = "cluster ${local.cluster_key} is a Kargo spoke of cluster ${local.management_cluster}, whose kargo unit has not been applied. Apply k8s-installs/.../${local.management_cluster}/kargo.yaml first."
    }
  }
}

resource "helm_release" "this" {
  count            = local.config.enabled ? 1 : 0
  name             = "kargo"
  repository       = "oci://ghcr.io/akuity/kargo-charts"
  chart            = "kargo"
  version          = local.config.chart_version
  namespace        = local.namespace
  create_namespace = true

  values = [
    local.mode == "management"
    ? templatefile("${path.module}/manifests/management-values.yaml.tpl", {
      api_host            = local.api_host
      shard_name          = local.shard
      argocd_urls         = local.argocd_urls
      admin_password_hash = local.kargo_admin_password_hash
      token_signing_key   = local.kargo_token_signing_key
    })
    : templatefile("${path.module}/manifests/spoke-values.yaml.tpl", {
      shard_name = local.shard
    })
  ]

  depends_on = [terraform_data.validation, kubernetes_secret_v1.kargo_management_kubeconfig, time_sleep.pod_identity_propagation]
}

# The Kargo API/UI on istio's internal gateway (management only).
resource "helm_release" "route" {
  count     = local.is_management ? 1 : 0
  name      = "kargo-route"
  chart     = "${path.module}/manifests/route"
  namespace = local.namespace

  values = [yamlencode({
    name     = "kargo-api"
    hostname = local.api_host
    gateway  = { name = "istio-internal", namespace = "istio-system" }
    service  = { name = "kargo-api", port = 80 }
  })]

  depends_on = [helm_release.this]
}
