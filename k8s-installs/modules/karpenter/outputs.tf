output "namespace" {
  value = local.namespace
}

output "node_class" {
  description = "What GPU node pools (karpenter-nodepool) reuse for their own EC2NodeClass."
  value       = local.node_class
}

output "resource_summary" {
  value = {
    environment   = local.environment
    region        = local.region
    cluster       = local.cluster_key
    resource_set  = "karpenter"
    chart_version = local.config.chart_version
    node_pool     = "default"
  }
}
