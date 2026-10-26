# strimzi-kafka-cluster

One Kafka cluster ([Strimzi](https://strimzi.io), KRaft) per unit:
`strimzi-kafka-cluster.<instance>.yaml` → `Kafka` `kafka-<instance>` in
`strimzi-operator`. Needs the `strimzi-kafka` operator unit and
`external-secrets`. Used for a **kafka** request in sandbox; stage and above use
infrastructure's managed `data-msk`.

`spec.tier` picks a preset (any field can be overridden):

| | `nonprod` (default) | `prod` |
|---|---|---|
| Nodes | one dual-role pool, 1 replica, 10Gi | 3 controllers + 3 brokers |
| Listeners | internal SCRAM `9093` | internal `9092` + external NLB `9096` |
| Replication | 1 | 3, min ISR 2 |
| Extras | — | CA lifecycle, Kafka exporter, PDB, zone spreading |

`topics: [{ name, partitions, replicas, config? }]` and `users: [{ name, acls? }]`.
Kubernetes objects are prefixed with the cluster name (`kafka-<instance>-<user>`,
`kafka-<instance>-<topic>`) so two clusters in one namespace never collide; a
topic keeps its real name, and the SCRAM username is the prefixed name.

User passwords (policy `generic`) publish at
`<organisation>/<env_id>/kafka/in-cluster/<instance>/<user>` with the bootstrap
address. Topics carry `helm.sh/resource-policy: keep`: removing one from the
spec does not delete its data.

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-platform` for the environment and region: the cluster this unit targets (the plan fails without it)

**Cluster components**, applied first on the same cluster (Backstage orders them from the catalog's `dependsOn`):

- `strimzi-kafka`
- `external-secrets`

**You provide:**

- Nothing beyond the unit YAML; Backstage writes it.

**Access** (the workflow has all of this; locally you need it too):

- Terraform ≥ 1.15 and the `aws` CLI: the helm and kubernetes providers fetch an EKS token per call (`aws eks get-token`).
- Credentials for `Terraform-Role` in the unit's account, and the account's state bucket.
- Network reach to the cluster's **private** API endpoint: in the pipeline that is the `phoenix-mgmt` self-hosted runner in the management VPC.

### The unit file

```text
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/strimzi-kafka-cluster.<kafka-cluster>.yaml
state: <env_id>/<region>/k8s/<cluster>/strimzi-kafka-cluster.<kafka-cluster>/terraform.tfstate
```

One file per Kafka cluster: `strimzi-kafka-cluster.<kafka-cluster>.yaml`; the instance name is lowercase letters, digits and hyphens, and keeps two instances apart. The identity block is the same as every unit's (see [`../../README.md`](../../README.md#a-units-yaml)); `spec` is described above. `spec.enabled: false` plans nothing.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd k8s-installs/modules/strimzi-kafka-cluster
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/k8s/<cluster>/strimzi-kafka-cluster.<kafka-cluster>/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/strimzi-kafka-cluster.<kafka-cluster>.yaml
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_with_defaults`, `two_instances_do_not_collide`, `missing_instance_rejected`, `disabled_plans_nothing`).

### Outputs

| Output | |
|---|---|
| `cluster` | The Kafka cluster and where its users' credentials are published. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Nothing else on the cluster depends on it. Backstage destroys in reverse install order.
