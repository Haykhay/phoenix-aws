
data "aws_caller_identity" "current" {}

# Resolve the latest compatible addon version for any addon that sets
# most_recent: true without a pinned addon_version. Only creates one
# data source instance per addon that actually needs the lookup.
data "aws_eks_addon_version" "latest" {
  for_each = {
    for k, v in local.all_configured_addons : k => v
    if try(v.most_recent, true) && try(v.addon_version, null) == null
  }

  addon_name         = each.value.addon_name
  kubernetes_version = local.clusters[each.value.cluster_key].version
  most_recent        = true
}