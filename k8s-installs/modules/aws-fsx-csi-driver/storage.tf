# phoenix-shared: the platform's cloud-neutral name for a file system many pods
# share (ReadWriteMany). Every cloud maps it to its shared file storage; here
# one FSx for Lustre file system per claim, PERSISTENT_2 at 125 MB/s per TiB,
# in the cluster's first node subnet. Sizes: 1200 GiB, then 2400 GiB steps.
# Deleted with its claim.
resource "kubernetes_storage_class_v1" "shared" {
  count = local.config.enabled ? 1 : 0

  metadata {
    name = "phoenix-shared"
  }

  storage_provisioner = "fsx.csi.aws.com"
  volume_binding_mode = "Immediate"
  reclaim_policy      = "Delete"
  mount_options       = ["flock"]
  parameters = {
    subnetId                 = module.cluster.node_subnet_ids[0]
    securityGroupIds         = aws_security_group.lustre[0].id
    deploymentType           = "PERSISTENT_2"
    perUnitStorageThroughput = "125"
    extraTags                = "${local.tag_key}=${local.cluster_name}"
  }

  depends_on = [helm_release.driver]
}
