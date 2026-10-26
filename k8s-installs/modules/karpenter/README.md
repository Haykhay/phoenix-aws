# karpenter

The [Karpenter](https://karpenter.sh) controller plus a default
`EC2NodeClass`/`NodePool` (both named `default`). Part of every cluster's
baseline. The AWS side — controller role (Pod Identity), node role, SQS
interruption queue — is infrastructure's core-platform (`clusters.<key>.karpenter.enabled`);
this module reads those facts back through `modules/cluster` and fails the
plan clearly if they are missing.

| Default pool | |
|---|---|
| AMI | `al2023@latest` |
| Capacity | on-demand + spot, amd64, categories c/m/r, generation > 5 |
| Limit | 64 vCPU |
| Disruption | consolidate when empty or underutilised after 1m; nodes expire after 7 days |
| Subnets / security group | core-platform's node subnets and node security group, **by ID** (no discovery tags) |
| Node tags | the unit's tags + `Cluster` |

GPU capacity is not here: each GPU type is its own `karpenter-nodepool.<type>`
unit. Chart `1.14.0` (oci://public.ecr.aws/karpenter), pinned; core-platform's
controller policy covers Karpenter up to 1.15 — re-check it before bumping.

The node class and pool are a local Helm chart (`manifests/karpenter-defaults`),
not `kubernetes_manifest`: their CRDs arrive with the controller chart, and
`kubernetes_manifest` needs CRDs to exist at plan time.

`spec` overrides: `ami_alias`, `capacity_types`, `instance_category`,
`instance_gen_min`, `cpu_limit`, `expire_after`, `consolidate_after`, `enabled`.

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-platform` for the environment and region: the cluster this unit targets (the plan fails without it)
- `core-platform` with `clusters.<cluster>.karpenter.enabled: true` (controller role, node role, interruption queue)

**Cluster components**, applied first on the same cluster (Backstage orders them from the catalog's `dependsOn`):

- None.

**You provide:**

- Nothing beyond the unit YAML; Backstage writes it.

**Access** (the workflow has all of this; locally you need it too):

- Terraform ≥ 1.15 and the `aws` CLI: the helm and kubernetes providers fetch an EKS token per call (`aws eks get-token`).
- Credentials for `Terraform-Role` in the unit's account, and the account's state bucket.
- Network reach to the cluster's **private** API endpoint: in the pipeline that is the `phoenix-mgmt` self-hosted runner in the management VPC.

### The unit file

```text
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/karpenter.yaml
state: <env_id>/<region>/k8s/<cluster>/karpenter/terraform.tfstate
```

One file per cluster. The identity block is the same as every unit's (see [`../../README.md`](../../README.md#a-units-yaml)); `spec` is described above. `spec.enabled: false` plans nothing.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd k8s-installs/modules/karpenter
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/k8s/<cluster>/karpenter/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/karpenter.yaml
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_with_defaults`, `requires_core_platform_karpenter`, `disabled_plans_nothing`).

### Outputs

| Output | |
|---|---|
| `namespace` | Namespace it runs in. |
| `node_class` | What GPU node pools (karpenter-nodepool) reuse for their own EC2NodeClass. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Destroy these first, on the same cluster: `karpenter-nodepool`. Backstage destroys in reverse install order.
