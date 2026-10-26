# k8s-installs Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn k8s-installs into plain-Terraform, YAML-driven cluster components that Backstage installs per workload type, database type and GPU type.

**Architecture:** One Terraform root per component (`modules/<component>`), one YAML unit per component per cluster, read through infrastructure's `modules/context` plus a new `modules/cluster` lookup. The single GitHub workflow runs both layers; k8s units run on the `phoenix-mgmt` self-hosted runner. Backstage reads workload/database/GPU/model/component entities from its catalog and writes the units.

**Tech Stack:** Terraform 1.15 (`terraform test`, mock providers), providers aws ~> 5.0, helm ~> 3.0, kubernetes ~> 2.38, random ~> 3.0; GitHub Actions; Backstage 1.55 scaffolder.

**Spec:** `k8s-installs/docs/superpowers/specs/2026-10-24-k8s-installs-backstage-design.md`

## Global Constraints

- No Terragrunt, no JSON config, no GitLab, no helper scripts in the repo; plain Terraform with a partial `backend "s3" {}`.
- No company identifiers (eeze, tain, polaris, real account IDs, company domains/Jira/GitLab URLs). Project name `Phoenix`; organisation comes from the YAML.
- Unit path: `k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/<component>[.<instance>].yaml`; module = file name up to the first dot.
- State key: `<env_id>/<region>/k8s/<cluster>/<component>[.<instance>]/terraform.tfstate`, same bucket as Layer 2.
- Roles by name: `arn:aws:iam::<account_id>:role/Terraform-Role`.
- k8s units run on `[self-hosted, phoenix-mgmt]`; AWS units and all module tests on GitHub-hosted runners.
- `module_ref`: `main` for sandbox, a release tag for stage/UAT/prod.
- Users never choose versions/sizes: every chart version is pinned in the module's `locals.defaults` (chosen ≥ 2 weeks old, recorded in the module README).
- Pod Identity bindings already created by core-platform: `monitoring/mimir`, `monitoring/loki`, `monitoring/tempo`, `langfuse/langfuse`, grafana CloudWatch role — namespaces and service accounts must match exactly.
- Tools: Terraform 1.15.7, actionlint, yq from the session scratchpad `bin/` (`$TF`, `$ACTIONLINT`, `$YQ` below). Downloads checksum-verified.
- Commits: on hold until the owner lifts it; every "Commit" step below is skipped until then (no AI attribution when it happens).

## Review Focus

1. A unit naming a cluster key core-platform does not have, or an env whose core-platform state is missing → plan fails with a message naming env and cluster, before any Helm/Kubernetes call (Task 1 tests `unknown_cluster_rejected`, `missing_core_platform_rejected`).
2. Two instances of one component in one cluster (two models, two Postgres clusters) → distinct release names, namespaces where per-instance, and IAM names (Task 7 `two_instances_do_not_collide`, Task 9 `two_models_do_not_collide`).
3. Namespace/service account drift from core-platform's Pod Identity bindings → observability writes fail silently in-cluster (Task 4 `bindings_match_core_platform`, Task 9 `langfuse_binding_matches`).
4. Personal environments' long names (`research-sandbox-jdoe-euw1-1…`) overrunning IAM (64) / Helm release (53) limits → plan error (Task 6 `personal_env_names_fit`, Task 1 `name_prefix_includes_cluster`).
5. A Kargo spoke planned before its management cluster's Kargo exists → clear plan error, not a provider crash (Task 8 `spoke_without_management_rejected`).

---

### Task 1: Clean slate, shared cluster lookup, component boilerplate

**Files:**
- Delete: `k8s-installs/{root.hcl,.gitlab-ci.yml,CODEOWNERS,.terraform.lock.hcl,.terraform/,stacks/,scripts/,config/,environments/,catalog/}`, `modules/{groundcover-sensor,cert-manager-aws-pca-issuer,k8s-image-swapper,cloudflare,keycloak,keycloak-operator,cluster-autoscaler,traefik}`. Copy `root.hcl`, `stacks/`, `config/` to scratchpad `reference/k8s/` first.
- Create: `k8s-installs/modules/cluster/{variables.tf,main.tf,outputs.tf,versions.tf,README.md,tests/cluster.tftest.hcl,tests/fixtures/*}`
- Create: `k8s-installs/modules/_boilerplate/README.md` (the four standard files, as text to copy; not a module)
- Modify: `infrastructure/modules/core-platform/outputs.tf` (add `cluster_certificate_authority_data` to each `clusters` entry), its tests
- Modify: `k8s-installs/.gitignore` (drop Terragrunt lines, keep `.terraform/`, lock, state, plans)

