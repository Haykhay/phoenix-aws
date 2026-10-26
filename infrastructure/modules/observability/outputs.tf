# Read by core-platform (observability remote state) to bind each cluster's
# service accounts to these roles.

output "bucket_name" {
  description = "Bucket holding <signal>/<cluster name>/... for every cluster in the account."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "The observability bucket's ARN."
  value       = aws_s3_bucket.this.arn
}

output "kms_key_arn" {
  description = "KMS key encrypting the bucket."
  value       = aws_kms_key.this.arn
}

output "writer_role_arns" {
  description = "Pod Identity role per signal: mimir, loki, tempo, langfuse."
  value       = { for signal, role in aws_iam_role.writer : signal => role.arn }
}

output "grafana_cloudwatch_role_arn" {
  description = "Pod Identity role for Grafana's CloudWatch data source."
  value       = aws_iam_role.grafana_cloudwatch.arn
}

output "signal_prefixes" {
  description = "Leading S3 prefix per signal; a cluster writes under <prefix><cluster name>/."
  value       = local.signal_prefixes
}
