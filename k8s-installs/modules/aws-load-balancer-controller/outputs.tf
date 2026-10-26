output "release_name" {
  description = "Helm release name."
  value       = try(helm_release.this[0].name, null)
}

output "role_arn" {
  description = "IAM role its service account uses, through Pod Identity."
  value       = try(aws_iam_role.this[0].arn, null)
}

output "resource_summary" {
  value = {
    environment   = local.environment
    region        = local.region
    cluster       = local.cluster_key
    resource_set  = "aws-load-balancer-controller"
    chart_version = try(helm_release.this[0].version, null)
    role_arn      = try(aws_iam_role.this[0].arn, null)
  }
}
