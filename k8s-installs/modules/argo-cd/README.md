# argo-cd

One [Argo CD](https://argo-cd.readthedocs.io) per cluster (chart `7.9.1`, Argo
CD 2.14, pinned) in `argocd`. Part of the **delivery** set, installed with every
workload type; Kargo uses it to sync promoted versions.

| `spec` | Default | |
|---|---|---|
| `repo_url` | **required** | the GitHub repository the bootstrap app watches, e.g. `git@github.com:acme/phoenix-apps.git` |
| `bootstrap_path` | `clusters/helm` | chart path in that repo |
| `ecr_cache_prefix` | `artifactory` | the group account's ECR pull-through prefix, for OCI Helm charts |

- **Bootstrap:** an `Application` syncing `<bootstrap_path>` with the values file
  `clusters/<env_id>-<cluster>.yaml` from the same repo.
- **Repository access:** an ED25519 deploy key generated here. Add output
  `repo_public_key` to the GitHub repo as a read-only deploy key. The chart's
  built-in known hosts already include github.com.
- **OCI charts:** from the group account's ECR (`repo-server` has Pod Identity
  read on `<ecr_cache_prefix>/*`; registry credentials refresh every 6h through
  an external-secrets `ECRAuthorizationToken`).
- **UI:** `https://argocd-<cluster>.<internal zone>`, an HTTPRoute on istio's
  internal gateway with an external-dns record (output `url`). Local admin only
  for now (password in output `admin_secret`); Entra SSO comes with Backstage's
  Entra toggle.
- **Secrets:** `<organisation>/<env_id>/argo-cd/<cluster>/{admin,repo-ssh-key}`.

Needs, applied first: istio (route), external-secrets (ECR credentials),
cert-manager (through istio).

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-platform` for the environment and region: the cluster this unit targets (the plan fails without it)
- `dns` (the UI route's zone) (the plan fails without it)
- `ecr` in the group account (the pull-through cache OCI charts come from)

**Cluster components**, applied first on the same cluster (Backstage orders them from the catalog's `dependsOn`):

- `istio`
- `external-secrets`

**You provide:**

- `spec.repo_url`: the GitHub repository Argo CD's bootstrap app watches (the plan fails without it).
- After the first apply: add output `repo_public_key` to that repository as a **read-only deploy key**.
- In that repository: the chart at `spec.bootstrap_path` and a values file `clusters/<env_id>-<cluster>.yaml`.

**Access** (the workflow has all of this; locally you need it too):

- Terraform ≥ 1.15 and the `aws` CLI: the helm and kubernetes providers fetch an EKS token per call (`aws eks get-token`).
- Credentials for `Terraform-Role` in the unit's account, and the account's state bucket.
- Network reach to the cluster's **private** API endpoint: in the pipeline that is the `phoenix-mgmt` self-hosted runner in the management VPC.

### The unit file

```text
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/argo-cd.yaml
state: <env_id>/<region>/k8s/<cluster>/argo-cd/terraform.tfstate
```

One file per cluster. The identity block is the same as every unit's (see [`../../README.md`](../../README.md#a-units-yaml)); `spec` is described above. `spec.enabled: false` plans nothing.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd k8s-installs/modules/argo-cd
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/k8s/<cluster>/argo-cd/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/argo-cd.yaml
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_with_defaults`, `ecr_pull_through_scoped`, `repo_url_required`, `personal_env_names_fit`, `disabled_plans_nothing`).

### Outputs

| Output | |
|---|---|
| `url` | Argo CD UI, on istio's internal gateway. |
| `repo_public_key` | Add to the GitHub repository (spec.repo_url) as a read-only deploy key. |
| `admin_secret` | Secrets Manager secret holding the local admin password. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Destroy these first, on the same cluster: `kargo`. Backstage destroys in reverse install order.
