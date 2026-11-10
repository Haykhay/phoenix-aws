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

# phoenix-block: the platform's cloud-neutral name for a pod's own disk. Every
# cloud maps it to its encrypted block storage (here gp3 EBS); workloads ask for
# the name, never the cloud's class. gp3 stays the default class.
resource "kubernetes_storage_class_v1" "block" {
  count = local.config.enabled ? 1 : 0

  metadata {
    name = "phoenix-block"
  }

  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  reclaim_policy         = "Delete"
  parameters = merge(
    { type = "gp3", encrypted = "true" },
    { for i, k in sort(keys(local.ebs_tags)) : "tagSpecification_${i + 1}" => "${k}=${local.ebs_tags[k]}" },
  )
}
