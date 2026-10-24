output "endpoint" {
  description = "OpenAI-compatible endpoint of this model."
  value       = local.config.enabled ? "https://${local.hostname}/v1" : null
}

output "model" {
  value = local.config.model
}

output "resource_summary" {
  value = {
    environment  = local.environment
    region       = local.region
    cluster      = local.cluster_key
    resource_set = "vllm"
    model        = local.config.model
    gpu          = local.config.gpu
    image_tag    = local.config.image_tag
  }
}
