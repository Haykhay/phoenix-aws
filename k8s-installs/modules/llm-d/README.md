# llm-d

Cluster prerequisites for the llm-d options a `vllm` unit can turn on
(`spec.llm_d`). A model with no options needs none of this: it is vLLM + the
endpoint picker, as before.

| Installs | |
|---|---|
| LeaderWorkerSet controller, chart `0.11.1` (2026-10-01) | `lws-system`: multi-node replicas (`multi_node`, `pd_disaggregation`, `wide_ep`) |
| KEDA, chart `2.21.0` (2026-09-23) | `keda`: scales models with `autoscaling` on, from the router's metrics in Mimir |

The Gateway API and `InferencePool` CRDs come from `istio`; each model's own
llm-d pieces come with its `vllm` unit.

It also records the pinned llm-d release, **`v0.10.0`** (2026-09-29; `v1.0.0`,
2026-10-20, is under two weeks old), and the options that release has a
well-lit path for. `vllm` reads both from this unit's state and rejects an
option not listed.

| Option | Guide in `v0.10.0` |
|---|---|
| `routing` | `optimized-baseline`, `precise-prefix-cache-routing` |
| `kv_offload` | `tiered-prefix-cache` |
| `flow_control` | `flow-control` |
| `autoscaling` | `workload-autoscaling` |
| `batch` | not offered: `batch-serving`'s gateway is experimental in `v0.10.0` |
| `multi_node`, `wide_ep` | `wide-ep` |
| `pd_disaggregation` | `pd-disaggregation` |

Moving to a newer llm-d: change `llm_d` and the list together, after reading
that release's guides. A release that lacks an option drops it from the list;
never back-port.

| `spec` | Default | |
|---|---|---|
| `lws_chart` | `0.11.1` | |
| `keda_chart` | `2.21.0` | |
| `llm_d` | `v0.10.0` | |

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-platform` for the environment and region: the cluster this unit targets (the plan fails without it)

**Cluster components**, applied first on the same cluster:

- `istio` (the InferencePool CRDs)

**Access** (the workflow has all of this; locally you need it too):

- Terraform ≥ 1.15 and the `aws` CLI: the helm and kubernetes providers fetch an EKS token per call (`aws eks get-token`).
- Credentials for `Terraform-Role` in the unit's account, and the account's state bucket.
- Network reach to the cluster's **private** API endpoint: in the pipeline that is the `phoenix-mgmt` self-hosted runner in the management VPC.

### The unit file

```text
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/llm-d.yaml
state: <env_id>/<region>/k8s/<cluster>/llm-d/terraform.tfstate
```

The identity block is the same as every unit's (see [`../../README.md`](../../README.md#a-units-yaml)). `spec.enabled: false` plans nothing and offers no options.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd k8s-installs/modules/llm-d
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/k8s/<cluster>/llm-d/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/llm-d.yaml
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_with_defaults`, `disabled_plans_nothing`).

### Outputs

| Output | |
|---|---|
| `version` | Pinned llm-d release whose guides vllm's options follow. |
| `supported_options` | spec.llm_d options available on this cluster with the pinned release; vllm rejects any other. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Used by: vllm units with any `spec.llm_d` option on. Destroy or switch those off first.
