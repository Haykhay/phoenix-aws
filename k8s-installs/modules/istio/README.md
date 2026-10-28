# istio

Istio (charts `base` + `istiod` `1.30.1`, pinned) as the cluster's one
[Gateway API](https://gateway-api.sigs.k8s.io) implementation — for normal
services and for model serving. Part of both the **service** and
**model-serving** sets.

| Release | What |
|---|---|
| `gateway-api-crds` | Gateway API standard CRDs v1.5.1 + Inference Extension v1.6.2 `InferencePool` (vendored; the latter checked against the release asset's sha256) |
| `istio-base`, `istiod` | istiod with `ENABLE_GATEWAY_API_INFERENCE_EXTENSION=true`, so HTTPRoutes can target an `InferencePool` (vLLM) |
| `istio-extras` | Gateways `istio-internal` (always) and `istio-external` (`spec.settings.gateways.external.enabled: true`), each with a cert-manager wildcard certificate on the cluster's internal / public zone |

Each gateway gets an NLB from aws-load-balancer-controller (IP targets;
`internal` or `internet-facing`). Output `gateways` gives HTTPRoutes their
`parentRefs` and domain.

Needs, applied first: cert-manager (certificates), aws-load-balancer-controller
(NLBs), and the environment's dns unit (zones). The CRDs are not
`prevent_destroy`: a weekend teardown removes this unit after everything that
uses them.

The internal NLB keeps callers' own addresses
(`preserve_client_ip.enabled=true`; IP targets drop them by default): vllm's
model access is decided by the caller's CIDR. A caller in the same VPC as a
gateway pod can't reach that pod through the NLB with this on (AWS hairpin);
callers sit in other environments' VPCs, so that is not a path models use.

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-platform` for the environment and region: the cluster this unit targets (the plan fails without it)
- `dns`: the zones its gateways' wildcard certificates cover (the plan fails without it)

**Cluster components**, applied first on the same cluster (Backstage orders them from the catalog's `dependsOn`):

- `cert-manager`
- `aws-load-balancer-controller`

**You provide:**

- Nothing beyond the unit YAML; Backstage writes it.

**Access** (the workflow has all of this; locally you need it too):

- Terraform ≥ 1.15 and the `aws` CLI: the helm and kubernetes providers fetch an EKS token per call (`aws eks get-token`).
- Credentials for `Terraform-Role` in the unit's account, and the account's state bucket.
- Network reach to the cluster's **private** API endpoint: in the pipeline that is the `phoenix-mgmt` self-hosted runner in the management VPC.

### The unit file

```text
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/istio.yaml
state: <env_id>/<region>/k8s/<cluster>/istio/terraform.tfstate
```

One file per cluster. The identity block is the same as every unit's (see [`../../README.md`](../../README.md#a-units-yaml)); `spec` is described above. `spec.enabled: false` plans nothing.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd k8s-installs/modules/istio
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/k8s/<cluster>/istio/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/istio.yaml
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_with_defaults`, `gateway_and_inference_crds`, `external_gateway_on_request`, `no_dns_rejected`, `disabled_plans_nothing`, `internal_nlb_preserves_client_ip`).

### Outputs

| Output | |
|---|---|
| `gateways` | Gateways HTTPRoutes attach to (parentRefs), with the zone their hostnames live in. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Destroy these first, on the same cluster: `argo-cd`, `langfuse`, `vllm`. Backstage destroys in reverse install order.
