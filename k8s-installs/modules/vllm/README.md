# vllm

One served model per unit: `vllm.<model slug>.yaml` (e.g.
`vllm.llama-3-8b.yaml`). Part of the **model-serving** set; Backstage writes
one per chosen model, with the platform's values from the `phoenix-model`
catalog entity.

| `spec` | Default | |
|---|---|---|
| `version` | **required** | the version `model-weights.<slug>` copied; the plan fails on a mismatch |
| `model` | the weights unit's `model` | served model name: what clients send as `model` |
| `gpu` | **required** | GPU type; its `karpenter-nodepool.<gpu>` unit must exist |
| `replicas` | `1` | |
| `gpus_per_replica` | `1` | tensor parallelism |
| `max_model_len`, `extra_args` | none | passed to vLLM |
| `image_tag` | `v0.31.0` | `vllm/vllm-openai`, pinned |
| `hardware` | `nvidia` | or `neuron` (Trainium/Inferentia): must match the pool's `accelerator`, or the plan fails |
| `tensor_parallel_size` | `gpus_per_replica` | on Neuron, NeuronCores (devices × cores per device) |
| `neuron_image_tag` | `0.24.0.1.1.0-neuronx-py313-sdk2.32.0-ubuntu24.04` | `public.ecr.aws/neuron/pytorch-inference-vllm-neuronx`, 2026-08-18 |

What it creates, in `models`:

- **vLLM** `vllm-<slug>` on the GPU pool (`nodeSelector phoenix/gpu=<gpu>`,
  tolerates `nvidia.com/gpu`), OpenAI-compatible API on 8000; Alloy scrapes its
  metrics. Loads the weights from the FSx cache: claim `model-cache` mounted
  read-only (subPath `weights`) at `/models`, `--model=/models/<model>/<version>`,
  `HF_HUB_OFFLINE=1`. Startup allows `max(1800, size_gib × 6)` seconds.
- **Prepull DaemonSet** `vllm-<slug>-prepull` on the same pool: pulls the
  serving image onto each node as it joins (no GPU requested), so a new
  replica waits only for the weights.
- **InferencePool** `vllm-<slug>-pool` with its endpoint picker (Gateway API
  Inference Extension chart `v1.5.0`, istio provider; requests trimmed to
  500m/1Gi for sandbox). The picker chooses a replica per request from
  vLLM's own load metrics.
- **HTTPRoute** on istio's internal gateway: `https://<slug>-<cluster>.<internal zone>/v1`
  (output `endpoint`), with an external-dns record.
**Neuron** (`hardware: neuron`, default path only, no llm-d options): the
Neuron build of vLLM, started as `python -m vllm.entrypoints.openai.api_server`
with the same `--model=/models/<model>/<version>` (its entrypoint runs the
command it is given), requesting `aws.amazon.com/neuron` × `gpus_per_replica`
and tolerating `aws.amazon.com/neuron`. Needs the `neuron-device-plugin` unit.

The plan fails clearly without the cluster's istio unit, the GPU pool unit,
the model's weights or the cache claim.

> **Breaking change.** vLLM no longer downloads from Hugging Face. Every
> existing `vllm.<slug>.yaml` needs `spec.version`, and `spec.model` is now the
> served name, not a Hugging Face ID: move the ID to
> `model-weights.<slug>.yaml` (`source.uri`) with its commit SHA as `version`.
> The Hugging Face token moved with it. Apply, in order: `model-store`,
> `model-cache.<cluster>`, `aws-fsx-csi-driver`, `model-weights.<slug>`, then
> this unit.

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-platform` for the environment and region: the cluster this unit targets (the plan fails without it)
- `model-store` in `<group>-shared/<region>` and `model-cache.<cluster>`: the weights bucket and the cluster's FSx cache
- `dns` (the model's hostname, through external-dns)

**Cluster components**, applied first on the same cluster (Backstage orders them from the catalog's `dependsOn`):

- `istio` (the plan fails without it)
- `karpenter-nodepool` (the plan fails without it)
- `aws-fsx-csi-driver` (the plan fails without it): state `<env_id>/<region>/k8s/<cluster>/aws-fsx-csi-driver/terraform.tfstate`
- `model-weights.<slug>`, same slug as this unit, at `spec.version` (the plan fails without it or on another version): state `<env_id>/<region>/k8s/<cluster>/model-weights.<slug>/terraform.tfstate`
- `nvidia-gpu-operator` (NVIDIA) or `neuron-device-plugin` (Neuron)
- `external-dns`

**You provide:**

- `spec.version` and `spec.gpu` (Backstage fills both; the plan fails without them).

**Access** (the workflow has all of this; locally you need it too):

- Terraform ≥ 1.15 and the `aws` CLI: the helm and kubernetes providers fetch an EKS token per call (`aws eks get-token`).
- Credentials for `Terraform-Role` in the unit's account, and the account's state bucket.
- Network reach to the cluster's **private** API endpoint: in the pipeline that is the `phoenix-mgmt` self-hosted runner in the management VPC.

### The unit file

```text
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/vllm.<model>.yaml
state: <env_id>/<region>/k8s/<cluster>/vllm.<model>/terraform.tfstate
```

One file per model: `vllm.<model>.yaml`; the instance name is lowercase letters, digits and hyphens, and keeps two instances apart. The identity block is the same as every unit's (see [`../../README.md`](../../README.md#a-units-yaml)); `spec` is described above. `spec.enabled: false` plans nothing.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd k8s-installs/modules/vllm
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/k8s/<cluster>/vllm.<model>/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/vllm.<model>.yaml
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_with_defaults`, `routes_through_inference_pool`, `two_models_do_not_collide`, `missing_gpu_pool_rejected`, `missing_istio_rejected`, `version_required`, `disabled_plans_nothing`, `served_name_overrides`, `startup_budget_scales_with_size`, `version_mismatch_rejected`, `missing_weights_rejected`, `missing_cache_rejected`, `prepull_on_model_pool`, `neuron_model`, `hardware_pool_mismatch_rejected`, `nvidia_by_default`).

### Outputs

| Output | |
|---|---|
| `endpoint` | OpenAI-compatible endpoint of this model. |
| `model` | Served model name: what clients put in the request's model field. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Nothing else on the cluster depends on it. Backstage destroys in reverse install order.
