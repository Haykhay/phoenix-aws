# model-weights

Copies one pinned version of one model into the group's weights bucket
(infrastructure's `model-store`), once. The cluster's FSx cache then serves
it to vLLM at `/models/<model>/<version>/`. Serving pods never reach the
internet; this job is the only thing that does.

A Job on CPU nodes fetches the source into a scratch EBS volume, syncs it to
`s3://<bucket>/<model>/<version>/` and writes `_COMPLETE` last (source type,
uri and version inside). If `_COMPLETE` is already there the Job exits at
once, so re-applying, or a second cluster asking for the same version, copies
nothing. The apply waits for the Job (up to 6 hours). The outputs vllm reads
(`version`, `cache_path`, `s3_prefix`, `size_gib`) are published only once the
release is deployed: a failed or disabled copy leaves them null, so vllm's
plan fails instead of starting pods on a missing path.

| Source `type` | `uri` | `version` | How |
|---|---|---|---|
| `huggingface` | `<org>/<repo>` | the 40-character commit SHA (a branch moves, so it is refused) | `hf download --revision` |
| `s3` | `s3://<bucket>/<prefix>/` | a label you choose | `aws s3 sync`, as the copy role: list the bucket in model-store's `source_buckets` **and** have its bucket policy grant model-store's writer role `s3:ListBucket` and `s3:GetObject` (and its KMS key policy, if encrypted with a customer key) |
| `https` | `https://…` (plain http is refused) | a label you choose | download, check `sha256`, unpack if it is a tar |

```yaml
spec:
  model: llama-3-1-70b          # optional; defaults to the instance (model-weights.<model>.yaml)
  source:
    type: huggingface
    uri: meta-llama/Llama-3.1-70B-Instruct
    credentials: false          # true for a gated or private source
  version: 0123456789abcdef0123456789abcdef01234567
  sha256: null                  # required for https
  size_gib: 200                 # scratch volume; at least the model's size
```

| Key | Default | Notes |
|---|---|---|
| `model` | the instance | name in paths and the served model name |
| `source.type` | `huggingface` | `huggingface`, `s3` or `https` |
| `source.uri` | **required** | must match the type |
| `source.credentials` | `false` | huggingface: token from `<organisation>/<env_id>/models/hf-token` (vllm's); https: `<organisation>/<env_id>/models/<instance>-source`, sent as `Authorization: Bearer`. Property `token`. s3 never uses one |
| `version` | **required** | letters, digits, `.`, `_`, `-`; at most 64 |
| `sha256` | `null` | 64 hex characters; required for https |
| `size_gib` | `200` | |

One unit per model, named like the vllm unit that serves it
(`model-weights.<slug>.yaml` beside `vllm.<slug>.yaml`): vllm reads this
unit's state. A new version is the same file with a new `spec.version`: a new
prefix and a new release (`weights-<model>-<SHA's first 7, or the label>`);
the old version stays in S3 and in the cache until you remove it. Versions
are never overwritten: the writer role cannot delete. Apply this unit first,
then vllm with the same `spec.version`.

| Image | Pinned |
|---|---|
| upload, check, s3 fetch | `amazon/aws-cli:2.38.0` (2026-10-13) |
| https fetch | `curlimages/curl:8.22.0` (2026-09-02) |
| huggingface fetch | `python:3.13.16-slim-bookworm` (2026-09-30) + `huggingface_hub==2.1.1` (2026-10-01), installed when the Job starts |

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-platform` for the environment and region: the cluster this unit targets (the plan fails without it)
- `model-store` in `<group>-shared/<region>` (the plan fails without it)

**Cluster components**, applied first on the same cluster:

- `external-secrets`, when `source.credentials` is true

**You provide:**

- `spec.source` and `spec.version` (Backstage fills both from the request; the plan fails on a malformed address, a Hugging Face branch name or an https source without `sha256`).
- With credentials: the token in Secrets Manager at the path above, property `token`.
- For an s3 source: the source bucket's policy granting model-store's writer role.

**Access** (the workflow has all of this; locally you need it too):

- Terraform ≥ 1.15 and the `aws` CLI: the helm and kubernetes providers fetch an EKS token per call (`aws eks get-token`).
- Credentials for `Terraform-Role` in the unit's account, and the account's state bucket.
- Network reach to the cluster's **private** API endpoint: in the pipeline that is the `phoenix-mgmt` self-hosted runner in the management VPC.

### The unit file

```text
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/model-weights.<model>.yaml
state: <env_id>/<region>/k8s/<cluster>/model-weights.<model>/terraform.tfstate
```

One file per model, with the same instance name as its vllm unit; the instance name is lowercase letters, digits and hyphens. The identity block is the same as every unit's (see [`../../README.md`](../../README.md#a-units-yaml)); `spec` is described above. `spec.enabled: false` plans nothing.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd k8s-installs/modules/model-weights
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/k8s/<cluster>/model-weights.<model>/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/model-weights.<model>.yaml
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_with_defaults`, `s3_source`, `https_source`, `versions_are_separate_paths`, `first_version_release_name`, `bad_source_rejected_*` (four), `missing_model_store_rejected`, `disabled_plans_nothing`).

### Outputs

| Output | |
|---|---|
| `model` | Model name used in paths and as vllm's served model name. |
| `version` | Pinned version copied: a Hugging Face commit SHA or the source's label. |
| `source` | Where the weights came from: type (huggingface, s3, https) and uri. |
| `s3_prefix` | Copied weights: s3://<bucket>/<model>/<version>/, complete once _COMPLETE exists. |
| `cache_path` | Where model servers find the weights through the FSx cache. |
| `size_gib` | Declared size of the weights in GiB; vllm sizes its startup budget from it. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Used by: vllm (the model it serves). Destroy that first. Destroying this unit removes the Job record only: the weights stay in S3, since the copy role cannot delete. Removing a version from the bucket is a deliberate step outside Phoenix.
