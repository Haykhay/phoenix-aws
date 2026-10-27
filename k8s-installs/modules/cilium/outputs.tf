output "release_name" {
  description = "Helm release name."
  value       = try(helm_release.this[0].name, null)
}

output "namespace" {
  description = "Namespace it runs in."
  value       = try(helm_release.this[0].namespace, null)
}

output "chart_version" {
  description = "Chart version installed."
  value       = try(helm_release.this[0].version, null)
}

output "resource_summary" {
  value = {
    environment   = local.environment
    region        = local.region
    cluster       = local.cluster_key
    resource_set  = "cilium"
    release_name  = try(helm_release.this[0].name, null)
    chart_version = try(helm_release.this[0].version, null)
  }
}
