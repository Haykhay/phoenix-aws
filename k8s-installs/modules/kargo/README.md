# kargo

[Kargo](https://kargo.io) (chart `1.11.2`, pinned) for promoting versions
between stages, with Argo CD doing the syncing. Part of the **delivery** set.
One Kargo per environment:

| Cluster | Mode | Runs |
|---|---|---|
| `spec.management_cluster` (default `"1"`) | **management** | API + UI, management controller, garbage collector, a shard controller, Pod Identity for ECR warehouse scans |
| every other cluster of the environment | **spoke** | a shard controller (`<env_id>-<cluster>`) watching the management cluster's Kargo resources |

The mode follows from the unit's `cluster`; nothing else to configure.

**How a spoke reaches the management cluster** (same environment = same
account; same VPC assumed):

1. The management unit creates a `kargo-spoke-agent` service account, binds it
   to Kargo's controller roles, and publishes a kubeconfig with a rotating
   (300-day) token at `<organisation>/<env_id>/kargo/remote-kubeconfig`
   (output `remote_kubeconfig_secret`).
2. A spoke reads that output from the management unit's state
   (`<env_id>/<region>/k8s/<management cluster>/kargo`) — planning a spoke
   before its management cluster fails with a clear message — mounts the
   kubeconfig, and opens the management cluster's API (security group rule,
   443) to **its own node security group only**.

**UI:** `https://kargo.<internal zone>`, an HTTPRoute on istio's internal
gateway. Admin password and token-signing key at
`<organisation>/<env_id>/kargo/admin`. Deep links to each cluster's Argo CD
(`settings.argocd_urls` adds others).

Needs, applied first: argo-cd, cert-manager (Kargo's webhook certificates),
istio (management route). Promotion across environments (sandbox → stage →
prod) is a separate design.

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-platform` for the environment and region: the cluster this unit targets (the plan fails without it)
- `dns` (the management cluster's UI route) (the plan fails without it)

**Cluster components**, applied first on the same cluster (Backstage orders them from the catalog's `dependsOn`):

- `argo-cd`
- `cert-manager`
- `kargo` on the management cluster (`spec.management_cluster`, default `"1"`), for every other cluster

**You provide:**

- Nothing beyond the unit YAML; Backstage writes it.

**Access** (the workflow has all of this; locally you need it too):

- Terraform ≥ 1.15 and the `aws` CLI: the helm and kubernetes providers fetch an EKS token per call (`aws eks get-token`).
- Credentials for `Terraform-Role` in the unit's account, and the account's state bucket.
- Network reach to the cluster's **private** API endpoint: in the pipeline that is the `phoenix-mgmt` self-hosted runner in the management VPC.

### The unit file

```text
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/kargo.yaml
state: <env_id>/<region>/k8s/<cluster>/kargo/terraform.tfstate
```

One file per cluster. The identity block is the same as every unit's (see [`../../README.md`](../../README.md#a-units-yaml)); `spec` is described above. `spec.enabled: false` plans nothing.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd k8s-installs/modules/kargo
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/k8s/<cluster>/kargo/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/kargo.yaml
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`management_mode_on_cluster_1`, `spoke_mode_on_cluster_2`, `spoke_without_management_rejected`, `disabled_plans_nothing`).

### Outputs

| Output | |
|---|---|
| `mode` | management or spoke. |
| `shard` | This cluster's shard name (<env_id>-<cluster>). |
| `remote_kubeconfig_secret` | Management only: Secrets Manager secret with the kubeconfig spokes use. Spokes read this from this unit's state. |
| `url` | Kargo UI; management cluster only. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Nothing else on the cluster depends on it. Backstage destroys in reverse install order.
