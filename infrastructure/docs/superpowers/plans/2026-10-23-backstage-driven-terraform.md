# Backstage-driven Terraform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Terragrunt carcass into plain Terraform roots driven by one YAML file per unit, run by a single GitHub Actions workflow that Backstage dispatches.

**Architecture:** A shared `modules/context` child module reads the unit's YAML and produces identity, naming, mandatory tags, state location and (for VPC-bound sets) the selected VPC from core-network's remote state. Every resource-set root replaces the Terragrunt-generated inputs with that module through one identical `_context.tf` plus `providers.tf`/`backend.tf`/`versions.tf`. A new `observability` root replaces `groundcover-ingester`.

**Tech Stack:** Terraform ≥ 1.15 (`terraform test` with `mock_provider`), AWS provider ~> 5.0, `terraform-aws-modules/*` from the public registry, GitHub Actions, `yq` (preinstalled on `ubuntu-latest`).

**Spec:** `docs/superpowers/specs/2026-10-23-backstage-driven-terraform-design.md`

## Global Constraints

- No Terragrunt, no `scripts/`, no JSON schema anywhere in the repo when done.
- Terraform `>= 1.15.0`; `aws ~> 5.0`; `random ~> 3.0`; upstream modules pinned by `version` from `terraform-aws-modules/*`.
- `env_id` = `join("-", compact([group, environment, requester]))`.
- YAML path: `environments/<tier>/<env_id>/<scope>/<resource-set>.yaml`; `tier` ∈ `sandbox | stage | uat | prod`; `scope` = the YAML `region`, or `global` when `region` is absent.
- State key: `<env_id>/<scope>/<resource-set>/terraform.tfstate`; `use_lockfile = true`; `encrypt = true`.
- Name prefix: `<env_id>-<region code>`; global scope: `<env_id>`. YAML `name_prefix` overrides.
- Region codes: `ap-northeast-2=apne2, eu-central-1=euc1, eu-west-1=euw1, eu-west-2=euw2, sa-east-1=sae1, us-east-1=use1`.
- Global-scope provider region: YAML `global_region`, default `us-east-1`.
- Tags on everything: `Project = "Phoenix"`, `Organisation`, `Group`, `Requester` (only when set), `Environment` (= env_id), `Tier`, `Scope`, `Region`, `ResourceSet`, `ManagedBy = "Terraform"`, plus YAML `tags`. `owner.team` and `Reason` required; `LongLive` must be a boolean when present.
- Identifiers (`organisation`, `group`, `environment`, `requester`) match `^[a-z][a-z0-9]*(-[a-z0-9]+)*$`.
- Sandbox YAML `module_ref: main`; stage/uat/prod pin a release tag.
- **Commits:** the user has asked for no commits yet. Every "Checkpoint" step is a commit to make *only* once that hold is lifted; until then, stop at the check. No AI attribution in commit messages.

## Review Focus

1. **Destroy after a dependency is gone** (Backstage tears down core-network before a data set retry): `module.context.network` must be `null`, not an error, when core-network state is missing — destroy of the consumer must still plan. Test in Task 2 (`network_missing_state_is_null`).
2. **Two researchers in one group** (`requester` differs, same `environment`): name prefixes, state keys and paths must differ. Test in Task 2 (`requester_isolates_names`).
3. **A long `env_id`** pushing an ElastiCache replication-group ID past 40 characters: plan must fail with a message naming the limit, not truncate. Test in Task 5 (`elasticache_name_too_long`).
4. **`LongLive: "false"` as a string** (reads truthy, would keep an ephemeral env alive): must fail. Test in Task 2 (`longlive_string_rejected`).
5. **Global-scope YAML with no `region`** (dns): scope `global`, provider region `us-east-1`, prefix without region code. Test in Task 2 (`global_scope_defaults`).

---

### Task 1: Strip Terragrunt, scripts and the old config model

**Files:**
- Delete: `root.hcl`, `stacks/`, `scripts/`, `catalog/`, `config/`, `environments/` (all `terragrunt.hcl`), `.github/actions/aws-terragrunt/`, `.github/workflows/infrastructure.yml`, every `modules/*/.terraform/` and `.terraform.lock.hcl`, `modules/groundcover-ingester/` (replaced in Task 7)
- Modify: `.gitignore` (keep the Terraform entries; drop `.terragrunt-cache/`)

