# kyverno

[Kyverno](https://kyverno.io) plus a module-owned policies chart. Part of every
cluster's baseline.

The one policy today, `require-environment-images`, checks where internal
images come from:

| Setting (`spec.settings`, or under `kyverno_policies`) | Default | |
|---|---|---|
| `policy_mode` | `Audit` | `Audit` or `Enforce`; anything else fails the plan |
| `managed_image_patterns` | `*.dkr.ecr.*.amazonaws.com/*` | images that count as internal |
| `allowed_image_patterns` | `<account_id>.dkr.ecr.<region>.amazonaws.com/*` | where internal images must come from: the group account's own registry (its ECR pull-through cache) |
| `excluded_namespaces` | `kube-system`, `kube-public`, `kube-node-lease`, `kyverno` | |

So a pod pulling another group's ECR image is reported (Audit) or refused
(Enforce). Chart `3.8.1`, pinned. `spec.enabled: false` installs nothing.

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-platform` for the environment and region: the cluster this unit targets (the plan fails without it)

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
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/kyverno.yaml
state: <env_id>/<region>/k8s/<cluster>/kyverno/terraform.tfstate
```

One file per cluster. The identity block is the same as every unit's (see [`../../README.md`](../../README.md#a-units-yaml)); `spec` is described above. `spec.enabled: false` plans nothing.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd k8s-installs/modules/kyverno
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/k8s/<cluster>/kyverno/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/kyverno.yaml
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_with_defaults`, `bad_policy_mode_rejected`, `disabled_plans_nothing`).

### Outputs

| Output | |
|---|---|
| `kyverno_release_name` | Kyverno's Helm release name. |
| `kyverno_policies_release_name` | The policies chart's Helm release name. |
| `kyverno_namespace` | Namespace Kyverno runs in. |
| `kyverno_policies_namespace` | Namespace of the policies release. |
| `chart_version` | Chart version installed. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Nothing else on the cluster depends on it. Backstage destroys in reverse install order.
