# observability

The AWS side of per-cluster self-hosted observability. Each EKS cluster runs
its own Grafana stack (Grafana, Mimir, Loki, Tempo, an OTel/Alloy collector,
NVIDIA DCGM, and Langfuse — deployed from the in-cluster repo). This resource
set gives them somewhere to keep history that **outlives the environment**:
Backstage tears environments down at the weekend; this bucket stays.

One per group account per region, account-level (not per environment):

```text
environments/<tier>/<group>-shared/<region>/observability.yaml
state: <group>-shared/<region>/observability/terraform.tfstate
```

## Creates

| Resource | Name |
|---|---|
| S3 bucket (SSE-KMS, public access blocked) | `<name_prefix>-observability-<account id>` |
| KMS key + alias | `alias/<bucket name>` |
| IAM role per signal — `mimir`, `loki`, `tempo`, `langfuse` | `<name_prefix>-<signal>` |
| IAM role for Grafana's CloudWatch data source | `<name_prefix>-grafana-cloudwatch` |

All roles trust EKS Pod Identity (`pods.eks.amazonaws.com`). core-platform
creates the per-cluster Pod Identity associations from this module's outputs.

## Bucket layout and isolation

```text
<signal prefix><eks cluster name>/...   e.g. mimir/vision-sandbox-jdoe-euw1-1-eks/...
                                              loki-vision-sandbox-jdoe-euw1-1-eks/...
```

| Signal | Prefix (output `signal_prefixes`) |
|---|---|
| mimir | `mimir/` (Mimir's tenant = the cluster name) |
| loki | `loki-` — Loki's `storage_prefix` may not contain a slash and its index sits at the prefix root, so the cluster name is part of the prefix |
| tempo | `tempo/` |
| langfuse | `langfuse/` |

The signal comes first because S3 lifecycle filters only match a leading
prefix — that is what gives each signal its own retention. A writer role may
only list, read, write and delete under `<signal prefix>${aws:PrincipalTag/eks-cluster-name}/*`:
Pod Identity tags every session with the cluster name, so one role per signal
serves every cluster in the account and no cluster can read or overwrite
another's data, or another signal's.

## Configuration

```yaml
environment: shared
tags:
  owner.team: vision
  Reason: observability history for the vision group
  LongLive: true           # required — the plan fails without it
spec:
  retention_days:          # optional; defaults shown
    mimir: 30
    loki: 14
    tempo: 7
    langfuse: 30
```

## Outputs

`bucket_name`, `bucket_arn`, `kms_key_arn`, `writer_role_arns` (map keyed by
signal), `grafana_cloudwatch_role_arn`.

## Order

Apply before core-platform (which reads these outputs); never destroyed by an
environment teardown.

## Tests

```bash
terraform init -backend=false && terraform test
```
