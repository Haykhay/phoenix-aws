# karpenter-nodepool

One GPU node pool per GPU type: the unit file is
`karpenter-nodepool.<gpu type>.yaml` (e.g. `karpenter-nodepool.l4.yaml`), and
the type names the pool. Backstage writes one when a request picks a GPU type,
with the platform's values from the `phoenix-gpu` catalog entity.

| `spec` | Default | |
|---|---|---|
| `instance_families` | **required** | e.g. `[g6]` for l4, `[g5]` for a10g, `[g6e]` for l40s |
| `gpu_count_max` | `1` | largest instance by GPU count |
| `gpu_limit` | `8` | total GPUs the pool may hold |
| `capacity_types` | `[on-demand]` | |
| `volume_size` | `200Gi` | model images and weights are large |
| `ami_alias` | `al2023@latest` | Karpenter picks the NVIDIA variant for GPU instances |

Each pool (`gpu-<type>`, with its own `EC2NodeClass`) labels nodes
`phoenix/gpu=<type>` and taints them `nvidia.com/gpu=true:NoSchedule`: only a
workload that selects that label and tolerates the taint lands there (vLLM
does). Pools consolidate when empty after 5 minutes, so idle GPUs go away.

Needs the cluster's `karpenter` unit (controller + CRDs) applied first, and the
`nvidia-gpu-operator` unit for the GPUs to be schedulable.
