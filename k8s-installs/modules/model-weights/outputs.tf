# Published only once the copy job succeeded (vllm checks the version against
# them): a failed or disabled copy leaves them null.
output "model" {
  description = "Model name used in paths and as vllm's served model name."
  value       = local.model
}

output "version" {
  description = "Pinned version copied: a Hugging Face commit SHA or the source's label."
  value       = local.copied ? local.version : null
}

output "source" {
  description = "Where the weights came from: type (huggingface, s3, https) and uri."
  value       = { type = local.source.type, uri = local.source.uri }
}

output "s3_prefix" {
  description = "Copied weights: s3://<bucket>/<model>/<version>/, complete once _COMPLETE exists."
  value       = local.copied ? local.s3_prefix : null
}

output "cache_path" {
  description = "Where model servers find the weights through the FSx cache."
  value       = local.copied ? "/models/${local.key}" : null
}

output "size_gib" {
  description = "Declared size of the weights in GiB; vllm sizes its startup budget from it."
  value       = local.copied ? local.config.size_gib : null
}

output "resource_summary" {
  value = {
    environment  = local.environment
    region       = local.region
    cluster      = local.cluster_key
    resource_set = "model-weights"
    model        = local.model
    version      = local.version
    source_type  = local.source.type
  }
}
