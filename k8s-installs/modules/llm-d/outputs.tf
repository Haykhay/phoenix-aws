output "version" {
  description = "Pinned llm-d release whose guides vllm's options follow."
  value       = local.config.llm_d
}

output "supported_options" {
  description = "spec.llm_d options available on this cluster with the pinned release; vllm rejects any other."
  value       = local.config.enabled ? local.supported_options : []
}

output "resource_summary" {
  value = {
    environment  = local.environment
    region       = local.region
    cluster      = local.cluster_key
    resource_set = "llm-d"
    llm_d        = local.config.llm_d
    lws_chart    = try(helm_release.lws[0].version, null)
    keda_chart   = try(helm_release.keda[0].version, null)
  }
}
