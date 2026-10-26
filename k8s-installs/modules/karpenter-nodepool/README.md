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

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-platform` for the environment and region: the cluster this unit targets (the plan fails without it)
- `core-platform` with `clusters.<cluster>.karpenter.enabled: true`

**Cluster components**, applied first on the same cluster (Backstage orders them from the catalog's `dependsOn`):

- `karpenter`

**You provide:**

- `spec.instance_families` (Backstage fills it from the `phoenix-gpu` entity; the plan fails without it).

**Access** (the workflow has all of this; locally you need it too):

- Terraform ≥ 1.15 and the `aws` CLI: the helm and kubernetes providers fetch an EKS token per call (`aws eks get-token`).
- Credentials for `Terraform-Role` in the unit's account, and the account's state bucket.
- Network reach to the cluster's **private** API endpoint: in the pipeline that is the `phoenix-mgmt` self-hosted runner in the management VPC.

### The unit file

```text
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/karpenter-nodepool.<gpu-type>.yaml
state: <env_id>/<region>/k8s/<cluster>/karpenter-nodepool.<gpu-type>/terraform.tfstate
```

One file per GPU type: `karpenter-nodepool.<gpu-type>.yaml`; the instance name is lowercase letters, digits and hyphens, and keeps two instances apart. The identity block is the same as every unit's (see [`../../README.md`](../../README.md#a-units-yaml)); `spec` is described above. `spec.enabled: false` plans nothing.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd k8s-installs/modules/karpenter-nodepool
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/k8s/<cluster>/karpenter-nodepool.<gpu-type>/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/karpenter-nodepool.<gpu-type>.yaml
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`gpu_pool_from_instance`, `two_gpu_types_do_not_collide`, `families_required`, `disabled_plans_nothing`).

### Outputs

| Output | |
|---|---|
| `node_pool` | NodePool name (gpu-<type>). |
| `node_selector` | What a GPU workload sets to land on this pool (plus a toleration for nvidia.com/gpu). |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Destroy these first, on the same cluster: `vllm`. Backstage destroys in reverse install order.
