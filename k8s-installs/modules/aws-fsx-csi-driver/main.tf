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

# The model cache is mounted statically when this cluster has one (vllm refuses
# to start without it). phoenix-shared provisions file systems dynamically, so
# the controller has a role of its own (iam.tf).
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

  depends_on = [time_sleep.pod_identity_propagation]
}

resource "helm_release" "volume" {
  count            = local.config.enabled && local.has_cache ? 1 : 0
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
