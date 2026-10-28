# model-store

The weights bucket for model serving. Every model's weights are copied here
once, at a pinned version (`k8s-installs` `model-weights.<model>`), and each
cluster's FSx for Lustre cache (`model-cache.<cluster>`) loads them from here.
Pods never download a model from the internet. Backstage tears environments
down at the weekend; this bucket stays, so a copy is never repeated.

One per group account per region, account-level (not per environment), like
`observability`:

```text
environments/<tier>/<group>-shared/<region>/model-store.yaml
state: <group>-shared/<region>/model-store/terraform.tfstate
```

## Creates

| Resource | Name |
|---|---|
| S3 bucket (SSE-KMS, versioned, public access blocked, `prevent_destroy`) | `<name_prefix>-model-weights-<account id>` |
| KMS key + alias | `alias/<bucket name>` |
| IAM role for the copy job (EKS Pod Identity) | `<name_prefix>-model-weights-writer` |

Layout: `<model>/<version>/…`, with `<model>/<version>/_COMPLETE` written last
by the copy job. A version is written once and never changed; a new version is
a new prefix.

The writer role can list, read and write, **never delete**. The KMS key policy
also lets FSx's S3 service-linked role (`AWSServiceRoleForFSxS3Access_<fs id>`,
one per file system) decrypt, which is how `model-cache` lazy-loads. FSx
reaches S3 through that role, not one we attach.

## Configuration

```yaml
environment: shared
tags:
  owner.team: research
  Reason: model weights for the research group
  LongLive: true           # required — the plan fails without it
```

No `spec`.

## Running it

### Before you run it

**Needs:**

- The group's AWS account, its `Terraform-Role` and its state bucket (account vending).
- `tags.LongLive: true` (the plan fails without it): the weights outlive every environment. Usually applied once per group and region in `<group>-shared`.

**Access** (the workflow has all of this; locally you need it too):

- Terraform ≥ 1.15.
- Credentials for `Terraform-Role` in the unit's account (account vending creates it), and the account's state bucket.
- Runs on GitHub-hosted runners: it talks to AWS APIs only.

### The unit file

```text
infrastructure/environments/<tier>/<group>-shared/<region>/model-store.yaml
state: <group>-shared/<region>/model-store/terraform.tfstate
```

The identity block is described in [`../context/README.md`](../context/README.md).

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd infrastructure/modules/model-store
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<group>-shared/<region>/model-store/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/model-store.yaml -var pipeline_user=$USER
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_with_defaults`, `long_live_required`).

### Outputs

| Output | |
|---|---|
| `bucket_name` | Bucket holding <model>/<version>/ for every model in the account and region. |
| `bucket_arn` | The weights bucket's ARN. |
| `kms_key_arn` | KMS key encrypting the bucket. |
| `writer_role_arn` | Pod Identity role for the model-weights copy job: list, read and write, never delete. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Used by: model-cache (FSx data repository association), model-weights (copy job). Destroy those first. The bucket is `prevent_destroy`: removing it is a deliberate edit, because it deletes every copied model.