**Interfaces:**
- Produces: a repo containing only `modules/`, `docs/`, `.github/`, `.gitignore`, `README.md`.

- [ ] **Step 1: Delete the paths above.**
- [ ] **Step 2: Verify nothing still references them**

Run: `grep -rnE 'terragrunt|root\.hcl|stacks/|scripts/|validate-config|config_path|environment\.schema|groundcover' --exclude-dir=.git --exclude-dir=docs . | grep -v README`
Expected: matches only inside `modules/*/*.tf` that later tasks rewrite (`var.config_path`). Nothing else.

- [ ] **Step 3: Checkpoint** — `chore: remove Terragrunt, helper scripts and JSON config model`

---

### Task 2: `modules/context`

**Files:**
- Create: `modules/context/variables.tf`, `modules/context/main.tf`, `modules/context/outputs.tf`, `modules/context/versions.tf`, `modules/context/README.md`
- Test: `modules/context/tests/context.tftest.hcl`, fixtures `modules/context/tests/fixtures/{regional,global,personal,bad_tags,longlive_string}.yaml`

**Interfaces:**
- Consumes: nothing.
- Produces (every root uses exactly these):
  - inputs: `config_file` (string), `resource_set` (string), `network` (bool, default `false`), `pipeline_user` (string, default `"unknown"`)
  - outputs: `config` (any — whole YAML), `spec` (any — `try(config.spec, {})`), `organisation`, `group`, `requester` (string or null), `environment`, `env_id`, `tier`, `scope`, `region`, `account_id`, `region_code` (null for global), `name_prefix`, `tags` (map(string)), `state` (object `{bucket, region, kms_key_id}`), `state_key` (this unit's key), `network` (object as core-network's `networks[<vpc>]`, or null), `pipeline_user`

- [ ] **Step 1: Write the failing tests** in `context.tftest.hcl`, all `command = plan`, `variables { resource_set = "core-platform" }`:
  - `regional_identity`: `regional.yaml` (org `acme`, group `vision`, environment `sandbox`, region `eu-west-1`, account `111111111111`) → `env_id == "vision-sandbox"`, `scope == "eu-west-1"`, `name_prefix == "vision-sandbox-euw1"`, `state_key == "vision-sandbox/eu-west-1/core-platform/terraform.tfstate"`, `tags["Project"] == "Phoenix"`, `tags["ResourceSet"] == "core-platform"`, `!contains(keys(tags), "Requester")`.
  - `requester_isolates_names`: `personal.yaml` (same + `requester: jdoe`) → `env_id == "vision-sandbox-jdoe"`, `name_prefix == "vision-sandbox-jdoe-euw1"`, `tags["Requester"] == "jdoe"`.
  - `global_scope_defaults`: `global.yaml` (no `region`) → `scope == "global"`, `region == "us-east-1"`, `name_prefix == "vision-sandbox"`, `region_code == null`.
  - `missing_owner_rejected`: `bad_tags.yaml` (no `owner.team`) → `expect_failures = [output.tags]`.
  - `longlive_string_rejected`: `longlive_string.yaml` (`LongLive: "false"`) → `expect_failures = [output.tags]`.
  - `network_from_core_network_state`: `regional.yaml`, `network = true`, `override_data { target = data.terraform_remote_state.core_network[0]; values = { outputs = { default_vpc_name = "vision-sandbox-euw1-vpc-1", networks = { "vision-sandbox-euw1-vpc-1" = { vpc_id = "vpc-123" } } } } }` → `network.vpc_id == "vpc-123"`.
  - `network_missing_state_is_null`: as above with `outputs = {}` → `network == null`.
  - `bad_identifier_rejected`: `regional.yaml` with `group: Vision` (separate fixture) → `expect_failures = [output.name_prefix]`.

- [ ] **Step 2: Run to verify they fail**
Run: `cd modules/context && terraform init -backend=false && terraform test`
Expected: FAIL — no configuration.

