# model-cache

FSx for Lustre in front of the group's weights bucket (`model-store`), one per
cluster that serves models. The first read of a file loads it from S3; every
later read, restart, rollout and scale-up is served from Lustre, which is what
keeps a large model's start in minutes. vLLM pods mount it read-only through
`k8s-installs` `aws-fsx-csi-driver`.

```text
environments/<tier>/<env_id>/<region>/model-cache.<cluster>.yaml
state: <env_id>/<region>/model-cache.<cluster>/terraform.tfstate
```

The instance is the cluster's key in core-platform (`model-cache.1.yaml` for
cluster `"1"`).

## Creates

| Resource | |
|---|---|
| FSx for Lustre (`PERSISTENT_2`, Lustre 2.15, LZ4) | in the cluster's first node subnet |
| Data repository association | `s3://<weights bucket>/` at `/weights`, importing new, changed and deleted objects |
| Security group | Lustre ports 988 and 1018–1023 from the cluster's node security group and from itself |

Weights appear at `/weights/<model>/<version>/` inside the file system.

## Configuration

```yaml
tags:
  LongLive: false            # see Lifecycle; Backstage writes it from the tier's setting
spec:
  storage_capacity_gib: 1200 # PERSISTENT_2 minimum; then 2400 GiB steps
  throughput_per_tib: 250    # 125, 250, 500 or 1000 MB/s per TiB
```

| Key | Default | Notes |
|---|---|---|
| `deployment_type` | `PERSISTENT_2` | needed for the S3 association |
| `storage_capacity_gib` | `1200` | size it to the models served on the cluster: the cache evicts nothing on its own |
| `throughput_per_tib` | `250` | load time scales with it |

## Lifecycle

`tags.LongLive` decides what a weekend teardown does to the cache:

- `true`: the file system stays, so Monday starts warm, and you pay FSx hours
  through the weekend.
- `false`: it is torn down with the environment; the next start is cold and
  re-reads from S3.

The DevOps engineer sets it per tier when setting up Backstage (default:
long-lived in uat and prod, torn down in sandbox and stage) and can change it
any time. Changing it changes only this unit: the bucket and the weights are
untouched.

A long-lived cache needs a long-lived network: FSx inside a VPC that a
teardown deletes would block the deletion, so the plan fails unless
core-network is `LongLive` too.

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-network`, with the S3 gateway endpoint (`enable_vpc_endpoints: true`, `s3` in `endpoint_services`): the plan fails without it.
- `core-platform`, with the cluster named in the file: the plan fails without it.
- `model-store` in `<group>-shared/<region>`: the plan fails without it.

**Access** (the workflow has all of this; locally you need it too):

- Terraform ≥ 1.15.
- Credentials for `Terraform-Role` in the unit's account (account vending creates it), and the account's state bucket.
- Runs on GitHub-hosted runners: it talks to AWS APIs only.

### The unit file

```text
infrastructure/environments/<tier>/<env_id>/<region>/model-cache.<cluster>.yaml
state: <env_id>/<region>/model-cache.<cluster>/terraform.tfstate
```

The identity block is described in [`../context/README.md`](../context/README.md); `spec` is described above.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd infrastructure/modules/model-cache
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/model-cache.<cluster>/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/model-cache.<cluster>.yaml -var pipeline_user=$USER
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_with_defaults`, `s3_gateway_endpoint_required`, `long_lived_cache_needs_long_lived_network`, `long_lived_cache_in_long_lived_network`, `missing_model_store_rejected`, `unknown_cluster_rejected`).

### Outputs

| Output | |
|---|---|
| `file_system_id` | FSx for Lustre file system ID (the CSI volume handle). |
| `dns_name` | File system DNS name (CSI volumeAttributes.dnsname). |
| `mount_name` | Lustre mount name (CSI volumeAttributes.mountname). |
| `weights_path_prefix` | Where the weights bucket appears inside the file system: <prefix>/<model>/<version>/. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Used by: aws-fsx-csi-driver (the static volume), vllm (through it). Destroy those first. Removing the cache never touches the weights in S3.
