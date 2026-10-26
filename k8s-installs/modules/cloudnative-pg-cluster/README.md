# cloudnative-pg-cluster

One PostgreSQL cluster ([CloudNativePG](https://cloudnative-pg.io) `Cluster`)
per unit: `cloudnative-pg-cluster.<instance>.yaml` → cluster `cnpg-<instance>`
in `cnpg-system`. Needs the `cloudnative-pg` operator unit and
`external-secrets`. Used for a **postgres** request in sandbox; stage and above
use infrastructure's managed `data-rds`.

| `spec` | Default | |
|---|---|---|
| `instances` | `1` | |
| `storage_size` | `10Gi` | |
| `databases` | one, named after the instance | `[{ name, owner? }]`; owner defaults to the name |
| `nlb_enabled` | `false` | internal NLB + `<cluster>.<internal zone>` record |

**Credentials** come from infrastructure's `credentials` module (policy
`postgres_incluster`) and are published where external-secrets may read them:

```text
<organisation>/<env_id>/postgres/in-cluster/<instance>            superuser
<organisation>/<env_id>/postgres/in-cluster/<instance>/<database> each database (address, port, endpoint, database)
```

The chart's `ExternalSecret`s turn them into the Kubernetes secrets CNPG uses.
Output `cluster` lists the service address and every secret name.

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-platform` for the environment and region: the cluster this unit targets (the plan fails without it)
- `dns`, only with `nlb_enabled: true` (the NLB's hostname) (the plan fails without it)

**Cluster components**, applied first on the same cluster (Backstage orders them from the catalog's `dependsOn`):

- `cloudnative-pg`
- `external-secrets`

**You provide:**

- Nothing beyond the unit YAML; Backstage writes it.

**Access** (the workflow has all of this; locally you need it too):

- Terraform ≥ 1.15 and the `aws` CLI: the helm and kubernetes providers fetch an EKS token per call (`aws eks get-token`).
- Credentials for `Terraform-Role` in the unit's account, and the account's state bucket.
- Network reach to the cluster's **private** API endpoint: in the pipeline that is the `phoenix-mgmt` self-hosted runner in the management VPC.

### The unit file

```text
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/cloudnative-pg-cluster.<database-cluster>.yaml
state: <env_id>/<region>/k8s/<cluster>/cloudnative-pg-cluster.<database-cluster>/terraform.tfstate
```

One file per database cluster: `cloudnative-pg-cluster.<database-cluster>.yaml`; the instance name is lowercase letters, digits and hyphens, and keeps two instances apart. The identity block is the same as every unit's (see [`../../README.md`](../../README.md#a-units-yaml)); `spec` is described above. `spec.enabled: false` plans nothing.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd k8s-installs/modules/cloudnative-pg-cluster
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/k8s/<cluster>/cloudnative-pg-cluster.<database-cluster>/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/cloudnative-pg-cluster.<database-cluster>.yaml
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_with_defaults`, `two_instances_do_not_collide`, `missing_instance_rejected`, `disabled_plans_nothing`).

### Outputs

| Output | |
|---|---|
| `cluster` | The Postgres cluster and where its credentials are published. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Nothing else on the cluster depends on it. Backstage destroys in reverse install order.
