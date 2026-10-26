# langfuse

[Langfuse](https://langfuse.com) (chart `2.1.4`, Langfuse 4.50.0, pinned) in
`langfuse`: tracing, prompt management and evaluation for the cluster's LLM
workloads. Part of the **model-serving** set.

- **Databases:** the chart's own Postgres and Valkey, and ClickHouse through
  the `clickhouse-operator` unit (required: the chart refuses to install
  without its CRDs). Sandbox-sized.
- **Blob storage:** the group's long-lived observability bucket, under
  `langfuse/<eks cluster name>/{events,media,exports}/` — the only path the
  observability unit's `langfuse` writer role allows. Credentials come from
  core-platform's Pod Identity binding `langfuse/langfuse` (web and worker run
  as that service account); no access keys. Virtual-hosted S3 addressing.
- **Secrets:** salt, encryption key (64 hex), NextAuth secret and the database
  passwords are generated here and kept in state (rotate by tainting).
- **UI:** `https://langfuse-<cluster>.<internal zone>` through istio's internal
  gateway (output `url`). Applications send traces to output `otel_endpoint`.

Needs, applied first: clickhouse-operator, cert-manager, istio, and the group's
observability unit. `spec`: `chart_version`, `observability_environment`
(`shared`), `enabled`.

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-platform` for the environment and region: the cluster this unit targets (the plan fails without it)
- `observability` in `<group>-shared` (blob storage) (the plan fails without it)
- `core-platform` applied with `spec.observability.enabled: true` (binds `langfuse/langfuse`) (the plan fails without it)
- `dns` (the UI route) (the plan fails without it)

**Cluster components**, applied first on the same cluster (Backstage orders them from the catalog's `dependsOn`):

- `clickhouse-operator`
- `cert-manager`
- `istio`

**You provide:**

- Nothing beyond the unit YAML; Backstage writes it.

**Access** (the workflow has all of this; locally you need it too):

- Terraform ≥ 1.15 and the `aws` CLI: the helm and kubernetes providers fetch an EKS token per call (`aws eks get-token`).
- Credentials for `Terraform-Role` in the unit's account, and the account's state bucket.
- Network reach to the cluster's **private** API endpoint: in the pipeline that is the `phoenix-mgmt` self-hosted runner in the management VPC.

### The unit file

```text
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/langfuse.yaml
state: <env_id>/<region>/k8s/<cluster>/langfuse/terraform.tfstate
```

One file per cluster. The identity block is the same as every unit's (see [`../../README.md`](../../README.md#a-units-yaml)); `spec` is described above. `spec.enabled: false` plans nothing.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd k8s-installs/modules/langfuse
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/k8s/<cluster>/langfuse/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/langfuse.yaml
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_with_defaults`, `langfuse_binding_matches`, `blobs_in_observability_bucket`, `missing_observability_rejected`, `disabled_plans_nothing`).

### Outputs

| Output | |
|---|---|
| `url` | Langfuse UI, on istio's internal gateway. |
| `otel_endpoint` | Where applications send traces (Langfuse's OpenTelemetry endpoint). |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Nothing else on the cluster depends on it. Backstage destroys in reverse install order.
