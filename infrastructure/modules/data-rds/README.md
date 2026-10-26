# data-rds

Bundled resource-set module for relational databases. It creates a **named set of
RDS instances** for one environment/region, each with its own KMS key, security
group, credentials secret and optional read replica.

## Where this runs

```text
environments/<tier>/<env_id>/<region>/data-rds.yaml
state: <env_id>/<region>/data-rds/terraform.tfstate
```

## Configuration

Values only, under `spec` in the unit's YAML:

```yaml
db_prefix: rds
instances:
  core:
    engine: postgres
    engine_version: "16.14"
    instance_class: db.t4g.small
    allocated_storage: 100
    vpc: vpc-1
    eks_clusters: ["1"]
```

| Key | Default | Notes |
|---|---|---|
| `engine`, `engine_version` | — | Required per instance |
| `instance_class`, `allocated_storage` | — | Required per instance |
| `vpc` | resource set's, else network default | Which VPC this instance sits in |
| `eks_clusters` | see below | EKS clusters whose nodes may reach it |
| `base_name_postfix` | the map key | Trailing component of the instance name |
| `username`, `db_name` | map key, `-` → `_` | |
| `port` | 5432 postgres / 3306 mysql | |
| `replica_enabled` | `false` | Creates a read replica |
| `parameters` | `[]` | Parameter-group entries |
| `enabled_cloudwatch_logs_exports` | per engine | |
| `cloudwatch_log_group_retention_days` | resource set's, else 7 | |
| `allowed_cidr_blocks` | `[]` | Extra ingress |
| `allowed_security_group_ids` | `[]` | Extra ingress |
| `allow_eks_node_security_group` | `true` | `false` skips the cluster binding entirely |
| `tags` | `{}` | Ownership tags |

Resource-set level values apply to every instance; an entry in `instances`
overrides them.

## Which clusters can reach it

`eks_clusters` lists the EKS clusters whose node security group gets ingress. It
is a list because one database can legitimately serve several clusters.

This is a security boundary, not a placement choice, and getting it wrong fails
**silently** — the database simply becomes unreachable from the cluster that
needed it, with nothing in the plan to notice. So the plan
refuses an unbound item once more than one EKS cluster exists; with exactly one it is
unambiguous and may be omitted.

Set `allow_eks_node_security_group: false` for a database no cluster should
reach; it then needs no binding.

## Naming

```text
<name_prefix>-<db_prefix>-<base_name_postfix>
```

`<name_prefix>` (`<env_id>-<region code>`) comes from `modules/context` — see
the repo README. The `name_prefix` override exists
only to hold an existing name through a migration; changing the resulting
identifier **replaces the instance**, since `identifier` is ForceNew on
`aws_db_instance`.

## Credentials

Master passwords come from the shared [`credentials`](../credentials/README.md)
module, which Layer 3's in-cluster Postgres uses too, one password policy for
both bindings.

Instances use the `rds_master` policy: 30 alphanumeric characters with at least
one upper, one lower and one digit.

To rotate one without changing policy, set `password_keepers` on the instance
and the plan shows the password being replaced; nothing rotates on its own.

```json
"instances": { "core": { "password_keepers": { "rotated": "2026-08-18" } } }
```

Rotating changes the RDS master password, so anything holding the old one fails
until it re-reads the secret.

## Secrets

Each instance gets a Secrets Manager secret at:

```text
/db/<db_prefix>/<name_prefix>/<base_name_postfix>-<engine>-db-config
```

Consumers read that path rather than being handed credentials — see
k8s-installs' Keycloak module for an example of the `incluster` vs `rds`
binding.

## Running it

### Before you run it

**Needs:**

- The group's AWS account, its `Terraform-Role` and its state bucket (account vending).
- `core-network` (subnets; the plan fails without it).
- `core-platform`, so the clusters' node security group may connect (`eks_clusters` names which, when there are several).

**Access** (the workflow has all of this; locally you need it too):

- Terraform ≥ 1.15.
- Credentials for `Terraform-Role` in the unit's account (account vending creates it), and the account's state bucket.
- Runs on GitHub-hosted runners: it talks to AWS APIs only.

### The unit file

```text
infrastructure/environments/<tier>/<env_id>/<region>/data-rds.yaml
state: <env_id>/<region>/data-rds/terraform.tfstate
```

The identity block is described in [`../context/README.md`](../context/README.md); `spec` is described above.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd infrastructure/modules/data-rds
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/data-rds/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/data-rds.yaml -var pipeline_user=$USER
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_in_selected_vpc`, `eks_binding_required`, `eks_binding_named`, `minimal_instance_plans`).

### Outputs

| Output | |
|---|---|
| `instance_names` | Keys of the RDS instances. |
| `rds` | RDS connection info |
| `secret_arns` | Connection secret ARN, by instance. |
| `kms_key_arns` | KMS key ARN, by instance. |
| `security_group_ids` | Security group ID, by instance. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Used by: applications, through the secrets published under `<organisation>/<env_id>/postgres/`. Destroy those first.
