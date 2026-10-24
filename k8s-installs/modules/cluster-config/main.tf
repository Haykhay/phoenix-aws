resource "helm_release" "this" {
  count            = local.config.enabled ? 1 : 0
  name             = "cluster-config"
  chart            = "${path.module}/manifests/cluster-config"
  namespace        = "kube-system"
  create_namespace = false
  wait             = true
  timeout          = 120
  atomic           = true
  cleanup_on_fail  = true

  values = [yamlencode({
    ebs  = { enabled = true }
    tags = local.ebs_tags
  })]
}
