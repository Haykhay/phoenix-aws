# Backstage-driven Terraform for infrastructure (Phoenix)

Status: approved (first iteration) · 2026-10-23

## Why

Developers, groups of developers and researchers need to stand AWS environments
up themselves — on Monday, used all week, gone at the weekend or when idle —
without an infrastructure engineer in the loop. Backstage is the front door: a
person fills in a form, Backstage opens a pull request, and GitHub Actions runs
Terraform against AWS. This repo is the first piece; a locally run Backstage
will drive it, and further repos (Backstage templates, workload promotion)
follow later.

Everything starts afresh: no existing state, environments or module versions
are carried over.

## Goals

- One YAML file per deployed unit (environment / scope / resource set),
  written by Backstage in a PR. That file is the whole input for one Terraform
  run.
- Plain Terraform, one root per resource set. No Terragrunt, no helper
  scripts.
- One GitHub Actions workflow that can `plan`, `apply` or `destroy` a single
  YAML file on request (Backstage calls it), and plans changed YAML files on a
  PR.
- Sandbox changes need no approval; stage, UAT and prod need approval,
  with approvers defined by the groups in Backstage (later).
- Mandatory ownership tags: defaults cover what they can, Backstage supplies
  the rest, Terraform refuses to run without them.
- VPC address space comes from IPAM only; no overlap checking in this repo.
- Organisation is a variable; project name is Phoenix.
- Observability that survives the weekly teardown: each EKS cluster runs its
  own Grafana stack, with history in a long-lived S3 bucket in the group
  account. GPU and model (vLLM) monitoring included.

## Accounts and groups

- Every AWS account belongs to one **group** (developers, engineers or
  researchers always work in a group). One account holds that group's
  environments: its shared ones and any standalone ones its members request.
- If the group has no account yet, Backstage runs a separate account workflow
  first (StackSets, another repo). It creates the account, its state bucket
  and its deploy role, and records them in a DynamoDB table. Backstage reads
  that table and writes the values into the YAML. This repo never creates
  accounts, buckets or deploy roles.
- Resource names carry the group, and for a standalone request also the
  requester, so environments sharing an account cannot collide.

## Non-goals (this repo)

- The central ECR hub and the Artifactory → hub sync.

- Anything running inside the clusters (Grafana stack, vLLM, Langfuse, GPU operator).

- Account vending, state buckets, deploy roles (StackSets, separate repo).
- Backstage itself: templates, environment constants, forms, ordering,
  schedules, manager approval of schedules, idle detection, teardown triggers,
  merging sandbox PRs.
- Workload / model promotion between environments.
- The final role-assumption model (undecided — see Constraints).

## Anti-goals

- Anything that needs a human to run a script or remember an order of
  operations. Ordering is Backstage's job; the repo just has to be safe to
  call in that order.
- A config validator or schema that duplicates what Terraform checks
  (`validation`, `precondition`) or what IPAM guarantees.
- An environment that can come up untagged.

## How it is used

| Kind | Example | Approval | Lifetime (owned by Backstage) |
|---|---|---|---|
| Personal sandbox | one researcher, isolated | none | destroyed Friday evening or when idle |
| Group, scheduled | a team's Mon–Fri environment, schedule approved by its engineering manager | none (sandbox) | stood up and destroyed on the schedule; no schedule, no rebuild |
| Group, always on | a research group's shared environment | none (sandbox) | `LongLive: true`, kept |
| Stage / UAT / prod | promotion targets | approvers from Backstage groups (later) | kept |

## Repo layout (target)

```text
modules/
  context/            shared child module: naming, tags, network lookup (new)
  credentials/        password/secret library (unchanged role)
  core-network/  core-platform/  dns/  data-rds/  data-elasticache/  data-msk/
  ecr/ (pull-through cache)  observability/ (replaces groundcover-ingester)
environments/<tier>/<env_id>/<scope>/<resource-set>.yaml     written by Backstage
.github/workflows/terraform.yml
README.md
```

Removed: `root.hcl`, `stacks/`, `scripts/` (all of it, including
`validate-config.py` and its tests), `catalog/schemas/`, `config/`
(JSON environments and `region-codes.json`), every `terragrunt.hcl`, the
`.terraform/` caches under `modules/`.

`<scope>` is an AWS region or `global` (dns only), as today.

## The YAML file

