locals {
  defaults = {
    enabled       = true
    namespace     = null # where the pods that mount it run (created if missing)
    storage_class = "phoenix-block"
    size_gib      = null
  }

  config = merge(local.defaults, module.context.spec)

  # The platform's cloud-neutral classes (cluster-config, aws-fsx-csi-driver).
  access_modes      = { "phoenix-block" = "ReadWriteOnce", "phoenix-shared" = "ReadWriteMany" }
  system_namespaces = ["kube-system", "kube-public", "kube-node-lease", "default"]

  size     = try(tonumber(local.config.size_gib), null)
  size_set = local.size != null && try(local.size > 0 && floor(local.size) == local.size, false)
  # FSx for Lustre PERSISTENT_2: 1200 GiB, then steps of 2400 GiB.
  lustre_size = local.size_set && (local.size == 1200 || try(local.size % 2400 == 0, false))
}
