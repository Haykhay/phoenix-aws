# clickhouse-operator

[ClickHouse's operator](https://github.com/ClickHouse/clickhouse-operator) (chart `0.0.8`, pinned) in `clickhouse-operator`: the `ClickHouseCluster`/`KeeperCluster` CRDs the Langfuse chart deploys its ClickHouse with. Langfuse refuses to install without them. Needs cert-manager. Upgrade it on its own, following the Langfuse chart's prerequisites.

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-platform` for the environment and region: the cluster this unit targets (the plan fails without it)

**Cluster components**, applied first on the same cluster (Backstage orders them from the catalog's `dependsOn`):

- `cert-manager`

**You provide:**

- Nothing beyond the unit YAML; Backstage writes it.

**Access** (the workflow has all of this; locally you need it too):

- Terraform ≥ 1.15 and the `aws` CLI: the helm and kubernetes providers fetch an EKS token per call (`aws eks get-token`).
- Credentials for `Terraform-Role` in the unit's account, and the account's state bucket.
- Network reach to the cluster's **private** API endpoint: in the pipeline that is the `phoenix-mgmt` self-hosted runner in the management VPC.

### The unit file

```text
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/clickhouse-operator.yaml
state: <env_id>/<region>/k8s/<cluster>/clickhouse-operator/terraform.tfstate
```

One file per cluster. The identity block is the same as every unit's (see [`../../README.md`](../../README.md#a-units-yaml)); `spec` is described above. `spec.enabled: false` plans nothing.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd k8s-installs/modules/clickhouse-operator
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/k8s/<cluster>/clickhouse-operator/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/clickhouse-operator.yaml
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_with_defaults`, `disabled_plans_nothing`).

### Outputs

None besides `resource_summary` (what was planned, for the pipeline's summary).

### Removing it

Destroy these first, on the same cluster: `langfuse`. Backstage destroys in reverse install order.
