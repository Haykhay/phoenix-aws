resource "helm_release" "kyverno" {
  count = local.config.enabled && local.kyverno_enabled ? 1 : 0

  name             = local.kyverno_release_name
  chart            = local.kyverno_chart
  repository       = local.kyverno_repository
  version          = local.kyverno_chart_version
  namespace        = local.kyverno_namespace
  create_namespace = true
  wait             = local.kyverno_wait
  wait_for_jobs    = local.kyverno_wait_for_jobs
  timeout          = local.kyverno_timeout
  atomic           = local.kyverno_atomic
  cleanup_on_fail  = local.kyverno_cleanup_on_fail

  values = [
    yamlencode(local.kyverno_values)
  ]
}

resource "helm_release" "kyverno_policies" {
  count = local.config.enabled && local.kyverno_policies_enabled ? 1 : 0

  name             = local.kyverno_policies_release_name
  chart            = local.kyverno_policies_chart
  repository       = local.kyverno_policies_repository
  version          = local.kyverno_policies_chart_version
  namespace        = local.kyverno_policies_namespace
  create_namespace = true
  wait             = local.kyverno_policies_wait
  wait_for_jobs    = local.kyverno_policies_wait_for_jobs
  timeout          = local.kyverno_policies_timeout
  atomic           = local.kyverno_policies_atomic
  cleanup_on_fail  = local.kyverno_policies_cleanup_on_fail

  values = [
    yamlencode(local.kyverno_policies_values)
  ]

  lifecycle {
    precondition {
      condition     = contains(["Audit", "Enforce"], local.policy_mode)
      error_message = "settings.policy_mode or settings.kyverno_policies.policy_mode must be Audit or Enforce."
    }

    precondition {
      condition     = length(local.managed_image_patterns) > 0
      error_message = "settings.managed_image_patterns or settings.kyverno_policies.managed_image_patterns must include at least one internal image pattern."
    }

    precondition {
      condition     = length(local.allowed_image_patterns) > 0
      error_message = "settings.allowed_image_patterns or settings.kyverno_policies.allowed_image_patterns must include at least one environment-specific allowed image pattern."
    }

    precondition {
      condition     = alltrue([for ns, q in local.quotas : alltrue([for acc, n in q : contains(keys(local.quota_resources), acc)])])
      error_message = "spec.quotas: each namespace's accelerators must be nvidia or neuron."
    }

    precondition {
      condition     = length(setintersection(keys(local.quotas), local.excluded_namespaces)) == 0
      error_message = "spec.quotas: system namespaces (kube-system, kube-public, kube-node-lease, kyverno) take no GPU quota."
    }

    precondition {
      condition     = alltrue([for ns, q in local.quotas : alltrue([for acc, n in q : try(n >= 0 && floor(n) == n, false)])])
      error_message = "spec.quotas: each quota must be a whole number, 0 or more."
    }
  }

  depends_on = [helm_release.kyverno]
}