One file per unit. Backstage writes the environment constants into every file
it creates, so each file stands alone.

```yaml
# environments/sandbox/vision-sandbox-jdoe/eu-west-1/core-platform.yaml
organisation: acme
project: phoenix            # fixed
group: vision               # owning group; its account is account_id
requester: jdoe             # standalone request only; omitted for group environments
environment: sandbox       # env_id = <group>-<environment>[-<requester>] = vision-sandbox-jdoe
tier: sandbox               # sandbox | stage | uat | prod
region: eu-west-1           # omitted for global scope
account_id: "111111111111"
module_ref: main            # git ref of this repo the modules run from

state:
  bucket: acme-terraform-state-111111111111
  region: eu-west-1
  kms_key_id: arn:aws:kms:...   # optional


tags:                        # mandatory: owner.team, Reason
  owner.team: research
  owner.squad: vision        # optional
  Reason: model evaluation
  LongLive: false            # absent or false = ephemeral

spec:                        # the resource set's own settings
  default_cluster: "1"
  clusters:
    "1": { version: "1.34", node_groups: { ... } }
```

`spec` carries the same keys each module reads today from its JSON
`resource_sets.<name>` entry, so module logic changes only at the point where
config is loaded (`jsondecode(file(var.config_path))...` →
`yamldecode(file(var.config_file)).spec`). Keys are unchanged unless listed
under Module changes.

## Terraform roots

Each `modules/<resource-set>/` is a root module runnable on its own:

- `backend "s3" {}` — partial; the workflow supplies bucket, key, region, KMS
  key and `use_lockfile = true` at `init`. Key:
  `<env_id>/<scope>/<resource-set>/terraform.tfstate`.
- `variable "config_file"` — path to the YAML.
- `module "context"` — reads the YAML and returns:
  - `name_prefix` — `<env_id>-<region code>`, i.e. `<group>-<environment>[-<requester>]-<region code>`
    (no region code for global); the region-code map moves from
    `config/region-codes.json` into this module. Overridable by
    `name_prefix` in the YAML. Tags also carry `Group` and, when set,
    `Requester`.
  - `tags` — `Project = "Phoenix"`, `Organisation`, `Environment`, `Scope`,
    `Region`, `ResourceSet`, `ManagedBy = "Terraform"`, plus the YAML `tags`.
    `validation` fails when `owner.team` or `Reason` is missing, or `LongLive`
    is not a boolean.
  - `network` — for VPC-bound sets (core-platform, data-rds,
    data-elasticache, data-msk): the selected VPC from core-network's remote
    state (`<environment>/<scope>/core-network/terraform.tfstate` in the same
    bucket), replacing `_network_generated.tf`. Tolerates missing state on
    destroy, as the generated file did.
  - `pipeline_user` seed for `CreatedBy` (from `GITHUB_ACTOR` via a variable).
- `providers.tf` — default `aws` provider with `region`,
  `allowed_account_ids` and `default_tags` from `module.context`. The extra
  provider aliases that `stacks/*.hcl` generated (networking account for
  core-network; for dns, the management account — the delegated admin
  account holding the parent zones, `spec.providers.management`)
  move into those modules' own `providers.tf`, with role ARNs from the YAML
  (`spec.providers.<alias>.account_id`) instead of hardcoded account IDs.
- `versions.tf` — required Terraform and provider versions (from
  `stacks/provider_versions.hcl`).

Upstream modules stay on the public Terraform registry
(`terraform-aws-modules/*`, the originals of the old GitLab forks), pinned by
`version`. `credentials` stays a relative `../credentials` source.

## Module changes

- **All**: config loading as above; `var.config_path`, `var.environment`,
  `var.scope`, `var.region`, `var.account_id`, `var.organisation`,
  `var.pipeline_user` and the generated naming/network locals are replaced by
  `module.context` outputs.
- **core-network**: pool (IPAM) VPCs only. `cidr`, `private_subnets_*`,
  `public_subnets` and the literal-CIDR code path are removed; `pool` becomes
  required. Transit-gateway features stay as-is.
- **Cross-value checks** that `validate-config.py` did and are still wanted
  become `precondition`s in the module that owns them: `dns` only in `global`;
  data stores name their `eks_clusters` when more than one cluster exists;
  one addon pin not shared across Kubernetes versions. CIDR checks are dropped
  (IPAM).

