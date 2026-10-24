locals {
  defaults = {
    enabled  = true
    settings = {}
  }

  config = merge(local.defaults, module.context.spec)

  # The tags every AWS resource of this unit carries; EBS volumes created
  # through the gp3 StorageClass get the same.
  ebs_tags = merge(
    module.context.tags,
    { Cluster = local.cluster_key },
  )
}
