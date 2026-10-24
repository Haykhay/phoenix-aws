output "release_name" {
  value = try(helm_release.this[0].name, null)
}

output "namespace" {
  value = try(helm_release.this[0].namespace, null)
}

output "chart_version" {
  value = try(helm_release.this[0].version, null)
}

output "resource_summary" {
  value = {
    environment   = local.environment
    region        = local.region
    cluster       = local.cluster_key
    resource_set  = "valkey-redis"
    release_name  = try(helm_release.this[0].name, null)
    namespace     = try(helm_release.this[0].namespace, null)
    chart_version = try(helm_release.this[0].version, null)
  }
}