- [ ] **Step 3: Implement.** `yamldecode(file(var.config_file))`; region-code map as a local (Global Constraints); `data "terraform_remote_state" "core_network"` with `count = var.network ? 1 : 0`, backend `s3`, key `<env_id>/<scope>/core-network/terraform.tfstate`, `defaults = {}`; selected VPC = `spec.vpc` if set, else `default_vpc_name` from that state, wrapped in `try(..., null)`. Validation as `precondition`s on `output "tags"` (owner.team, Reason, LongLive bool) and `output "name_prefix"` (identifier regex on org/group/environment/requester).

- [ ] **Step 4: Run tests to verify they pass**
Run: `terraform test`
Expected: `8 passed, 0 failed`.

- [ ] **Step 5: Checkpoint** — `feat(context): YAML-driven identity, naming, tags and network lookup`

---

### Task 3: Root boilerplate + `core-network` (IPAM only)

**Files:**
- Create: `modules/core-network/{_context.tf,providers.tf,backend.tf,versions.tf}`; test `modules/core-network/tests/core_network.tftest.hcl`, fixture `modules/core-network/tests/fixtures/core-network.yaml`
- Modify: `modules/core-network/{locals.tf,main.tf,data.tf,outputs.tf,README.md}`

**Interfaces:**
- Consumes: `module.context` (Task 2).
- Produces — the boilerplate every later root copies verbatim, changing only `resource_set` and `network`:
  - `_context.tf`: `variable "config_file" {type = string}`, `variable "pipeline_user" {type = string, default = "unknown"}`, `module "context" { source = "../context" … }`, and bridging locals `environment = module.context.env_id`, `scope`, `region`, `account_id`, `organisation`, `base_name_prefix = module.context.name_prefix`, `core_network = module.context.network`, `config = merge(local.resource_set_defaults, module.context.spec)`.
  - `providers.tf`: default `aws` provider — `region`, `allowed_account_ids = [account_id]`, `default_tags { tags = module.context.tags }`, `ignore_tags { keys = ["kubernetes.io/role/internal-elb"] }`.
  - `backend.tf`: `terraform { backend "s3" {} }`.
  - `versions.tf`: Global Constraints versions.
  - Unchanged output contract: `networks`, `default_vpc_name`, `vpc_names`.

- [ ] **Step 1: Write the failing test** (`mock_provider "aws" {}`, `mock_provider "aws" { alias = "network" }`, `mock_provider "aws" { alias = "network_dublin" }`, `override_data` for `data.terraform_remote_state.network` / `network_dublin` / `data.aws_vpc_ipam_pool.this`):
  - `pool_vpc_plans`: fixture with one VPC `vpc-1 = { pool = "nonprod", azs = [a,b,c] }` → `output.vpc_names == ["vision-sandbox-euw1-vpc-1"]`.
  - `literal_cidr_rejected`: VPC with `cidr = "10.0.0.0/16"` → `expect_failures` on the `terraform_data.validation` precondition.
  - `network_providers_from_spec`: the network provider role ARN comes from `spec.providers.network.role_arn` (assert via a `locals`-exposed output `network_role_arn`).

- [ ] **Step 2: Run to verify it fails** — `terraform test` → FAIL.
- [ ] **Step 3: Implement.** Replace every `var.config_path`/`local.environment_config`/`local.scope_config`/`local.resource_sets` read with `module.context.*` / `local.config`; `var.environment|scope|region|account_id` → `local.*`. Remove the literal-CIDR path (`cidr`, `private_subnets_*`, `public_subnets`); `pool` required (precondition). Move the `aws.network`/`aws.network_dublin` providers (previously `stacks/core-network.hcl`) into `providers.tf`, `assume_role.role_arn = local.config.providers.network.role_arn`, `allowed_account_ids` derived from that ARN. Networking remote-state bucket/role in `data.tf` come from `local.config.providers.network` (`state_bucket`, `role_arn`) instead of literals.
- [ ] **Step 4: Run tests** — `terraform test` → `3 passed`.
- [ ] **Step 5: Update `modules/core-network/README.md`** — remove literal-CIDR docs and the stale "Apply order" section; document `spec.providers.network`.
- [ ] **Step 6: Checkpoint** — `feat(core-network): YAML context, IPAM-only VPCs`

---

### Task 4: `observability` (new, account-level)

**Files:**
- Create: `modules/observability/{_context.tf,providers.tf,backend.tf,versions.tf,main.tf,iam.tf,outputs.tf,README.md}`; test `modules/observability/tests/observability.tftest.hcl`, fixture `tests/fixtures/observability.yaml` (`environment: shared`, `tags.LongLive: true`)