## Observability

Decision: self-hosted Grafana stack **per EKS cluster**, history kept in the
group account so it survives teardown. Grafana + Langfuse rather than a SaaS,
because the groups will serve models with vLLM.

| Signal | Collected by (in-cluster, next repo) | Stored in |
|---|---|---|
| Metrics: cluster, nodes, vLLM (`/metrics`), GPU (NVIDIA DCGM exporter) | Prometheus scrape → Mimir | group observability bucket |
| Logs | Grafana Alloy / OTel collector → Loki | group observability bucket |
| Traces: apps, vLLM (OpenTelemetry) | OTel collector → Tempo | group observability bucket |
| AWS service metrics (RDS, ElastiCache, MSK, ALB) | Grafana CloudWatch data source, read-only role | CloudWatch |
| Model calls: prompts, responses, tokens, cost | Langfuse SDK / OTel | Langfuse (Postgres + ClickHouse + Redis + S3) |

**This repo provides (AWS side only):**

- **`observability`** resource set — account-level, one per group account per
  region, `LongLive: true`, so weekend teardowns never touch it:
  - S3 bucket for Mimir, Loki, Tempo and Langfuse blob storage, prefixed per
    cluster, with
    lifecycle expiry per signal (retention in the YAML `spec`). Layout is
    `<signal prefix><cluster name>/…` (`mimir/`, `loki-`, `tempo/`, `langfuse/`;
    Loki cannot take a slash in its prefix) — S3 lifecycle filters match leading
    prefixes only, so the signal comes first; each writer role is scoped to
    `<signal prefix>${aws:PrincipalTag/eks-cluster-name}/*` (Pod Identity session tag).
  - KMS key for the bucket.
  - IAM roles for EKS Pod Identity — one per writer (Mimir, Loki, Tempo,
    Langfuse), each scoped to its own prefix — and a read-only CloudWatch role
    for Grafana. The Pod Identity *associations* are made per cluster by
    core-platform, which reads these role ARNs from the observability state.
  - Replaces `groundcover-ingester` (removed, with its Firehose, Lambda and
    groundcover provider).
- **`core-platform`**:
  - GPU node groups for vLLM (NVIDIA-ready EKS AL2023 image, GPU instance
    types, `nvidia.com/gpu` taint), and Karpenter able to provision GPU nodes
    on demand so idle GPUs scale to zero.
  - Pod Identity associations binding the observability roles to the
    in-cluster service accounts.
  - Monitoring overhead (~2–4 vCPU, 8 GB+) budgeted in the default node group.
- **Langfuse backing services**, per environment, from existing modules:
  Postgres via `data-rds`, Redis via `data-elasticache`, blobs in the
  observability bucket. ClickHouse runs in-cluster (no managed AWS
  equivalent).

**Elsewhere:**

- Next repo (in-cluster): Grafana, Mimir, Loki, Tempo, Alloy/OTel collector,
  NVIDIA DCGM exporter and GPU operator, vLLM, Langfuse, ClickHouse, the vLLM
  and GPU dashboards.
- Backstage repo: the Grafana plugin; each environment's entity carries its
  Grafana URL.

**Accepted trade-offs:** no single cross-environment view (one Grafana per
cluster; a central Grafana reading the group buckets can be added later);
each cluster pays the monitoring overhead.

## Container images (ECR)

Decision: **hub and spoke**. ECR's pull-through cache cannot use Artifactory as
an upstream (supported: ECR Public, Kubernetes registry, Quay, Docker Hub,
Azure CR, GHCR, GitLab SaaS, Chainguard, and another ECR), so:

- **Hub — outside this repo** (shared tooling, like account vending): one
  central ECR, filled from the company's Artifactory by a scheduled sync
  (e.g. `regsync`/`skopeo`), with a registry policy letting the group
  accounts' pull-through role read it.
- **Spoke — `ecr` resource set, one per group account per region:**
  - `aws_ecr_pull_through_cache_rule`: prefix `spec.cache_prefix` (default
    `artifactory`) → upstream `<hub account>.dkr.ecr.<hub region>.amazonaws.com`,
    optional upstream repository prefix.
  - IAM role ECR assumes for the cross-account pull (trust
    `pullthroughcache.ecr.amazonaws.com`), read-only on the hub.
  - Repository creation template for the cache prefix: KMS encryption,
    immutable tags, lifecycle (expire untagged, keep the last N).
  - IAM policy granting first-pull rights (`ecr:BatchImportUpstreamImage`,
    `ecr:CreateRepository` on the prefix) for core-platform's
    `node_role_additional_policies`.
