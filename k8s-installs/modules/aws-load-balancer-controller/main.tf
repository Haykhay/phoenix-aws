resource "helm_release" "this" {
  count            = local.config.enabled ? 1 : 0
  name             = "aws-load-balancer-controller"
  chart            = "aws-load-balancer-controller"
  repository       = "https://aws.github.io/eks-charts"
  version          = local.config.chart_version
  namespace        = local.namespace
  create_namespace = false

  values = [yamlencode(merge(
    {
      clusterName = local.cluster_name
      region      = local.region
      # Set explicitly: nodes require IMDSv2 with the default hop limit, so the
      # controller cannot reliably discover its VPC from instance metadata.
      vpcId          = module.cluster.vpc_id
      defaultTags    = local.default_tags
      serviceAccount = { create = true, name = local.service_account_name }
    },
    local.config.app_version == "" ? {} : { image = { tag = "v${local.config.app_version}" } },
  ))]

  depends_on = [
    aws_iam_role_policy_attachment.this,
    time_sleep.pod_identity_propagation,
  ]
}