**Interfaces:**
- Consumes: `module.context` (`resource_set = "observability"`).
- Produces outputs read by core-platform (Task 5): `bucket_name`, `bucket_arn`, `kms_key_arn`, `writer_role_arns` (map: `mimir`, `loki`, `tempo`, `langfuse`), `grafana_cloudwatch_role_arn`.

- [ ] **Step 1: Write the failing tests** (`mock_provider "aws" {}`, `command = plan`):
  - `bucket_named_per_account`: `aws_s3_bucket.this.bucket == "vision-shared-euw1-observability-111111111111"`.
  - `retention_per_signal`: default spec → lifecycle rules with `filter.prefix` `"mimir/"`=30, `"loki/"`=14, `"tempo/"`=7, `"langfuse/"`=30 days; `spec.retention_days.loki = 30` overrides loki only.
  - `writer_scoped_to_cluster`: the mimir writer policy JSON contains `"arn:aws:s3:::vision-shared-euw1-observability-111111111111/mimir/${aws:PrincipalTag/eks-cluster-name}/*"`.
  - `pod_identity_trust`: every writer role's trust policy principal is `pods.eks.amazonaws.com` with actions `sts:AssumeRole`, `sts:TagSession`.
  - `requires_longlive`: fixture without `LongLive: true` → precondition failure on `aws_s3_bucket.this` ("observability must be LongLive").
