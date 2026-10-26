# external-secrets

The [External Secrets Operator](https://external-secrets.io) plus two
`ClusterSecretStore`s (`aws-secretsmanager`, `aws-ssm`), with AWS access
through **EKS Pod Identity** (`external-secrets/external-secrets` → role
`<name_prefix>-external-secrets`). Part of every cluster's baseline.

## What it can read

Only values under **`<organisation>/<env_id>/`** in the unit's own account and
region:

| Store | Allowed |
|---|---|
| Secrets Manager | `arn:aws:secretsmanager:<region>:<account>:secret:<organisation>/<env_id>/*` |
| SSM Parameter Store | `arn:aws:ssm:<region>:<account>:parameter/<organisation>/<env_id>/*` |
| KMS decrypt | the cluster's KMS key, plus `settings.kms_key_arns` |

That prefix is where infrastructure's `credentials` module publishes
(`<organisation>/<environment>/<service>/<binding>`), and where other
components put what they need (e.g. `acme/research-sandbox-jdoe/models/hf-token`).
There is no `ListSecrets` / `DescribeParameters`: the operator reads values by
name and cannot enumerate other environments' secrets.

## Spec

| `spec.settings` | Default | |
|---|---|---|
| `secrets_manager_arns` / `ssm_parameter_arns` | the prefix above | override only with a reason |
| `kms_key_arns` | `[]` | extra keys besides the cluster's |
| `ecr_pull_repos` | `[]` | repositories in this account the operator may pull |

Chart `2.6.0` (`spec.chart_version`), pinned by the platform. `spec.enabled:
false` creates nothing.

A 20-second wait after the Pod Identity association closes a real gap: EKS
injects credentials only at pod admission, and a pod created before the
association is live stays unauthorized for good.

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-platform` for the environment and region: the cluster this unit targets (the plan fails without it)

**Cluster components**, applied first on the same cluster (Backstage orders them from the catalog's `dependsOn`):

- None.

**You provide:**

- Secrets other components read, under `<organisation>/<env_id>/` in Secrets Manager or SSM, in the cluster's account and region. Most are written by Terraform (infrastructure's `credentials` module, argo-cd, kargo); a few by hand (vllm's Hugging Face token).

**Access** (the workflow has all of this; locally you need it too):

- Terraform ≥ 1.15 and the `aws` CLI: the helm and kubernetes providers fetch an EKS token per call (`aws eks get-token`).
- Credentials for `Terraform-Role` in the unit's account, and the account's state bucket.
- Network reach to the cluster's **private** API endpoint: in the pipeline that is the `phoenix-mgmt` self-hosted runner in the management VPC.

### The unit file

```text
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/external-secrets.yaml
state: <env_id>/<region>/k8s/<cluster>/external-secrets/terraform.tfstate
```

One file per cluster. The identity block is the same as every unit's (see [`../../README.md`](../../README.md#a-units-yaml)); `spec` is described above. `spec.enabled: false` plans nothing.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd k8s-installs/modules/external-secrets
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/k8s/<cluster>/external-secrets/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/external-secrets.yaml
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_with_defaults`, `pod_identity_scoped`, `personal_env_names_fit`, `disabled_plans_nothing`).

### Outputs

| Output | |
|---|---|
| `release_name` | Helm release name. |
| `namespace` | Namespace it runs in. |
| `role_arn` | Pod Identity role of the operator. |
| `secret_path` | Prefix every secret/parameter this cluster can read lives under: <organisation>/<env_id>. |
| `cluster_secret_stores` | ClusterSecretStores to reference from an ExternalSecret. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Destroy these first, on the same cluster: `argo-cd`, `cloudnative-pg-cluster`, `strimzi-kafka-cluster`, `valkey-redis-cluster`, `vllm`. Backstage destroys in reverse install order.
