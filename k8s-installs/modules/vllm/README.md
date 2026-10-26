# vllm

One served model per unit: `vllm.<model slug>.yaml` (e.g.
`vllm.llama-3-8b.yaml`). Part of the **model-serving** set; Backstage writes
one per chosen model, with the platform's values from the `phoenix-model`
catalog entity.

| `spec` | Default | |
|---|---|---|
| `model` | **required** | Hugging Face ID, e.g. `meta-llama/Llama-3.1-8B-Instruct` |
| `gpu` | **required** | GPU type; its `karpenter-nodepool.<gpu>` unit must exist |
| `replicas` | `1` | |
| `gpus_per_replica` | `1` | tensor parallelism |
| `max_model_len`, `extra_args` | none | passed to vLLM |
| `image_tag` | `v0.31.0` | `vllm/vllm-openai`, pinned |

What it creates, in `models`:

- **vLLM** `vllm-<slug>` on the GPU pool (`nodeSelector phoenix/gpu=<gpu>`,
  tolerates `nvidia.com/gpu`), OpenAI-compatible API on 8000; Alloy scrapes its
  metrics. Startup allows 30 minutes to download and load the model.
- **InferencePool** `vllm-<slug>-pool` with its endpoint picker (Gateway API
  Inference Extension chart `v1.5.0`, istio provider; requests trimmed to
  500m/1Gi for sandbox). The picker chooses a replica per request from
  vLLM's own load metrics.
- **HTTPRoute** on istio's internal gateway: `https://<slug>-<cluster>.<internal zone>/v1`
  (output `endpoint`), with an external-dns record.
- **Hugging Face token** (optional, for gated models) from
  `<organisation>/<env_id>/models/hf-token` (property `token`).

The plan fails clearly without the cluster's istio unit or the GPU pool unit.

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-platform` for the environment and region: the cluster this unit targets (the plan fails without it)
- `dns` (the model's hostname, through external-dns)

**Cluster components**, applied first on the same cluster (Backstage orders them from the catalog's `dependsOn`):

- `istio` (the plan fails without it)
- `karpenter-nodepool` (the plan fails without it)
- `nvidia-gpu-operator`
- `external-secrets`
- `external-dns`

**You provide:**

- `spec.model` and `spec.gpu` (Backstage fills both from the `phoenix-model` entity; the plan fails without them).
- For a gated model only: a Hugging Face token in Secrets Manager at `<organisation>/<env_id>/models/hf-token`, property `token`.

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

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_with_defaults`, `routes_through_inference_pool`, `two_models_do_not_collide`, `missing_gpu_pool_rejected`, `missing_istio_rejected`, `model_required`, `disabled_plans_nothing`).

### Outputs

| Output | |
|---|---|
| `endpoint` | OpenAI-compatible endpoint of this model. |
| `model` | Hugging Face ID of the model served. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Nothing else on the cluster depends on it. Backstage destroys in reverse install order.