- Workloads pull `<account>.dkr.ecr.<region>.amazonaws.com/<cache prefix>/<repo>:<tag>`;
  AWS refreshes cached tags from the hub at least daily. A group account holds
  only what its workloads actually pull.
- The old per-account repositories and CI push role are dropped: CI publishes
  to Artifactory, not to group accounts. *(Designer's call.)*

## Dependencies (Backstage orders runs by this)

```text
core-network ──► core-platform ──► data-rds / data-elasticache / data-msk
observability ──► core-platform   (bucket + roles exist before clusters write to them)
dns, ecr: independent
```

Apply in that order; destroy in reverse. A run whose dependency has no state
fails at plan with a clear message rather than planning on placeholders.

## Workflow

`.github/workflows/terraform.yml`:

- **pull_request** touching `environments/**.yaml`: matrix over changed files,
  `plan` each, plan summary in the job summary.
- **workflow_dispatch** (Backstage): inputs `config_file`, `action`
  (`plan | apply | destroy`). `apply`/`destroy` only from `main`.
- Steps per run: checkout `main` (the YAML) → checkout `module_ref` from the
  YAML into a second path (the modules) → set up Terraform → authenticate
  (Constraints) → `terraform init` with backend config from the YAML →
  `plan` / `apply` / `destroy` in `modules/<resource-set>` with
  `-var config_file=<abs path>`.
- `concurrency` group per config file, so two runs never touch one state.
- A run exits non-zero on failure so Backstage can stop the chain.

## Approval

- No CODEOWNERS yet. Who approves what is defined with the **groups in
  Backstage** (later), and the repo's approval rules follow from that.
- Until then: Backstage's GitHub App merges sandbox PRs itself; stage, UAT and
  prod need a review rule on `main`, keyed on `environments/<tier>/`, once the
  groups exist.

## Versioning

- Sandbox YAML uses `module_ref: main`.
- Stage, UAT and prod pin a repo-wide release tag (`v0.1.0`, ...) created as a
  GitHub Release. Promotion of infrastructure is a PR changing `module_ref`.
  *(Builder's call, made in the conversation without objection.)*

## Constraints

- **Roles are known by name; only account IDs vary.** Every account has a
  deploy role named `Terraform-Role` (created by account vending / StackSets,
  built later), so the YAML carries account IDs only — `account_id` for the
  unit itself, `spec.providers.<management|network>.account_id` for
  cross-account hops — and Backstage just fetches IDs from DynamoDB. The
  workflow assumes `arn:aws:iam::<account_id>:role/Terraform-Role` over GitHub
  OIDC; modules build cross-account ARNs from `module.context.role_name`. The
  StackSets must create that role, trusting GitHub OIDC (unit accounts) and the
  organisation's deploy roles (management, networking).
- Terraform ≥ 1.15; AWS provider ~> 5.0; Terragrunt is not used anywhere.
- Must work with a locally run Backstage: everything Backstage needs is a PR
  to this repo plus `workflow_dispatch` calls.

## Left to the builder

- Exact file split inside each module; whether `context` outputs a single
  object or several.
- Plan-summary formatting.
- README rewrite to match.

## Calls made by the designer (check these)

- `env_id` = `<group>-<environment>[-<requester>]` is the unique key: path,
  state key and name prefix. Tier leads the path so approval rules can key on it.

- One repo-wide release tag for promotion, not per-module tags.
- Account-level resource sets (`ecr`, `observability`) are deployed once per
  group account, from the group's `shared` environment, `requester` unset.
- `shared-config` (cross-account database-secret reader) and
  `private-ca-roles-anywhere` (on-prem only) are removed: not needed now.
- A derived name that exceeds an AWS limit fails at plan (`validation`)
  rather than being silently truncated or hashed.
- `context` validates `group` and `requester` to the same lowercase
  charset as `environment`.
- One observability bucket per group account per region, prefixed per
  environment, rather than a bucket per environment — it has to outlive the
  environments.
- Langfuse's ClickHouse runs in-cluster; its state is lost on teardown unless
  backed up to the bucket (left to the next repo).
