# Cluster-wide prerequisites for llm-d options on vllm units. The Gateway API
# and InferencePool CRDs come from istio; each model's llm-d pieces come with
# its vllm unit. This adds the LeaderWorkerSet controller (multi-node serving,
# P/D, wide EP) and records the pinned llm-d release and its options.
resource "helm_release" "lws" {
  count            = local.config.enabled ? 1 : 0
  name             = "lws"
  repository       = "oci://registry.k8s.io/lws/charts"
  chart            = "lws"
  version          = local.config.lws_chart
  namespace        = "lws-system"
  create_namespace = true
}
