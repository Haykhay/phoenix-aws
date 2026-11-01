locals {
  defaults = {
    enabled       = true
    chart_version = "1.10.0"                                      # neuron-helm-chart, 2026-08-19 (Neuron SDK 2.32)
    monitor_image = "public.ecr.aws/neuron/neuron-monitor:1.12.0" # 2026-08-18
  }

  config = merge(local.defaults, module.context.spec)

  neuron_toleration = { key = "aws.amazon.com/neuron", operator = "Exists", effect = "NoSchedule" }
}
