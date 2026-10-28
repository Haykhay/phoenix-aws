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
**llm-d options** (`spec.llm_d`, all `false`). All off is the default path:
vLLM + the Inference Extension's endpoint picker, no llm-d unit needed. Any
option on swaps the picker for the llm-d router (`llm-d-router-gateway`
`v0.11.0`, from llm-d `v0.10.0`) under the same pool name, so the HTTPRoute
and the endpoint stay the same; its picker config is built from the options.
Output `llm_d_options` lists what is on.

- **`routing`**: the picker scores by prefix-cache affinity (`prefix-cache-scorer`),
  queue depth and KV-cache use, so repeated prompts and sessions land where
  their cache is warm.
- **`kv_offload`**: vLLM's `OffloadingConnector` keeps evicted KV blocks in CPU
  memory (`kv_offload_cpu_gib`, default `100`).
- **`flow_control`**: requests queue in the picker in three priority bands
  (100, 0, −10), round-robin fair within a band by
  `x-gateway-inference-fairness-id` (Task 10 sets it per caller), instead of
  piling onto saturated replicas.
- **`autoscaling`**: a KEDA ScaledObject on the router's running-request count
  in Mimir (`autoscale_target` per replica, default `16`), between
  `max(1, min_replicas)` and `max_replicas` (default `4`); never to zero. A
  5-minute stabilisation window covers model start. Needs the llm-d unit's KEDA.
- **`multi_node`**: each replica is a LeaderWorkerSet group of
  `nodes_per_replica` nodes, `gpus_per_replica` each: tensor parallel inside a
  node, pipeline parallel across nodes. Workers run `--headless`.
- **`pd_disaggregation`**: separate prefill (`prefill_replicas`) and decode
  (`decode_replicas`) sets; decode sits behind llm-d's routing sidecar
  (`v0.11.0`) and KV moves over NIXL, on EFA (`LIBFABRIC`) when the pool has it.
  With `kv_offload` too, both connectors run (`MultiConnector`).
- **`wide_ep`**: expert parallelism over data-parallel ranks across the LWS
  group (`--enable-expert-parallel`, DP size = nodes × GPUs). Needs `multi_node`.
- **`batch`**: deferred — llm-d `v0.10.0`'s batch gateway is experimental; the
  plan rejects it as not in the release.

On an EFA pool, multi_node, P/D and wide EP use AWS's vLLM image with EFA
(`public.ecr.aws/deep-learning-containers/vllm:<efa_image_tag>`, the image
llm-d's AWS overlay uses), request `vpc.amazonaws.com/efa`
(`efa_interfaces`, default `1`) and add `IPC_LOCK`.

The plan checks the options (`option_checks`) and names every rule broken:
`nvidia_only`, `wide_ep_needs_multi_node`, `multi_node_needs_nodes`,
`efa_required` (multi_node, pd_disaggregation, wide_ep need a pool with
`efa: true`), `llm_d_installed` (the cluster's `llm-d` unit, only when an option
is on) and `available_in_release` (the option is in that unit's
`supported_options`).

The day-one ~600B MoE (`tests/fixtures/llm-d/vllm.deepseek.yaml`): multi_node +
wide_ep + pd_disaggregation + routing, 8 GPUs × 2 nodes per group, on an EFA
P5/P6 pool. That needs a reservation in practice: see
[`karpenter-nodepool`'s "Bringing a reservation or Capacity Block"](../karpenter-nodepool/README.md#bringing-a-reservation-or-capacity-block).

## Who can call this model

The team that deploys a model owns it. `spec.access` (Backstage writes it):

```yaml
access:
  owner_cidrs: [10.20.0.0/16]          # the owner environment's VPC CIDR(s)
  consumers:                           # uat/prod only; approved in Backstage
    quant-research: { cidrs: [10.30.0.0/16], weight: 1 }
  oidc:                                # optional
    issuer: https://idp.example.com
    jwks_uri: https://idp.example.com/jwks
    audiences: [phoenix-models]
    consumer_claim: azp
```

- **Network identity (default).** Each environment's VPC has its own
  IPAM-allocated CIDR, so the caller's address says which environment it is.
  On istio's internal gateway an `AuthorizationPolicy` refuses this model's
  hostname to any address outside `owner_cidrs` and the consumers' CIDRs (a
  DENY with `notIpBlocks`: an ALLOW would close every other host on the shared
  gateway). An `EnvoyFilter` (Lua) sets `x-phoenix-consumer`, and flow
  control's `x-gateway-inference-fairness-id`, to the matching name (the
  owner team, a consumer, or `unknown`), replacing whatever the client sent.
  Granularity: per environment. It needs istio's internal NLB to keep client
  addresses, which the `istio` unit sets.
