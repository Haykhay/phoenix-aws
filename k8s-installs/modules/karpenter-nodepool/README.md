# karpenter-nodepool

One GPU node pool per GPU type: the unit file is
`karpenter-nodepool.<gpu type>.yaml` (e.g. `karpenter-nodepool.l4.yaml`), and
the type names the pool. Backstage writes one when a request picks a GPU type,
with the platform's values from the `phoenix-gpu` catalog entity.

| `spec` | Default | |
|---|---|---|
| `instance_families` | **required** | e.g. `[g6]` for l4, `[g5]` for a10g, `[g6e]` for l40s |
| `gpu_count_max` | `1` | largest instance by GPU count |
| `gpu_limit` | `max(8, 2 × gpu_count_max)` | total GPUs (Neuron devices) the pool may hold: two full nodes by default; the plan fails below one node |
| `capacity_types` | `[on-demand]` | after any reservations; `[]` with reservations = reserved only |
| `capacity_reservations` | `[]` | ODCRs or Capacity Blocks you hold: `[{ id: cr-… }]` or `[{ tags: { … } }]`; used first |
| `accelerator` | `nvidia` | or `neuron`: Trainium/Inferentia families (`trn1`, `trn2`, `inf2`); `gpu_count_max` and `gpu_limit` then count Neuron devices |
| `efa` | `false` | EFA networking for multi-node serving; EFA-capable families only (`p4d`, `p4de`, `p5`, `p5e`, `p5en`, `p6-b200`, `p6e-gb200`) |
| `volume_size` | `200Gi` | model images and weights are large |
| `ami_alias` | `al2023@latest` | Karpenter picks the NVIDIA variant for GPU instances |

Each pool (`gpu-<type>`, with its own `EC2NodeClass`) labels nodes
`phoenix/gpu=<type>` and taints them `nvidia.com/gpu=true:NoSchedule`: only a
workload that selects that label and tolerates the taint lands there (vLLM
does). Pools consolidate when empty after 5 minutes, so idle GPUs go away.

A Neuron pool taints `aws.amazon.com/neuron=true:NoSchedule`, labels
`phoenix/accelerator=neuron` (NVIDIA pools: `nvidia`), limits
`aws.amazon.com/neuron` and keeps the `al2023` alias, which resolves to the
AL2023 Neuron AMI for Neuron instances. It needs the `neuron-device-plugin`
unit in place of `nvidia-gpu-operator`.

With `efa: true` the pool also labels nodes `phoenix/efa=true`, adds a
security group allowing all traffic between its nodes (EFA needs it), and
installs the EFA device plugin (`aws-efa-k8s-device-plugin` chart `v0.5.33`,
2026-09-15) on its nodes; Karpenter attaches EFA interfaces to nodes whose pods
request `vpc.amazonaws.com/efa`.

Nodes need no Lustre package for the model cache: the FSx CSI driver's node
image carries the client.

## What you can achieve

Phoenix never buys capacity. It uses what you name, then on-demand if the pool
allows it. In practice:

| Instance class | On-demand realistically gives | Needs a reservation or Capacity Block |
|---|---|---|
| `g5`, `g6`, `g6e` (A10G, L4, L40S) | single-GPU and single-node models (≤ 8 GPUs); usually available in minutes | rarely; only for guaranteed peak scale |
| `p4d`, `p4de` (A100) | a single node now and then; often short in popular regions | multi-node serving, or anything that must start on time |
| `p5`, `p5e`, `p5en` (H100, H200) | occasionally one node; do not plan on it | a 70B model reliably, any multi-node, P/D or wide-EP setup |
| `p6-b200`, `p6e-gb200` (B200, GB200) | effectively none | everything |

A ~600B MoE model needs multi-node P5/P6 with EFA: plan on a reservation. A
model that can't get capacity is visible, never a silent hang: its pods stay
Pending with Karpenter's reason, which Grafana and Backstage show.

## Bringing a reservation or Capacity Block

1. Buy or book it yourself in the cluster's account and region (EC2 →
   Capacity Reservations, or Capacity Blocks for ML), in an AZ the cluster's
   node subnets cover. For multi-node EFA serving, one AZ.
2. Name it in the pool's unit file, by ID or by tags you put on it:

   ```yaml
   spec:
     instance_families: [p5]
     gpu_count_max: 8
     efa: true
     capacity_reservations: [{ id: cr-0123456789abcdef0 }]
     capacity_types: [on-demand]   # [] = reserved only, never on-demand
   ```

3. Apply the pool. Karpenter fills the reservation first; on-demand only when
   it's full and `capacity_types` allows it.
4. A Capacity Block ends at its end time and its instances are reclaimed:
   remove it from the file (or replace it) before then. Pods on it go Pending
   and fall back to on-demand if allowed.

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
- Optionally, reservations you hold (see above). The plan fails if `capacity_types` is empty with none named, or `efa: true` names a family without EFA.

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

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`gpu_pool_from_instance`, `two_gpu_types_do_not_collide`, `families_required`, `disabled_plans_nothing`, `on_demand_by_default`, `reservations_used_first`, `reserved_only`, `no_capacity_rejected`, `efa_pool`, `efa_needs_capable_family`, `nvidia_by_default`, `neuron_pool`, `unknown_accelerator_rejected`).

### Outputs

| Output | |
|---|---|
| `node_pool` | NodePool name (gpu-<type>). |
| `node_selector` | What a workload sets to land on this pool (plus a toleration for its accelerator's taint). |
| `accelerator` | nvidia or neuron: what the pool's devices are; vllm's spec.hardware must match. |
| `efa` | Whether the pool's nodes have EFA (label phoenix/efa=true): multi-node serving needs it. |
| `capacity_reservations` | Reservations or Capacity Blocks the pool uses first ([] = on-demand only). |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Destroy these first, on the same cluster: `vllm`. Backstage destroys in reverse install order.
