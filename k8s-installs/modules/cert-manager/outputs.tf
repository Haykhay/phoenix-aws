output "cluster_issuers" {
  value = ["letsencrypt-prod", "letsencrypt-staging"]
}

output "role_arn" {
  value = try(aws_iam_role.this[0].arn, null)
}

output "resource_summary" {
  value = {
    environment   = local.environment
    region        = local.region
    cluster       = local.cluster_key
    resource_set  = "cert-manager"
    chart_version = try(helm_release.this[0].version, null)
  }
}
