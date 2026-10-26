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
