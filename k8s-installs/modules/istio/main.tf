# Istio as the cluster's one Gateway API implementation: for services, and
# for model serving through the Inference Extension (InferencePool).
# Gateways terminate TLS with cert-manager wildcards on the cluster's zones
# and sit behind NLBs, so this needs the aws-load-balancer-controller and
# cert-manager units (and a dns unit) applied first.
resource "terraform_data" "validation" {
  lifecycle {
    precondition {
      condition     = !local.config.enabled || local.dns != null
      error_message = "istio needs the cluster's DNS zone (dns_zone \"${try(module.context.config.dns_zone, "zone-1")}\") from infrastructure's dns unit for ${local.environment}."
    }
  }
}

# Gateway API standard CRDs + InferencePool. Not prevent_destroy: a weekend
# teardown destroys this unit, after everything that uses the CRDs.
resource "helm_release" "crds" {
  count     = local.config.enabled ? 1 : 0
  name      = "gateway-api-crds"
  chart     = "${path.module}/manifests/gateway-crds"
  namespace = "kube-system"

  depends_on = [terraform_data.validation]
}

resource "helm_release" "base" {
  count            = local.config.enabled ? 1 : 0
  name             = "istio-base"
  chart            = "base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  version          = local.config.chart_version
  namespace        = local.namespace
  create_namespace = true

  set = [{ name = "defaultRevision", value = "default" }]

  depends_on = [helm_release.crds]
}

resource "helm_release" "istiod" {
  count      = local.config.enabled ? 1 : 0
  name       = "istiod"
  chart      = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  version    = local.config.chart_version
  namespace  = local.namespace

  # Lets istiod reconcile InferencePool backends for HTTPRoutes.
  values = [yamlencode({ pilot = { env = { ENABLE_GATEWAY_API_INFERENCE_EXTENSION = "true" } } })]

  depends_on = [helm_release.base]
}

resource "helm_release" "extras" {
  count     = local.config.enabled ? 1 : 0
  name      = "istio-extras"
  chart     = "${path.module}/manifests/istio-extras"
  namespace = local.namespace

  values = [yamlencode({
    certs = {
      publicZoneName     = local.public_zone_name
      internalZoneName   = local.internal_zone_name
      publicSecretName   = local.public_secret_name
      internalSecretName = local.internal_secret_name
      issuerName         = "letsencrypt-prod"
    }
    gateways = {
      internal = { enabled = local.internal_gateway.enabled, serviceAnnotations = local.internal_gateway.service_annotations }
      external = { enabled = local.external_gateway.enabled, serviceAnnotations = local.external_gateway.service_annotations }
    }
    telemetry = { consumerTags = true }
  })]

  depends_on = [helm_release.istiod]
}
