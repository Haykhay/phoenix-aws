# One claim (file volume.<name>.yaml) on a cloud-neutral class: phoenix-block,
# a disk for one pod at a time, or phoenix-shared, a file system many pods
# mount. The namespace is created if missing; the claim binds when a pod uses it.
resource "terraform_data" "validation" {
  lifecycle {
    precondition {
      condition     = !local.config.enabled || local.instance != null
      error_message = "volume is per claim: name the file volume.<claim name>.yaml."
    }
    precondition {
      condition     = !local.config.enabled || contains(keys(local.access_modes), local.config.storage_class)
      error_message = "spec.storage_class must be ${join(" or ", keys(local.access_modes))}; got ${local.config.storage_class}."
    }
    precondition {
      condition     = !local.config.enabled || local.size_set
      error_message = "spec.size_gib is required: a whole number of GiB, 1 or more."
    }
    precondition {
      condition     = !local.config.enabled || local.config.storage_class != "phoenix-shared" || local.lustre_size
      error_message = "phoenix-shared sizes are 1200 GiB or a multiple of 2400 GiB (FSx for Lustre); got ${coalesce(local.size, 0)}."
    }
    precondition {
      condition     = !local.config.enabled || (local.config.namespace != null && !contains(local.system_namespaces, coalesce(local.config.namespace, "default")))
      error_message = "spec.namespace is required, and not a system namespace (${join(", ", local.system_namespaces)})."
    }
  }
}

resource "helm_release" "this" {
  count            = local.config.enabled ? 1 : 0
  name             = "volume-${coalesce(local.instance, "missing")}"
  chart            = "${path.module}/manifests/volume"
  namespace        = coalesce(local.config.namespace, "missing")
  create_namespace = true
  # The claim stays Pending until a pod mounts it (phoenix-block binds where the
  # pod lands): waiting for Bound would hang the apply.
  wait = false

  values = [yamlencode({
    name         = local.instance
    storageClass = local.config.storage_class
    size         = "${coalesce(local.size, 0)}Gi"
    accessMode   = lookup(local.access_modes, local.config.storage_class, "ReadWriteOnce")
  })]

  depends_on = [terraform_data.validation]
}
