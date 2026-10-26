# data-msk

Provisions a **named set of MSK clusters** with IAM-only authentication, using the
[terraform-aws-modules/terraform-aws-msk-kafka-cluster](https://github.com/terraform-aws-modules/terraform-aws-msk-kafka-cluster)
community module, from the public Terraform registry.
The security group is managed here (not by the module) so we control exactly which ports are opened.

**Metadata mode**: KRaft. The AWS MSK API selects metadata mode via the `kafka_version` string:
use `3.8.x.kraft` for KRaft or `3.8.x` for ZooKeeper. The `.kraft` suffix is the only way to
enable KRaft via Terraform (the provider has no `metadata_mode` argument).

## Configuration

Values only, under `spec` in the unit's YAML:

```yaml
cluster_defaults:
  kafka_version: 3.8.x.kraft
clusters:
  core:
    broker_instance_type: kafka.m7g.large
    broker_per_zone: 1
    vpc: vpc-1
    eks_clusters: ["1"]
    users: [ ... ]
```

| Key | Default | Notes |
|---|---|---|
| `kafka_version` | `3.8.x.kraft` | The `.kraft` suffix selects KRaft — see below |
| `broker_instance_type` | `kafka.m7g.large` | |
| `broker_per_zone` | `1` | Brokers = this × number of subnets |
| `vpc` | resource set's, else network default | Which VPC the brokers sit in |
| `eks_clusters` | see below | EKS clusters whose nodes may reach the brokers |
| `users` | `[]` | IAM roles + ACLs, see below |
| `scram_users` | `[]` | SASL/SCRAM usernames, see below. Distinct from `users` |
| `allowed_cidr_blocks` | `[]` | Extra ingress on 9094/9098 |
| `allow_eks_node_security_group` | `true` | `false` skips the cluster binding entirely |
| `name_prefix` | `<prefix>-<key>` | Override only to hold an existing name |
| `tags` | `{}` | Ownership tags |

`cluster_defaults` applies to every cluster; an entry in `clusters` overrides it.

### Which clusters can reach it

`eks_clusters` lists the EKS clusters whose node security group gets ingress on
9094/9098. It is a list because one Kafka cluster can serve several. Getting it
wrong fails **silently** — the brokers simply become unreachable — so the
plan refuses an unbound cluster once more than one EKS cluster exists;
with exactly one it is unambiguous and may be omitted.

## Authentication

**IAM is the default and the one to reach for.** Workloads authenticate with
their own AWS IAM role via the `bootstrap_brokers_sasl_iam` endpoint (port
9098) — no usernames, no passwords, nothing to rotate or leak. Every cluster
gets it whether or not SCRAM is also on.

SASL/SCRAM is available for workloads that cannot use IAM — a third-party
client, or something outside AWS. Declaring `scram_users` turns it on for that
cluster and leaves it off everywhere else.

```json
"clusters": { "core": { "scram_users": ["partner-feed"] } }
```

Each username gets a password from the shared `credentials` module and a
Secrets Manager secret named
`AmazonMSK_<organisation>_<env>_kafka_managed_<cluster>_<username>`, associated with
the cluster. Read the name from the `scram_secrets` output rather than
reconstructing it.

AWS constrains these secrets in ways the module handles for you:

- the name **must** begin with `AmazonMSK_`, so the secret path convention `<organisation>/...` path
  cannot apply — the same components are flattened into a legal name instead
- the secret **must** use a customer-managed KMS key; an association whose
  secret uses the default `aws/secretsmanager` key is rejected. The cluster's
  own key is used
- the secret must hold exactly `username` and `password` and nothing else
- SCRAM-SHA-512 only, up to 1000 users, and the secret must live in the same
  account and region as the cluster

> **Unverified against a running cluster.** `data-msk` is `enabled: false` in
> every environment, so this path has never been applied. An earlier revision of
> this README stated that SASL/SCRAM is not supported with KRaft; AWS documents
> no such limitation, but nor is it documented as supported. Confirm against a
> real KRaft cluster before depending on it.

### Kafka client config

Add the [AWS MSK IAM Auth](https://github.com/aws/aws-msk-iam-auth) library to the service and configure:

```properties
bootstrap.servers=<bootstrap_brokers_sasl_iam from Secrets Manager>
security.protocol=SASL_SSL
sasl.mechanism=AWS_MSK_IAM
sasl.jaas.config=software.amazon.msk.auth.iam.IAMLoginModule required;
sasl.client.callback.handler.class=software.amazon.msk.auth.iam.IAMClientCallbackHandler
```

### MSK resource policy (managed by Terraform)

Declare a `users` list per cluster. Each user is an IAM role ARN plus a list of ACL rules. The module generates one `aws_msk_cluster_policy` per cluster — the resource ARNs carry that cluster's name, so the statements cannot be shared between clusters.

```json
"clusters": { "core": { "users": [
  {
    "role_arn": "arn:aws:iam::<account_id>:role/core-app-role",
    "acls": [
      { "resource_type": "topic", "name": "core-events", "operations": ["Read", "Write", "Describe"] },
      { "resource_type": "group", "name": "core-app",    "operations": ["Read"] }
    ]
  },
  {
    "role_arn": "arn:aws:iam::<account_id>:role/analytics-reader-role",
    "acls": [
      { "resource_type": "topic", "name": "core-events", "operations": ["Read", "Describe"] },
      { "resource_type": "group", "name": "analytics",   "operations": ["Read"] }
    ]
    }
  ] } }
```

Each user automatically receives `kafka-cluster:Connect` + `kafka-cluster:DescribeCluster` on the cluster, plus the per-topic/group permissions derived from the `operations` list.

#### ACL fields

| Field | Required | Description |
|---|---|---|
| `resource_type` | yes | `topic` or `group` |
| `name` | yes | Kafka resource name. Use `*` to match all resources of this type |
| `operations` | yes | List of operations — see table below |

#### Operations → IAM actions

| Operation | resource_type | IAM actions granted |
|---|---|---|
| `Read`           | topic | `kafka-cluster:ReadData`, `kafka-cluster:DescribeTopic` |
| `Write`          | topic | `kafka-cluster:WriteData`, `kafka-cluster:DescribeTopic` |
| `Create`         | topic | `kafka-cluster:CreateTopic` |
| `Delete`         | topic | `kafka-cluster:DeleteTopic` |
| `Describe`       | topic | `kafka-cluster:DescribeTopic` |
| `AlterConfigs`   | topic | `kafka-cluster:AlterTopic` |
| `DescribeConfigs` | topic | `kafka-cluster:DescribeTopicDynamicConfiguration` |
| `Read`           | group | `kafka-cluster:ReadGroup`, `kafka-cluster:DescribeGroup` |
| `Delete`         | group | `kafka-cluster:DeleteGroup` |
| `Describe`       | group | `kafka-cluster:DescribeGroup` |

**Note:** Topics are not created by Terraform (the Kafka admin API requires VPC connectivity from CI, which is not available). Grant `Create` to the workload role if the service manages its own topics, or create topics out-of-band via a Kafka admin client.

## Connection info

The module writes a Secrets Manager secret (`<name-prefix>-msk`) containing:

```json
{ "bootstrap_brokers_sasl_iam": "b-1.<cluster>:9098,b-2.<cluster>:9098,..." }
```

Read this secret at startup to get the broker string.

## Migration from the old SASL/SCRAM setup

This module used to set `client_sasl_scram_enabled = true` and create one
per-account secret (`AmazonMSK_<prefix>-<account>`) holding
`{ username, password }`. That arrangement is gone, and moving to IAM remains
the right default — the `scram_users` support described above is a per-username
escape hatch for clients that cannot use IAM, not a route back to it.

Services that were using the old SCRAM credentials need to:

1. Switch their Kafka client config (see above).
2. Ensure their EKS pod has an IAM role (via Pod Identity or IRSA) with the MSK resource policy applied.
3. Remove any code that reads the old `AmazonMSK_*` secrets.

## Running it

### Before you run it

**Needs:**

- The group's AWS account, its `Terraform-Role` and its state bucket (account vending).
- `core-network` (the plan fails without it).
- `core-platform`, so the clusters' node security group may connect.

**Access** (the workflow has all of this; locally you need it too):

- Terraform ≥ 1.15.
- Credentials for `Terraform-Role` in the unit's account (account vending creates it), and the account's state bucket.
- Runs on GitHub-hosted runners: it talks to AWS APIs only.

### The unit file

```text
infrastructure/environments/<tier>/<env_id>/<region>/data-msk.yaml
state: <env_id>/<region>/data-msk/terraform.tfstate
```

The identity block is described in [`../context/README.md`](../context/README.md); `spec` is described above.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd infrastructure/modules/data-msk
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/data-msk/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/data-msk.yaml -var pipeline_user=$USER
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_in_selected_vpc`, `eks_binding_required`, `secret_path_uses_organisation`).

### Outputs

| Output | |
|---|---|
| `clusters` | Every MSK cluster in this resource set, keyed by its config name. |
| `default_cluster_name` | Config key of the cluster the flat outputs resolve to. |
| `cluster_names` | Keys of the MSK clusters. |
| `bootstrap_brokers_sasl_iam` | Default cluster: IAM-auth bootstrap brokers. |
| `secret_arn` | ARN of the connection-info secret (bootstrap brokers) |
| `kms_key_arn` | Default cluster: KMS key ARN. |
| `security_group_id` | Default cluster: security group ID. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Used by: applications, through the SCRAM secrets it publishes. Destroy those first.
