# Read by model-cache (FSx data repository association) and model-weights
# (the copy job's Pod Identity role) from this unit's remote state.

output "bucket_name" {
  description = "Bucket holding <model>/<version>/ for every model in the account and region."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "The weights bucket's ARN."
  value       = aws_s3_bucket.this.arn
}

output "kms_key_arn" {
  description = "KMS key encrypting the bucket."
  value       = aws_kms_key.this.arn
}

output "writer_role_arn" {
  description = "Pod Identity role for the model-weights copy job: list, read and write, never delete."
  value       = aws_iam_role.writer.arn
}

output "resource_summary" {
  value = {
    environment  = local.environment
    region       = local.region
    resource_set = "model-store"
    bucket       = aws_s3_bucket.this.bucket
  }
}