**Interfaces:**
- Produces `module "cluster"` (`source = "../cluster"`):
  - inputs: `state = object({ bucket = string, region = string, kms_key_id = optional(string) })`, `env_id = string`, `region = string`, `cluster = string`, `dns_zone = optional(string, "zone-1")`
  - outputs: `cluster_name`, `cluster_endpoint`, `cluster_ca_data` (base64), `cluster_kms_key_arn`, `vpc_id`, `node_security_group_id`, `karpenter` (core-platform's object or null), `dns` (`{public_zone_id, public_zone_name, internal_zone_id, internal_zone_name}` or null when the env has no dns state or zone), `token` (sensitive, from `aws_eks_cluster_auth`)
  - reads `<env_id>/<region>/core-platform/terraform.tfstate` and `<env_id>/global/dns/terraform.tfstate` (dns via `try`, optional)
- Produces boilerplate every component copies (`_context.tf`, `providers.tf`, `backend.tf`, `versions.tf`):
  - `variable "config_file"`, `variable "pipeline_user"`; `module "context"` from `../../../infrastructure/modules/context` with `resource_set = "<component>"`; `module "cluster"` fed from `module.context.state`, `module.context.env_id`, `module.context.region`, `module.context.config.cluster`, `try(module.context.config.dns_zone, "zone-1")`
  - locals: `environment = module.context.env_id`, `region`, `account_id`, `cluster_key = module.context.config.cluster`, `instance = try(regex("^[^.]+\\.(.+)\\.yaml$", basename(var.config_file))[0], null)`, `name_prefix = join("-", compact([module.context.name_prefix, local.cluster_key, local.instance]))`, `cluster_name = module.cluster.cluster_name`
  - providers: `aws` (region, `allowed_account_ids`, `default_tags` from context, plus `Cluster` and `Instance` when set); `helm` (`kubernetes = { host, cluster_ca_certificate = base64decode(...), token }`); `kubernetes` (same three)

- [ ] **Step 1: Copy the old repo's reference files to scratchpad, then delete the files listed above.** Expected: `ls k8s-installs` shows `docs modules README.md .gitignore .claude`.

- [ ] **Step 2: Write `modules/cluster/tests/cluster.tftest.hcl`** (mock aws; `override_data` on the two remote states) with runs:
  - `finds_cluster`: `output.cluster_name == "research-sandbox-euw1-1-eks"`, `output.vpc_id == "vpc-123"`, `output.dns.public_zone_name == "sandbox.research.example.com"`
  - `unknown_cluster_rejected`: `cluster = "9"` → `expect_failures = [terraform_data.validation]`
  - `missing_core_platform_rejected`: core-platform outputs `{}` → `expect_failures = [terraform_data.validation]`
  - `dns_optional`: dns outputs `{}` → `output.dns == null`, plan succeeds
  - `name_prefix_includes_cluster` lives in Task 3's first module (boilerplate is exercised there).

- [ ] **Step 3: Run** `cd k8s-installs/modules/cluster && $TF init -backend=false && $TF test`. Expected: FAIL (no module).

- [ ] **Step 4: Implement `modules/cluster`.** Precondition on `terraform_data.validation`: cluster key present in `clusters`, message `core-platform state for <env_id>/<region> has no cluster "<cluster>"`. Unknown/missing cluster resolves to placeholder name `"cluster-missing"` so `aws_eks_cluster_auth` never sees null.

- [ ] **Step 5: Add `cluster_certificate_authority_data = module.eks[name].cluster_certificate_authority_data` to core-platform's `clusters`;** extend `core_platform.tftest.hcl` `cluster_in_selected_vpc` with `output.clusters["1"].cluster_certificate_authority_data != null`. Run core-platform tests: 7 passed.

- [ ] **Step 6: Run cluster tests.** Expected: 4 passed. Write `modules/_boilerplate/README.md` with the four files verbatim.

- [ ] **Step 7: Sweep** `grep -rniE 'eeze|tain-|polaris|terragrunt|gitlab|[0-9]{12}' k8s-installs --exclude-dir=docs` → only hits in modules still to be converted (listed in the ledger). Commit (on hold).

### Task 2: One workflow for both layers

**Files:**
- Modify: `.github/workflows/terraform.yml`
- Modify: `backstage/phoenix/templates/environment/template.yaml` (`targetPath` gains `infrastructure/`)
- Modify: scratchpad `check_generated.sh` (repo-root-relative paths, k8s units)
- Modify: `infrastructure/README.md`, `k8s-installs/README.md` (rewrite: what it is, layout, unit YAML, how to add a component)

**Interfaces:**
- `config_file` input is repo-root-relative (`infrastructure/environments/...` or `k8s-installs/environments/...`).
- `changes` job runs for both events and outputs `units = [{config_file, runner}]` where `runner` is `"ubuntu-latest"` or `["self-hosted","phoenix-mgmt"]` (JSON); `unit` job: `runs-on: ${{ fromJSON(matrix.unit.runner) }}`.
- `module-tests` matrix entries are `<project>/modules/<name>`.
- "Read unit" outputs (both projects): `project`, `resource_set`, `module_ref`, `role_arn`, `aws_region`, `state_bucket`, `state_region`, `state_kms_key_id`, `state_key`. k8s: `state_key=<env_id>/<region>/k8s/<cluster>/<component>[.<instance>]/terraform.tfstate`; checks `.cluster` in YAML equals the path's cluster; refuses module `cluster` and `_boilerplate`.

- [ ] **Step 1: Write the path-check cases** (scratchpad `test_read_unit.sh`, runs the workflow's "Read unit" script extracted with `yq`): 6 existing infrastructure examples pass with unchanged state keys; `k8s-installs/.../1/vllm.llama-3-8b.yaml` → `state_key=research-sandbox-jdoe/eu-west-1/k8s/1/vllm.llama-3-8b/terraform.tfstate`; cluster mismatch → error; `modules/cluster` as component → error; apply off `main` → error.
- [ ] **Step 2: Run it.** Expected: FAIL on the k8s cases.
- [ ] **Step 3: Implement the workflow changes;** remove the `defaults.run.working-directory`; module checkout path `src/<project>/modules/<rs>`.
- [ ] **Step 4: Run** `test_read_unit.sh` → all pass; `$ACTIONLINT .github/workflows/terraform.yml` → clean; Backstage dry-run (`dryrun.mjs`) → files under `infrastructure/environments/...`, `check_generated.sh` → all ok. Commit (on hold).

### Task 3: Baseline I — cluster-config, reloader, kyverno, falco

**Files:** for each module: add the four boilerplate files; rewrite `locals.tf` header; remove on-prem branches; `tests/<module>.tftest.hcl` + `tests/fixtures/<module>.yaml`; README "Spec" section.

**Conversion recipe (used by Tasks 3–9):**
1. `config = merge(local.defaults, module.context.spec)`; `defaults.enabled = true`; drop `module_version`, `environment_config`, `scope_config`, `resource_sets`, `is_onprem`, ownership-tag plumbing (context tags cover it).
2. Replace generated names: `base_name_prefix`→`local.name_prefix`; `eks_cluster_name`→`local.cluster_name`; `cluster_kms_key_arn`→`module.cluster.cluster_kms_key_arn`; `dns_*`→`module.cluster.dns.*`; `data.aws_eks_cluster.this.*`→`module.cluster.*`; `var.environment`→`local.environment`; `var.scope`/`var.region`→`local.region`; `var.account_id`→`local.account_id`.
3. Every test file: `mock_provider` aws, helm, kubernetes; `override_data` for `module.cluster.data.terraform_remote_state.core_platform` / `.dns`; runs `plans_with_defaults` (release name, namespace, pinned chart version) and `disabled_plans_nothing` (`enabled: false` → 0 releases).

- [ ] **Step 1: Write tests** for the four modules; cluster-config also gets `name_prefix_includes_cluster` (`local.name_prefix == "research-sandbox-euw1-1"`) and `personal_prefix` (`"research-sandbox-jdoe-euw1-1"`); falco: `three_releases_in_order` (operator → falco → rules, `depends_on` chain).
- [ ] **Step 2: Run** → FAIL (modules still read `var.config_path`).
- [ ] **Step 3: Convert** per the recipe.
- [ ] **Step 4: Run all four** → pass; fmt clean. Commit (on hold).

### Task 4: Baseline II — external-secrets, grafana-stack (new)

**Files:** convert `modules/external-secrets` (EKS only: delete Roles Anywhere / signing-helper / on-prem files); create `modules/grafana-stack/{main.tf,locals.tf,outputs.tf,manifests/*.yaml.tpl,README.md,tests/…}`.

**Interfaces:**
- grafana-stack reads the observability unit's state `<group>-<observability.environment|shared>/<region>/observability/terraform.tfstate` for `bucket_name` and `writer_role_arns` (same lookup core-platform uses); releases in namespace `monitoring`: `mimir` (mimir-distributed), `loki`, `tempo`, `alloy`, `grafana`; service accounts `mimir`, `loki`, `tempo`, `grafana`; S3 prefixes `<signal>/<cluster_name>/`.
- Outputs: `grafana_service`, `namespaces`.

- [ ] **Step 1: Tests:** external-secrets `plans_with_defaults`, `pod_identity_scoped` (role allows only `secretsmanager:GetSecretValue`/`ssm:GetParameter*` on `<name_prefix>` paths + optional KMS); grafana-stack `plans_with_defaults` (5 releases), `bindings_match_core_platform` (namespace `monitoring`, SA names exactly `mimir`,`loki`,`tempo`), `bucket_from_observability_state` (rendered values contain the bucket and `mimir/research-sandbox-euw1-1-eks/` prefix), `missing_observability_rejected`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → pass. Commit (on hold).

### Task 5: Compute — karpenter, karpenter-nodepool, nvidia-gpu-operator (new)

**Interfaces:**
- `karpenter`: Helm chart into `module.cluster.karpenter.namespace` with `serviceAccount.name = module.cluster.karpenter.service_account`, `settings.clusterName`, `settings.interruptionQueue = module.cluster.karpenter.queue_name`; plus default `EC2NodeClass`/`NodePool` (`default`, on-demand + spot, non-GPU families). Precondition: `module.cluster.karpenter != null` ("set clusters.<key>.karpenter.enabled in core-platform").
- `karpenter-nodepool` (instance = GPU type): spec `{ instance_families = [..], gpu_count_max, limits }` filled by Backstage from the `phoenix-gpu` entity; NodePool `gpu-<instance>` with taint `nvidia.com/gpu=true:NoSchedule`, label `phoenix/gpu=<instance>`; EC2NodeClass AMI family `AL2023` NVIDIA variant, node role `module.cluster.karpenter.node_role_name`.
- `nvidia-gpu-operator`: gpu-operator chart (driver disabled — AL2023 NVIDIA AMI ships drivers; toolkit + device plugin + DCGM exporter on), namespace `gpu-operator`; DCGM ServiceMonitor scraped by Alloy.

- [ ] **Step 1: Tests:** karpenter `plans_with_defaults`, `requires_core_platform_karpenter`; nodepool `gpu_pool_from_instance` (NodePool name `gpu-l4`, taint present, families `["g6"]`), `two_gpu_types_do_not_collide`; gpu-operator `driver_disabled_dcgm_on`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** (manifests via `kubernetes_manifest`; CRDs come from the karpenter chart, so nodepool waits on karpenter's state by order, not in-plan). **Step 4: Run** → pass. Commit (on hold).

### Task 6: Service set — aws-load-balancer-controller, istio, external-dns, cert-manager

**Interfaces:** istio provides Gateway API CRDs + `istiod` + one `Gateway` per cluster (`internal` and `external` listeners) and enables the Inference Extension CRDs (`InferencePool`) — Task 9 consumes `gateway_name`/`gateway_namespace` outputs via remote state `<env_id>/<region>/k8s/<cluster>/istio`. cert-manager EKS only (delete on-prem branches); `ClusterIssuer`s use `module.cluster.dns`. external-dns zones default to the cluster's own zone.

- [ ] **Step 1: Tests:** each `plans_with_defaults` + `disabled_plans_nothing`; external-dns `zone_scoped_iam` (policy resources only the cluster zone IDs), `personal_env_names_fit` (IAM role name ≤ 64 for `research-sandbox-jdoe` env); istio `gateway_and_inference_crds`; cert-manager `issuers_use_cluster_zone`, `no_dns_rejected` (no dns state → clear error).
- [ ] **Step 2–4:** FAIL → convert → pass. Commit (on hold).

### Task 7: Data — cloudnative-pg(+cluster), valkey-redis(+cluster), strimzi-kafka(+cluster)

**Interfaces:** operators are singletons; `*-cluster` modules are instance-named (`cloudnative-pg-cluster.app.yaml`) and drop their internal multi-cluster maps — one instance = one database cluster, named `<instance>`; secrets published through `../../../infrastructure/modules/credentials` (`publish` binding `in-cluster`). Versions/sizes are module defaults only.

- [ ] **Step 1: Tests:** operators `plans_with_defaults`; each cluster module `plans_with_defaults` (one CR, name = instance), `two_instances_do_not_collide` (two fixture files → different CR names, secret paths, IAM names), `missing_instance_rejected` (file without instance → clear error).
- [ ] **Step 2–4:** FAIL → convert → pass. Commit (on hold).

### Task 8: Delivery — argo-cd, kargo

**Interfaces:**
- argo-cd: `spec.repo_url` (GitHub HTTPS/SSH) — required; repo credential via external-secrets from `<name_prefix>/argo-cd/repo`; OCI Helm charts from the group ECR pull-through (`<account>.dkr.ecr.<region>.amazonaws.com/<cache_prefix>/*`, default prefix `artifactory`), replacing `shared_account_id`.
- kargo: `spec.management_cluster` (default `"1"`); `mode = cluster_key == management_cluster ? "management" : "spoke"`; spoke reads `<env_id>/<region>/k8s/<management_cluster>/kargo` state for the kubeconfig secret ARN. Delete `_kargo_management` logic and `terraform_remote_state.management_core_platform`.

- [ ] **Step 1: Tests:** argo-cd `plans_with_defaults`, `repo_url_required`, `ecr_pull_through_scoped`; kargo `management_mode_on_cluster_1`, `spoke_mode_on_cluster_2`, `spoke_without_management_rejected`.
- [ ] **Step 2–4:** FAIL → convert → pass. Commit (on hold).

### Task 9: Model serving — vllm, langfuse (new)

**Interfaces:**
- `vllm` (instance = model slug): spec `{ model = "<hf id>", gpu = "<gpu type>", replicas = 1 }` (filled from the `phoenix-model` entity); Deployment + Service in namespace `models`, `nodeSelector phoenix/gpu=<gpu>`, toleration `nvidia.com/gpu`; `InferencePool` + `HTTPRoute` on the istio gateway (from istio state); Hugging Face token from external-secrets `<name_prefix>/hf-token`; images through ECR pull-through. Precondition: istio state present; gpu nodepool state `karpenter-nodepool.<gpu>` present.
- `langfuse`: chart in namespace `langfuse`, service account `langfuse`; bundled ClickHouse/Redis/Postgres; S3 blob storage = observability bucket, prefix `langfuse/<cluster_name>/`.

- [ ] **Step 1: Tests:** vllm `plans_with_defaults`, `two_models_do_not_collide`, `missing_gpu_pool_rejected`, `routes_through_inference_pool`; langfuse `plans_with_defaults`, `langfuse_binding_matches` (namespace/SA exactly `langfuse`), `blobs_in_observability_bucket`.
- [ ] **Step 2–4:** FAIL → implement → pass. Commit (on hold).

### Task 10: Backstage — catalog, workload template, examples

**Files:**
- Create: `backstage/phoenix/catalog/{workloads,databases,gpus,models,components}.yaml`
- Create: `backstage/phoenix/templates/workload/{template.yaml,skeleton/…}`
- Modify: `backstage/phoenix/templates/environment/template.yaml` (register a `phoenix-cluster` Resource per core-platform cluster; drop the `gpu` toggle and the managed GPU node group, per spec call 3)
- Modify: `backstage/app-config.docker.yaml` (catalog locations)
- Create: `k8s-installs/environments/sandbox/research-sandbox-jdoe/eu-west-1/1/*.yaml` examples (one per component used by model-serving + postgres + l4)

**Interfaces:**
- Entities: `resource:default/workload-<name>` (`spec.type: phoenix-workload`), `database-<name>`, `gpu-<name>` (annotations `phoenix/instance-families`, `phoenix/gpu-count-max`), `model-<slug>` (annotations `phoenix/hf-id`, `phoenix/min-gpu`), `component-<module>` (`spec.dependsOn` for prerequisites, annotation `phoenix/instanced: "true"` where applicable). Baseline = `resource:default/workload-baseline`, always included.
- Template output: one file per resolved component under `k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/`, plus an `install-order` text output (topological order) for the orchestrator.

- [ ] **Step 1: Extend `dryrun.mjs`** with cases: model-serving + l4 + llama; service + postgres; service + kafka. Expected files listed per case; run → FAIL (template missing).
- [ ] **Step 2: Write catalog entities and the template** (component set = baseline ∪ chosen options closed over `dependsOn`; order = topological; implemented with Nunjucks over `catalog:fetch` results — if the closure can't be done in Nunjucks, emit the set and leave ordering to the orchestrator, ledger the ruling).
- [ ] **Step 3: Run** dry-run → expected files; `check_generated.sh` → every generated k8s unit passes path check + plan with its module's mocks.
- [ ] **Step 4: Examples + READMEs** (`k8s-installs/README.md` final, `backstage/README.md` workload section); full regression: all Layer 2 tests (44+) + all k8s module tests; sweep clean. Commit (on hold).
