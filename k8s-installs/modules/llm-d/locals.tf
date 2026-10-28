locals {
  defaults = {
    enabled   = true
    lws_chart = "0.11.1"  # LeaderWorkerSet, 2026-10-01
    llm_d     = "v0.10.0" # 2026-09-29; v1.0.0 (2026-10-20) is under two weeks old
  }

  config = merge(local.defaults, module.context.spec)

  # Options with a well-lit path (guides/) in the pinned release; vllm rejects
  # any other. Pinning a release that lacks one: remove it here, never back-port.
  supported_options = [
    "routing",           # optimized-baseline, precise-prefix-cache-routing
    "kv_offload",        # tiered-prefix-cache
    "flow_control",      # flow-control
    "autoscaling",       # workload-autoscaling
    "batch",             # batch-serving
    "multi_node",        # wide-ep (LeaderWorkerSet)
    "pd_disaggregation", # pd-disaggregation
    "wide_ep",           # wide-ep
  ]
}
