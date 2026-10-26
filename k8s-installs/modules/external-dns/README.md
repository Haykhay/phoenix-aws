# external-dns

[external-dns](https://kubernetes-sigs.github.io/external-dns/) for Route53,
with Pod Identity (`external-dns/external-dns` → `<name_prefix>-external-dns`).
Part of the **service** set.

- Sources: `service`, `ingress`, `gateway-httproute` — only resources annotated
  `external-dns.alpha.kubernetes.io/hostname` get a record.
- Zones: the cluster's own public + internal zone by default; naming zone keys
  (`spec.settings.providers.route53.zones: [zone-1, zone-2]`) widens both what
  it reconciles (`--zone-id-filter`; the chart has no `zoneIdFilters` value)
  and what its IAM policy may change.
- Records are owned per cluster (`txtOwnerId` = the cluster's name prefix) and
  never deleted by default (`policy: upsert-only`).

Chart `1.21.1`, pinned. The plan fails clearly without the environment's dns unit.

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-platform` for the environment and region: the cluster this unit targets (the plan fails without it)
- `dns`: the zones it manages (the plan fails without it)

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
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/external-dns.yaml
state: <env_id>/<region>/k8s/<cluster>/external-dns/terraform.tfstate
```

One file per cluster. The identity block is the same as every unit's (see [`../../README.md`](../../README.md#a-units-yaml)); `spec` is described above. `spec.enabled: false` plans nothing.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd k8s-installs/modules/external-dns
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/k8s/<cluster>/external-dns/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/external-dns.yaml
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_with_defaults`, `zone_scoped_iam`, `extra_zone_on_request`, `personal_env_names_fit`, `no_dns_rejected`, `disabled_plans_nothing`).

### Outputs

| Output | |
|---|---|
| `role_arn` | IAM role its service account uses, through Pod Identity. |
| `zone_ids` | Hosted zones it reconciles (and may write to). |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Destroy these first, on the same cluster: `vllm`. Backstage destroys in reverse install order.
