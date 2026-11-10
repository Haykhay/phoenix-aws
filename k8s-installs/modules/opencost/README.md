# opencost

[OpenCost](https://opencost.io) (chart `2.5.33`, OpenCost `1.121.3`, pinned)
in `opencost`. Part of every cluster's baseline.

It prices each node from AWS list prices and emits cost metrics: per node
(`node_total_hourly_cost`, `node_cpu_hourly_cost`, `node_ram_hourly_cost`,
`node_gpu_hourly_cost`) and per container (`container_cpu_allocation`,
`container_memory_allocation_bytes`, `container_gpu_allocation`). It reads the
cluster's own Mimir (`grafana-stack`) instead of running a Prometheus of its
own, and grafana-stack's Alloy scrapes its metrics (annotation, port `9003`)
back into Mimir. grafana-stack's **Cost** dashboard shows cost per namespace,
per model and per GPU type from them.

Costs are labelled with the cluster's name (`exporter.defaultClusterId`).

`spec`: `chart_version`, `enabled`.

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-platform` for the environment and region: the cluster this unit targets (the plan fails without it)

**Cluster components**, applied first on the same cluster (Backstage orders them from the catalog's `dependsOn`):

- `grafana-stack`: the Mimir it reads and the Alloy that scrapes it.

**You provide:**

- Nothing beyond the unit YAML; Backstage writes it.

**Access** (the workflow has all of this; locally you need it too):

- Terraform ≥ 1.15 and the `aws` CLI: the helm and kubernetes providers fetch an EKS token per call (`aws eks get-token`).
- Credentials for `Terraform-Role` in the unit's account, and the account's state bucket.
- Network reach to the cluster's **private** API endpoint: in the pipeline that is the `phoenix-mgmt` self-hosted runner in the management VPC.

### The unit file

```text
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/opencost.yaml
state: <env_id>/<region>/k8s/<cluster>/opencost/terraform.tfstate
```

One file per cluster. The identity block is the same as every unit's (see [`../../README.md`](../../README.md#a-units-yaml)); `spec` is described above.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd k8s-installs/modules/opencost
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/k8s/<cluster>/opencost/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/opencost.yaml
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_opencost`, `disabled_plans_nothing`).

### Outputs

| Output | |
|---|---|
| `namespace` | Namespace it runs in. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Nothing else on the cluster depends on it. Backstage destroys in reverse install order.
