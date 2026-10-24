resource "terraform_data" "validation" {
  lifecycle {
    precondition {
      condition     = !local.config.enabled || local.dns != null
      error_message = "cert-manager's issuers need the cluster's DNS zone from infrastructure's dns unit for ${local.environment}."
    }
  }
}

resource "helm_release" "this" {
  count            = local.config.enabled ? 1 : 0
  name             = "cert-manager"
  chart            = "cert-manager"
  repository       = "https://charts.jetstack.io"
  version          = local.config.chart_version
  namespace        = local.namespace
  create_namespace = true

  values = [yamlencode(merge(
    {
      crds           = { enabled = local.install_crds }
      config         = { enableGatewayAPI = local.enable_gateway_api }
      serviceAccount = { name = local.service_account_name }
    },
    local.config.app_version == "" ? {} : { image = { tag = local.config.app_version } },
  ))]

  depends_on = [terraform_data.validation, aws_iam_role_policy_attachment.this, time_sleep.pod_identity_propagation]
}

# Let's Encrypt prod + staging, DNS-01 through Route53 in the cluster's zones.
resource "helm_release" "cluster_issuers" {
  count     = local.config.enabled ? 1 : 0
  name      = "cert-manager-cluster-issuers"
  chart     = "${path.module}/manifests/cluster-issuers"
  namespace = local.namespace

  values = [yamlencode({
    acmeEmail        = local.acme_email
    awsRegion        = local.region
    publicZoneId     = try(local.dns.public_zone_id, "")
    publicZoneName   = try(local.dns.public_zone_name, "")
    internalZoneId   = try(local.dns.internal_zone_id, "")
    internalZoneName = try(local.dns.internal_zone_name, "")
  })]

  depends_on = [helm_release.this]
}
