output "release_name" {
  value = try(helm_release.this[0].name, null)
}

output "namespace" {
  value = try(helm_release.this[0].namespace, null)
}

output "role_arn" {
  description = "Pod Identity role of the operator."
  value       = try(aws_iam_role.this[0].arn, null)
}

output "secret_path" {
  description = "Prefix every secret/parameter this cluster can read lives under: <organisation>/<env_id>."
  value       = local.secret_path
}

output "cluster_secret_stores" {
  value = ["aws-secretsmanager", "aws-ssm"]
}

output "resource_summary" {
  value = {
    environment   = local.environment
    region        = local.region
    cluster       = local.cluster_key
    resource_set  = "external-secrets"
    release_name  = try(helm_release.this[0].name, null)
    chart_version = try(helm_release.this[0].version, null)
    role_arn      = try(aws_iam_role.this[0].arn, null)
  }
}
