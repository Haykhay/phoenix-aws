resource "helm_release" "falco_operator" {
  count            = local.config.enabled ? 1 : 0
  name             = local.release_name
  chart            = local.chart
  repository       = local.repository
  version          = local.chart_version
  namespace        = local.namespace
  create_namespace = true
  wait             = local.wait
  wait_for_jobs    = local.wait_for_jobs
  timeout          = local.timeout
  atomic           = local.atomic
  cleanup_on_fail  = local.cleanup_on_fail

  values = [yamlencode(local.chart_values)]
}

# Artifact CRs (plugins, rulesfile, metacollector) applied before the Falco instance.
# On destroy Terraform reverses this order: Falco CR is removed first while the
# artifact-operator sidecar is still running, so Plugin/Rulesfile finalizers resolve
# cleanly. Deleting the Falco CR first (instance before artifacts) would kill the
# sidecar and leave those finalizers stuck.
resource "helm_release" "falco_artifacts" {
  count            = local.config.enabled ? 1 : 0
  name             = "falco-artifacts"
  chart            = "${path.module}/manifests/falco-artifacts"
  namespace        = local.namespace
  create_namespace = true
  wait             = false
  atomic           = false
  cleanup_on_fail  = local.cleanup_on_fail

  set = [
    { name = "pluginTag", value = local.plugin_tag },
    { name = "k8smetaTag", value = local.k8smeta_tag },
    { name = "rulesTag", value = local.rules_tag },
  ]

  depends_on = [helm_release.falco_operator]
}

# Falco instance CR — applied last so destroy order is: instance → artifacts → operator.
resource "helm_release" "falco_instance" {
  count            = local.config.enabled ? 1 : 0
  name             = "falco-instance"
  chart            = "${path.module}/manifests/falco-instance"
  namespace        = local.namespace
  create_namespace = true
  wait             = false
  atomic           = false
  cleanup_on_fail  = local.cleanup_on_fail

  depends_on = [helm_release.falco_artifacts]
}
