output "kyverno_release_name" {
  value = try(helm_release.kyverno[0].name, null)
}

output "kyverno_policies_release_name" {
  value = try(helm_release.kyverno_policies[0].name, null)
}

output "kyverno_namespace" {
  value = try(helm_release.kyverno[0].namespace, null)
}

output "kyverno_policies_namespace" {
  value = try(helm_release.kyverno_policies[0].namespace, null)
}

output "chart_version" {
  value = local.config.chart_version
}

output "resource_summary" {
  value = {
    environment                   = local.environment
    region                        = local.region
    cluster                       = local.cluster_key
    resource_set                  = "kyverno"
    kyverno_release_name          = try(helm_release.kyverno[0].name, null)
    kyverno_policies_release_name = try(helm_release.kyverno_policies[0].name, null)
    policy_mode                   = local.policy_mode
  }
}
