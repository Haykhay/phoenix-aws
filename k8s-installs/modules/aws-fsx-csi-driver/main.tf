# The cluster's FSx for Lustre cache, from infrastructure's model-cache unit.
data "terraform_remote_state" "model_cache" {
  backend = "s3"
  config = {
    bucket = module.context.state.bucket
    region = module.context.state.region
    key    = "${local.environment}/${local.region}/model-cache.${local.cluster_key}/terraform.tfstate"
  }
  defaults = {}
}

resource "terraform_data" "validation" {
  lifecycle {
    precondition {
      condition     = !local.config.enabled || can(local.cache.file_system_id)
      error_message = "no model cache for cluster ${local.cluster_key}: apply infrastructure's model-cache.${local.cluster_key} first."
    }
  }
}

# Static provisioning only: the controller creates nothing in AWS, so no IAM.
resource "helm_release" "driver" {
  count      = local.config.enabled ? 1 : 0
  name       = "aws-fsx-csi-driver"
  chart      = "aws-fsx-csi-driver"
  repository = "https://kubernetes-sigs.github.io/aws-fsx-csi-driver"
  version    = local.config.chart_version
  namespace  = "kube-system"

  values = [yamlencode({
    # The node image carries the Lustre client and loads its kernel module, so
    # nodes need nothing installed. Every node, GPU and Neuron pools included.
    node = { tolerateAllTaints = true }
  })]

  depends_on = [terraform_data.validation]
}

resource "helm_release" "volume" {
  count            = local.config.enabled ? 1 : 0
  name             = local.pvc_name
  chart            = "${path.module}/manifests/model-cache"
  namespace        = local.namespace
  create_namespace = true

  values = [yamlencode({
    name = local.pvc_name
    fsx = {
      volumeHandle = local.cache.file_system_id
      dnsName      = local.cache.dns_name
      mountName    = local.cache.mount_name
    }
  })]

  depends_on = [helm_release.driver]
}