- [ ] **Step 2: Run to verify they fail.**
- [ ] **Step 3: Implement** bucket (versioning off, SSE-KMS with the module's `aws_kms_key`, public access blocked, `force_destroy = false`), lifecycle per signal, four writer roles (S3 Get/Put/Delete/List on own `<signal>/${aws:PrincipalTag/eks-cluster-name}/*`, KMS encrypt/decrypt), Grafana role (trust as writers, managed `arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess`). Role names `<name_prefix>-<signal>` / `<name_prefix>-grafana-cloudwatch`.
- [ ] **Step 4: Run tests** → `5 passed`.
- [ ] **Step 5: Checkpoint** — `feat(observability): long-lived bucket and Pod Identity roles`

---

### Task 5: `core-platform` (network, GPU, observability bindings)

**Files:**
- Create: `modules/core-platform/{_context.tf,providers.tf,backend.tf,versions.tf,observability.tf}`; test `modules/core-platform/tests/core_platform.tftest.hcl`, fixture with a CPU and a GPU node group
- Modify: `modules/core-platform/{local.tf,main.tf,karpenter.tf,data.tf,README.md}`

**Interfaces:**
- Consumes: `module.context` (`network = true`); observability outputs (Task 4) via `data "terraform_remote_state" "observability"` at key `<group>-<spec.observability.environment, default "shared">/<scope>/observability/terraform.tfstate`.
- Produces: unchanged `clusters` output contract (data-* read `clusters[<key>].node_security_group_id`).

- [ ] **Step 1: Write the failing tests** (`mock_provider "aws" {}`; `override_data` for `module.context.data.terraform_remote_state.core_network[0]` with one VPC and three subnet IDs, and for `data.terraform_remote_state.observability[0]`):
  - `cluster_in_selected_vpc`: `module.eks["1"]` plans with `vpc_id == "vpc-123"`.
  - `gpu_node_group_passthrough`: node group `gpu-1 = { ami_type = "AL2023_x86_64_NVIDIA", instance_types = ["g6.xlarge"], min_size = 0, taints = { gpu = { key = "nvidia.com/gpu", value = "true", effect = "NO_SCHEDULE" } } }` reaches `module.eks["1"]` `eks_managed_node_groups["gpu-1"].taints`.
  - `observability_associations`: with `spec.observability.enabled = true` → `aws_eks_pod_identity_association.observability` has keys `1/mimir`, `1/loki`, `1/tempo`, `1/langfuse`, `1/grafana`; `1/mimir` has `namespace = "monitoring"`, `service_account = "mimir"`; `1/langfuse` has `namespace = "langfuse"`.
  - `observability_disabled`: `enabled = false` → zero associations and no observability remote-state read.
- [ ] **Step 2: Run to verify they fail.**
- [ ] **Step 3: Implement.** Bridge locals as in Task 3; remove `local.core_network_outputs` uses in favour of `local.core_network`. `observability.tf`: remote state + `aws_eks_pod_identity_association` per `cluster × writer`, namespace/service-account defaults `mimir|loki|tempo|grafana → monitoring/<name>`, `langfuse → langfuse/langfuse`, overridable under `spec.observability.service_accounts`. Rename `ci_runners_cidr` to come from `spec.ci_runners_cidr` (null → rule omitted).
- [ ] **Step 4: Run tests** → `4 passed`.
- [ ] **Step 5: README** — GPU node-group example, observability block, removal of Terragrunt references.
- [ ] **Step 6: Checkpoint** — `feat(core-platform): YAML context, GPU node groups, observability bindings`

---

### Task 6: `data-rds`, `data-elasticache`, `data-msk`

**Files:**
- Create per module: `_context.tf`, `providers.tf`, `backend.tf`, `versions.tf`, `tests/<module>.tftest.hcl` + fixture
- Modify per module: `locals.tf`, `data.tf`, main `.tf`, `README.md`

**Interfaces:**
- Consumes: `module.context` (`network = true`); core-platform `clusters` output via the module's existing `terraform_remote_state.core_platform`, now keyed `module.context` state + `<env_id>/<scope>/core-platform/terraform.tfstate`; `../credentials` with `organisation = local.organisation`.

- [ ] **Step 1: Write the failing tests** (mock aws/random; overrides for core-network and core-platform state):
  - each module `plans_in_data_subnets`: subnet group uses the overridden data subnet IDs.
  - `eks_binding_required`: two clusters in core-platform state and an instance without `eks_clusters` → precondition failure (`data stores must name eks_clusters when more than one cluster exists`).
  - `elasticache_name_too_long` (data-elasticache): `group = "computational-biology"`, `environment = "sandbox"`, `requester = "jdoe-long"`, cluster `core-cache` → precondition failure naming the 40-character replication-group limit.
  - `secret_path_uses_organisation` (data-msk): SCRAM secret name starts `AmazonMSK_acme_`.
- [ ] **Step 2: Run to verify they fail.**
- [ ] **Step 3: Implement** — bridge locals; `remote_state` config from `module.context.state`; add the two preconditions on the module's main resource.
- [ ] **Step 4: Run tests** in each of the three modules → all pass.
- [ ] **Step 5: Checkpoint** — `feat(data-*): YAML context and binding preconditions`

---

### Task 7: `dns`, `ecr` (pull-through spoke); remove `shared-config`, `private-ca-roles-anywhere`

**Files:**
- Delete: `modules/shared-config/`, `modules/private-ca-roles-anywhere/` *(done at user request)*
- Create per module: `_context.tf`, `providers.tf`, `backend.tf`, `versions.tf`, `tests/<module>.tftest.hcl` + fixtures
- Modify: `modules/dns/{locals,main,outputs}.tf`, `README.md`; `modules/dns/providers.tf` gets the `aws.management` alias — the delegated admin account holding the parent zones (role from `spec.providers.management.role_arn`, no `profile`)
- Replace: `modules/ecr/*` with the pull-through spoke (spec section "Container images")

**Interfaces:**
- Produces (ecr): outputs `cache_prefix`, `registry_url_prefix` (`<account>.dkr.ecr.<region>.amazonaws.com/<cache prefix>`), `pull_through_role_arn`, `node_pull_policy_arn`.

- [ ] **Step 1: Write the failing tests:**
  - `dns_global_only`: dns fixture with `region: eu-west-1` → precondition failure (`dns belongs in the global scope`).
  - `dns_zone_names`: global fixture, zone `zone-1 = { public_zone_name = "vision.example.com", internal_zone_name = "internal.vision.example.com" }` → `aws_route53_zone.public["zone-1"].name == "vision.example.com"`.
  - `ecr_rule_points_at_hub`: `spec.hub.account_id = "999999999999"` → `aws_ecr_pull_through_cache_rule.this.upstream_registry_url == "999999999999.dkr.ecr.eu-west-1.amazonaws.com"`, `ecr_repository_prefix == "artifactory"`, `custom_role_arn` = the spoke role.
  - `ecr_template_encrypts`: `aws_ecr_repository_creation_template.this.prefix == "artifactory"`, `applied_for == ["PULL_THROUGH_CACHE"]`, encryption KMS.
  - `ecr_role_trusts_pull_through`: role trust principal `pullthroughcache.ecr.amazonaws.com`.
  - `ecr_requires_hub`: no `spec.hub.account_id` → precondition failure.
- [ ] **Step 2: Run to verify they fail.**
- [ ] **Step 3: Implement** bridge locals, the dns precondition, the ecr spoke.
- [ ] **Step 4: Run tests** → all pass; `grep -rn 'profile *= *"oidc"' modules` → no output.
- [ ] **Step 5: Checkpoint** — `feat: YAML context for dns; ecr pull-through spoke; drop shared-config, private-ca`

---

### Task 8: Workflow, example environments, README

**Files:**
- Create: `.github/workflows/terraform.yml`; example YAMLs `environments/sandbox/vision-shared/eu-west-1/observability.yaml`, `environments/sandbox/vision-sandbox-jdoe/eu-west-1/{core-network,core-platform,data-rds}.yaml`, `environments/sandbox/vision-sandbox-jdoe/global/dns.yaml` (placeholder account `111111111111`, org `acme`)
- Modify: `README.md`
- Delete: `.github/CODEOWNERS` *(done at user request: approvers come with Backstage groups)*

**Interfaces:**
- Consumes: every root's `config_file` and `pipeline_user` variables; YAML fields `module_ref`, `role_arn`, `state.{bucket,region,kms_key_id}`, `tier`.
- Produces for Backstage: `workflow_dispatch` inputs `config_file` (repo-relative YAML path) and `action` (`plan|apply|destroy`); non-zero exit on failure.

- [ ] **Step 1: Write the workflow:**
  - triggers: `pull_request` (paths `environments/**.yaml`), `workflow_dispatch` (inputs above).
  - job `changed` (PR only): list changed YAML as a JSON matrix from `git diff --name-only origin/${{ github.base_ref }}...HEAD -- 'environments/**.yaml'`.
  - job `run`: matrix of one file (dispatch) or the changed list (PR); `concurrency: tf-${{ file }}`, `cancel-in-progress: false`; `permissions: id-token: write, contents: read`.
  - steps: checkout (YAML at `main`/PR head) → read `module_ref`, `role_arn`, `state.*`, `tier` with `yq`, resource set = file basename, scope = parent dir → checkout `module_ref` into `src/` → `hashicorp/setup-terraform@v3` (`~1.15.0`, wrapper off) → `aws-actions/configure-aws-credentials@v4` (`role-to-assume` from YAML) → `terraform -chdir=src/modules/<rs> init` with `-backend-config` for `bucket`, `key=<env_id>/<scope>/<rs>/terraform.tfstate`, `region`, `kms_key_id` (if set), `encrypt=true`, `use_lockfile=true` → plan/apply/destroy with `-var config_file=$GITHUB_WORKSPACE/<file> -var pipeline_user=${{ github.actor }}`; plan output summarised into `$GITHUB_STEP_SUMMARY`.
  - guards: `apply`/`destroy` refuse unless `github.ref == 'refs/heads/main'`; the env_id derived from the path must equal the one in the YAML.
- [ ] **Step 2: Lint**
Run: `actionlint .github/workflows/terraform.yml` (install: `brew install actionlint`)
Expected: no output.
- [ ] **Step 3: (removed — no CODEOWNERS until Backstage groups exist)**
- [ ] **Step 4: Validate every example YAML end to end**
Run: `for f in environments/**/*.yaml; do rs=$(basename $f .yaml); (cd modules/$rs && terraform init -backend=false >/dev/null && terraform validate) || echo "FAIL $f"; done`
Expected: no `FAIL` lines.
- [ ] **Step 5: README** — rewrite around the YAML file, the roots, the dependency order (`observability → core-platform`, `core-network → core-platform → data-*`), dispatch inputs, approval model, observability; delete every Terragrunt/GitLab section.
- [ ] **Step 6: Final sweep**
Run: `grep -rniE 'terragrunt|gitlab|config_path|root\.hcl|groundcover' --exclude-dir=.git . | grep -v docs/superpowers`
Expected: no output.
- [ ] **Step 7: Checkpoint** — `feat: GitHub Actions runner for Backstage, example environments, README`
