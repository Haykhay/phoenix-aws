# cert-manager

[cert-manager](https://cert-manager.io) (chart `v1.20.2`, pinned) with two
Let's Encrypt `ClusterIssuer`s, `letsencrypt-prod` and `letsencrypt-staging`,
solving DNS-01 through Route53 in the cluster's own public and internal zones.
Pod Identity: `cert-manager/cert-manager` → `<name_prefix>-cert-manager`,
allowed to change only those two zones. Part of the **service** set; istio's
wildcard certificates come from it.

| `spec.settings` | Default | |
|---|---|---|
| `acme_email` | none | Let's Encrypt no longer needs an account email |
| `install_crds` | `true` | |
| `hosted_zone_arns` | the cluster's two zones | |
| `enable_gateway_api` | `false` | see below |

`enable_gateway_api` is off: certificates are explicit `Certificate` resources,
and with it on cert-manager will not start until the Gateway API CRDs exist —
which istio installs, after cert-manager. Order: cert-manager →
aws-load-balancer-controller → istio.

The plan fails clearly without the environment's dns unit.

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-platform` for the environment and region: the cluster this unit targets (the plan fails without it)
- `dns`: the cluster's public and internal zones (DNS-01 challenges); the public zone must be delegated so Let's Encrypt can resolve it (the plan fails without it)

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
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/cert-manager.yaml
state: <env_id>/<region>/k8s/<cluster>/cert-manager/terraform.tfstate
```

One file per cluster. The identity block is the same as every unit's (see [`../../README.md`](../../README.md#a-units-yaml)); `spec` is described above. `spec.enabled: false` plans nothing.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd k8s-installs/modules/cert-manager
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/k8s/<cluster>/cert-manager/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/cert-manager.yaml
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_with_defaults`, `issuers_use_cluster_zone`, `personal_env_names_fit`, `no_dns_rejected`, `disabled_plans_nothing`).

### Outputs

| Output | |
|---|---|
| `cluster_issuers` | ClusterIssuers to reference from a Certificate. |
| `role_arn` | IAM role its service account uses, through Pod Identity. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Destroy these first, on the same cluster: `clickhouse-operator`, `istio`, `kargo`, `langfuse`. Backstage destroys in reverse install order.
