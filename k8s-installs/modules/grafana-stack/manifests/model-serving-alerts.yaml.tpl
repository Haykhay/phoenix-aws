# The model-serving anti-goals, as Grafana alerts (Backstage reads them from
# Grafana). owner is the cluster's environment owner.
apiVersion: 1
groups:
  - orgId: 1
    name: model-serving
    folder: Model serving
    interval: 1m
    rules:
      - uid: model-start-slow
        title: ModelStartSlow
        condition: C
        for: 0m
        labels: { severity: warning, owner: "${owner}", cluster: "${cluster_name}" }
        annotations:
          summary: "{{ $labels.pod }} has been starting for over 30 minutes"
        data:
          - refId: A
            datasourceUid: mimir
            relativeTimeRange: { from: 600, to: 0 }
            model:
              refId: A
              instant: true
              expr: >-
                max by (pod) ((time() - kube_pod_created{namespace="models", pod=~"vllm-.*", pod!~".*-prepull-.*"})
                and on (pod) (kube_pod_status_ready{namespace="models", condition="false"} == 1))
          - refId: C
            datasourceUid: __expr__
            model:
              refId: C
              type: threshold
              expression: A
              conditions: [{ evaluator: { type: gt, params: [1800] } }]
      - uid: accelerator-idle
        title: AcceleratorIdle
        condition: C
        for: 0m
        labels: { severity: warning, owner: "${owner}", cluster: "${cluster_name}" }
        annotations:
          summary: "{{ $labels.model }}{{ $labels.instance_id }} used under 5% of its accelerators for 30 minutes"
        data:
          - refId: A
            datasourceUid: mimir
            relativeTimeRange: { from: 1800, to: 0 }
            model:
              refId: A
              instant: true
              expr: >-
                label_replace(avg by (pod) (avg_over_time(DCGM_FI_DEV_GPU_UTIL{namespace="models"}[30m])),
                "model", "$1", "pod", "vllm-(.+)-[^-]+-[^-]+")
                or (100 * avg by (instance_id) (avg_over_time(neuroncore_utilization_ratio[30m])))
          - refId: C
            datasourceUid: __expr__
            model:
              refId: C
              type: threshold
              expression: A
              conditions: [{ evaluator: { type: lt, params: [5] } }]
      - uid: model-pending-capacity
        title: ModelPendingCapacity
        condition: C
        for: 15m
        labels: { severity: warning, owner: "${owner}", cluster: "${cluster_name}" }
        annotations:
          summary: "{{ $labels.pod }} has waited over 15 minutes for capacity: see karpenter-nodepool's What you can achieve"
        data:
          - refId: A
            datasourceUid: mimir
            relativeTimeRange: { from: 600, to: 0 }
            model:
              refId: A
              instant: true
              expr: max by (pod) (kube_pod_status_unschedulable{namespace="models"})
          - refId: C
            datasourceUid: __expr__
            model:
              refId: C
              type: threshold
              expression: A
              conditions: [{ evaluator: { type: gt, params: [0] } }]
