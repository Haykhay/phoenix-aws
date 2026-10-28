output "endpoint" {
  description = "OpenAI-compatible endpoint of this model."
  value       = local.config.enabled ? "https://${local.hostname}/v1" : null
}

output "model" {
  description = "Served model name: what clients put in the request's model field."
  value       = local.served_name
}

output "llm_d_options" {
  description = "llm-d options on for this model ([] = the default path)."
  value       = local.llm_d_on
}

output "resource_summary" {
  value = {
    environment  = local.environment
    region       = local.region
    cluster      = local.cluster_key
    resource_set = "vllm"
    model        = local.served_name
    version      = local.config.version
    gpu          = local.config.gpu
    image_tag    = local.hardware.image.tag
    hardware     = local.config.hardware
    llm_d        = local.llm_d_on
  }
}
