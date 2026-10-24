locals {
  defaults = {
    enabled       = true
    chart_version = "3.8.1"
    app_version   = ""
    settings      = {}
  }

  config = merge(local.defaults, module.context.spec)

  kyverno_enabled         = try(local.config.settings.enabled, true)
  kyverno_release_name    = try(local.config.settings.release_name, "kyverno")
  kyverno_namespace       = try(local.config.settings.namespace, "kyverno")
  kyverno_chart           = try(local.config.settings.chart, "kyverno")
  kyverno_repository      = try(local.config.settings.repository, "https://kyverno.github.io/kyverno/")
  kyverno_chart_version   = local.config.chart_version
  kyverno_values          = coalesce(try(local.config.settings.values, null), {})
  kyverno_wait            = try(local.config.settings.wait, true)
  kyverno_wait_for_jobs   = try(local.config.settings.wait_for_jobs, true)
  kyverno_timeout         = try(local.config.settings.timeout, 600)
  kyverno_atomic          = try(local.config.settings.atomic, true)
  kyverno_cleanup_on_fail = try(local.config.settings.cleanup_on_fail, true)

  kyverno_policies_enabled         = try(local.config.settings.kyverno_policies.enabled, true)
  kyverno_policies_release_name    = try(local.config.settings.kyverno_policies.release_name, "kyverno-policies")
  kyverno_policies_namespace       = try(local.config.settings.kyverno_policies.namespace, local.kyverno_namespace)
  kyverno_policies_chart           = try(local.config.settings.kyverno_policies.chart, "${path.module}/manifests/kyverno-policies")
  kyverno_policies_repository      = try(local.config.settings.kyverno_policies.repository, null)
  kyverno_policies_chart_version   = try(local.config.settings.kyverno_policies.chart_version, null)
  kyverno_policies_values          = merge(local.kyverno_policies_default_values, coalesce(try(local.config.settings.kyverno_policies.values, null), {}))
  kyverno_policies_wait            = try(local.config.settings.kyverno_policies.wait, true)
  kyverno_policies_wait_for_jobs   = try(local.config.settings.kyverno_policies.wait_for_jobs, true)
  kyverno_policies_timeout         = try(local.config.settings.kyverno_policies.timeout, 600)
  kyverno_policies_atomic          = try(local.config.settings.kyverno_policies.atomic, true)
  kyverno_policies_cleanup_on_fail = try(local.config.settings.kyverno_policies.cleanup_on_fail, true)
  policy_mode                      = try(local.config.settings.kyverno_policies.policy_mode, try(local.config.settings.policy_mode, "Audit"))
  # Platform defaults: any ECR image counts as internal, and internal images
  # must come from the group account's own registry (its pull-through cache).
  managed_image_patterns = try(local.config.settings.kyverno_policies.managed_image_patterns, try(local.config.settings.managed_image_patterns, ["*.dkr.ecr.*.amazonaws.com/*"]))
  allowed_image_patterns = try(local.config.settings.kyverno_policies.allowed_image_patterns, try(local.config.settings.allowed_image_patterns, ["${local.account_id}.dkr.ecr.${local.region}.amazonaws.com/*"]))
  excluded_namespaces = try(local.config.settings.kyverno_policies.excluded_namespaces, [
    "kube-system",
    "kube-public",
    "kube-node-lease",
    local.kyverno_namespace,
  ])

  kyverno_policies_default_values = {
    environmentName = local.environment
    policyMode      = local.policy_mode
    environmentImagePolicy = {
      enabled              = true
      managedImagePatterns = local.managed_image_patterns
      allowedImagePatterns = local.allowed_image_patterns
      excludedNamespaces   = local.excluded_namespaces
    }
  }
}
