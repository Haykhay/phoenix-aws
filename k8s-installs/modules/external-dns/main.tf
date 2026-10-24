resource "terraform_data" "validation" {
  lifecycle {
    precondition {
      condition     = !local.config.enabled || module.cluster.dns != null
      error_message = "external-dns needs the cluster's DNS zone from infrastructure's dns unit for ${local.environment}."
    }
  }
}

resource "helm_release" "this" {
  count            = local.config.enabled ? 1 : 0
  name             = "external-dns"
  chart            = "external-dns"
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  version          = local.config.chart_version
  namespace        = local.namespace
  create_namespace = true

  values = [yamlencode(merge(
    {
      provider       = { name = "aws" }
      sources        = ["service", "ingress", "gateway-httproute"]
      serviceAccount = { create = true, name = local.service_account_name }
      # Only resources that ask for a record.
      annotationFilter = "external-dns.alpha.kubernetes.io/hostname"
      txtOwnerId       = local.txt_owner_id
      policy           = try(local.config.settings.policy, "upsert-only")
      # The chart has no zoneIdFilters value; the filter is container args.
      extraArgs = [for id in local.route53_zone_ids : "--zone-id-filter=${id}"]
      env       = [{ name = "AWS_DEFAULT_REGION", value = local.region }]
    },
    local.config.app_version == "" ? {} : { image = { tag = "v${local.config.app_version}" } },
  ))]

  depends_on = [terraform_data.validation, aws_iam_role_policy_attachment.this, time_sleep.pod_identity_propagation]
}