- **OIDC (option).** With `oidc.issuer`, a `RequestAuthentication` validates
  tokens against `jwks_uri` and a second policy refuses requests without a
  valid token from that issuer, on top of the network rule. The consumer is
  the token's `consumer_claim` (default `azp`), written over any client-sent
  header. Granularity: per service or person. Any IdP works (Okta, Entra ID,
  Cognito, Keycloak, …).
- **sandbox / stage**: owner only. A non-empty `consumers` fails the plan
  (`consumers_only_uat_prod`).
- **uat / prod**: with any consumer, `llm_d.flow_control` is forced on (NVIDIA
  only; a shared Neuron model stays on the default path), so one team can't
  starve the others; consumers start equal (round-robin per
  consumer). `weight` is recorded for the owner's priority lever, which
  llm-d `v0.10.0`'s fairness policy does not take yet.
- **Fails closed.** With `owner_cidrs` empty the owner is the cluster's own VPC
  CIDR (from core-network's state); the plan fails if it can't find it. A
  consumer without CIDRs fails the plan. A model is never open to the whole
  segment.

**Segment note.** sandbox, stage and uat share the non-production transit
gateway segment (prod is isolated), so a sandbox or stage VPC can route to a
uat model: the AuthorizationPolicy, not routing, is what keeps them off it.

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
- `core-network`: the cluster's VPC CIDR is the owner's identity by default (the plan fails without it)
- `dns` (the model's hostname, through external-dns)

**Cluster components**, applied first on the same cluster (Backstage orders them from the catalog's `dependsOn`):

- `istio` (the plan fails without it)
- `karpenter-nodepool` (the plan fails without it)
- `aws-fsx-csi-driver` (the plan fails without it): state `<env_id>/<region>/k8s/<cluster>/aws-fsx-csi-driver/terraform.tfstate`
- `model-weights.<slug>`, same slug as this unit, at `spec.version` (the plan fails without it or on another version): state `<env_id>/<region>/k8s/<cluster>/model-weights.<slug>/terraform.tfstate`
- `nvidia-gpu-operator` (NVIDIA) or `neuron-device-plugin` (Neuron)
- `llm-d`, only when a `spec.llm_d` option is on (the plan fails without it)
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

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_with_defaults`, `routes_through_inference_pool`, `two_models_do_not_collide`, `missing_gpu_pool_rejected`, `missing_istio_rejected`, `version_required`, `disabled_plans_nothing`, `served_name_overrides`, `startup_budget_scales_with_size`, `version_mismatch_rejected`, `missing_weights_rejected`, `missing_cache_rejected`, `prepull_on_model_pool`, `neuron_model`, `hardware_pool_mismatch_rejected`, `nvidia_by_default`, `no_options_needs_no_llm_d`, `routing_allowed`, `llm_d_not_installed_rejected`, `invalid_combinations_rejected_*` (four), `multi_node_needs_two_nodes`, `multi_node_on_efa_pool_allowed`, `default_render_unchanged`, `option_routing`, `option_kv_offload`, `option_flow_control`, `option_autoscaling`, `option_multi_node`, `option_wide_ep_single_node`, `option_pd_with_kv_offload`, `wide_ep_600b_fixture`, `uat_allows_only_owner_and_consumers`, `shared_allows_consumers`, `consumer_header_overwritten`, `consumers_only_uat_prod`, `shared_forces_flow_control`, `oidc_option`).

### Outputs

| Output | |
|---|---|
| `endpoint` | OpenAI-compatible endpoint of this model. |
| `model` | Served model name: what clients put in the request's model field. |
| `llm_d_options` | llm-d options on for this model ([] = the default path). |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Nothing else on the cluster depends on it. Backstage destroys in reverse install order.
