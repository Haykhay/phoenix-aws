# valkey-redis-cluster

One Valkey (Redis-compatible) cluster per unit:
`valkey-redis-cluster.<instance>.yaml` → `ValkeyCluster` `valkey-<instance>` in
`valkey-operator`. Needs the `valkey-redis` operator unit and
`external-secrets`. Used for a **redis** request in sandbox; stage and above use
infrastructure's managed `data-elasticache`.

| `spec` | Default | |
|---|---|---|
| `shards` | `1` | |
| `replicas` | `0` | per shard |
| `storage_size` | `5Gi` | |
| `users` | `[]` | `[{ name, permissions? }]` (ACL, default `+@all ~* &*`) |

Passwords (policy `redis_incluster`) publish at
`<organisation>/<env_id>/redis/in-cluster/<instance>` (default user) and
`.../<instance>/<user>`. The service address in the payload
(`valkey-<instance>.<namespace>.svc`) assumes the operator names its Service
after the cluster — not yet confirmed against a running operator.

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-platform` for the environment and region: the cluster this unit targets (the plan fails without it)

**Cluster components**, applied first on the same cluster (Backstage orders them from the catalog's `dependsOn`):

- `valkey-redis`
- `external-secrets`

**You provide:**

- Nothing beyond the unit YAML; Backstage writes it.

**Access** (the workflow has all of this; locally you need it too):

- Terraform ≥ 1.15 and the `aws` CLI: the helm and kubernetes providers fetch an EKS token per call (`aws eks get-token`).
- Credentials for `Terraform-Role` in the unit's account, and the account's state bucket.
- Network reach to the cluster's **private** API endpoint: in the pipeline that is the `phoenix-mgmt` self-hosted runner in the management VPC.

### The unit file

```text
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/valkey-redis-cluster.<valkey-cluster>.yaml
state: <env_id>/<region>/k8s/<cluster>/valkey-redis-cluster.<valkey-cluster>/terraform.tfstate
```

One file per Valkey cluster: `valkey-redis-cluster.<valkey-cluster>.yaml`; the instance name is lowercase letters, digits and hyphens, and keeps two instances apart. The identity block is the same as every unit's (see [`../../README.md`](../../README.md#a-units-yaml)); `spec` is described above. `spec.enabled: false` plans nothing.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd k8s-installs/modules/valkey-redis-cluster
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/k8s/<cluster>/valkey-redis-cluster.<valkey-cluster>/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/valkey-redis-cluster.<valkey-cluster>.yaml
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_with_defaults`, `two_instances_do_not_collide`, `missing_instance_rejected`, `disabled_plans_nothing`).

### Outputs

| Output | |
|---|---|
| `cluster` | The Valkey cluster and where its credentials are published. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Nothing else on the cluster depends on it. Backstage destroys in reverse install order.
