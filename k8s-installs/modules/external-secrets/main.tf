resource "helm_release" "this" {
  count            = local.config.enabled ? 1 : 0
  name             = "external-secrets"
  chart            = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  version          = local.config.chart_version
  namespace        = local.namespace
  create_namespace = true

  wait    = true
  timeout = 600

  values = [
    templatefile("${path.module}/manifests/values.yaml.tpl", {
      service_account_name = local.service_account_name
      app_version          = try(local.config.app_version, "")
    })
  ]

  set = [{ name = "installCRDs", value = "true" }]

  depends_on = [
    aws_iam_role_policy_attachment.this,
    time_sleep.pod_identity_propagation,
  ]
}

resource "helm_release" "cluster_secret_stores" {
  count     = local.config.enabled ? 1 : 0
  name      = "external-secrets-cluster-secret-stores"
  chart     = "${path.module}/manifests/cluster-secret-stores"
  namespace = local.namespace

  set = [{ name = "awsRegion", value = local.region }]

  depends_on = [helm_release.this]
}
