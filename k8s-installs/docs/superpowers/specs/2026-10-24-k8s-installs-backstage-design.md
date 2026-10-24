# k8s-installs: workload-driven cluster components from Backstage

Status: draft for review · 2026-10-24
Companion to `infrastructure/docs/superpowers/specs/2026-10-23-backstage-driven-terraform-design.md`
(Layer 2). This is Layer 3: what runs **inside** each EKS cluster.

## Intent

A developer or researcher asks Backstage for what they need, in their own terms:
**what kind of workload**, **what kind of database**, **what kind of GPU node**.
They never pick Helm charts, versions or sizes. The platform team decides which
components each choice needs, at which version and size. Backstage installs
them into the right cluster in the right order and tells the requester when it
is done.

Owner's words, kept as the yardstick:
- "the user do not need to know what each aspect does.. they just specify what
  is needed and then it deploys into the cluster and let them know when it is done"
- "all they can select is what type of database … we define which db version"
- "everyone selects what type of workload and we decide which [components]
  based on their selection"
- "allow room to grow if we will need to serve different types of workload"

## Goals

1. Same model as Layer 2: Backstage writes one YAML per **component** per
   **cluster**; the one GitHub workflow runs plain Terraform for it; Backstage
   orders the runs and reports completion. No Terragrunt, no JSON config, no
   GitLab, no helper scripts.
2. Users choose from what is offered; the platform pins everything else.
3. New workload types, database types, GPU types and models are added as
   **data** (catalog entries plus, at most, a new component module) — never by
   editing the form or the workflow.
4. Every component plans and tests offline (`terraform test`, mock providers).

## Non-goals (this iteration)

- Networking (IPAM pools, TGW, routes, runner VPC) — designed later. This design
  only states what it needs from networking (see Constraints).
- Building the Backstage orchestrator (dispatch-in-order, wait, notify). It is
  shared with Layer 2 and gets its own design; this one defines the data it
  works from.
- Cross-environment promotion (sandbox → stage → prod). Argo CD and Kargo are
  installed now, per environment; promotion across environments gets its own design.
- On-prem clusters.

## Anti-goals

- A form that exposes chart names, versions, replica counts or sizes.
- A per-workload-type `if` buried in a template or the workflow: adding a type
  must not need a code change outside its own catalog entry and module(s).
- A cluster component that can reach a zone, bucket prefix or secret path that
  belongs to another cluster (existing scoping rules stay).

## Constraints

- **Runner:** k8s units run on a self-hosted GitHub runner in the **management
  VPC**, beside Backstage, label `phoenix-mgmt`. EKS endpoints stay private.
  Each cluster's API must accept the management VPC range — core-platform
  already has `ci_runners_cidr` for exactly this; account vending / Backstage
  sets it. Reachability (TGW, routes) is the networking design's job.
- AWS units (Layer 2) keep GitHub-hosted runners.
- Roles by name: the runner assumes `arn:aws:iam::<account_id>:role/Terraform-Role`
  exactly like Layer 2.
- Same repo (`AWS/`), same state bucket per account, same `module_ref` rule
  (`main` for sandbox, a release tag for stage/UAT/prod).
- Terraform ≥ 1.15; upstream charts/modules from their public sources.

## Decided (by the owner)

- Form choices: workload type, database type, GPU node type (none or a GPU kind).
  Platform defines versions, sizes and everything else.
- First iteration workload types: **model serving** (vLLM + its gateway) and
  **normal service** (load balancer, DNS, certificates…).
- Backstage owns the flow and tells the requester when it is done.
- Runner in the management VPC, reaching all clusters in the IPAM range.
- Dropped: groundcover, on-prem / KAS / Roles Anywhere paths,
  `cert-manager-aws-pca-issuer`, `k8s-image-swapper` (ECR pull-through covers it),
  `cloudflare`, `keycloak` and `keycloak-operator` (Entra covers identity).
- Added: Karpenter controller, NVIDIA GPU operator, Grafana stack, Langfuse, vLLM.
- Argo CD, Kargo and Falco are in this iteration.

## Design

### 1. Three layers of choice, all catalog data

The form asks three things. Each answer is a catalog entity, so the form lists
whatever exists and new options appear without touching the template.

| Form question | Catalog entity (`kind: Resource`) | Example entries |
|---|---|---|
| Workload type | `spec.type: phoenix-workload` | `model-serving`, `service` |
| Database type | `spec.type: phoenix-database` | `postgres`, `redis`, `kafka` |
| GPU node type | `spec.type: phoenix-gpu` | `none`, `l4` (g6), `a10g` (g5), `l40s` (g6e) |
| Model (model serving only) | `spec.type: phoenix-model` | curated Hugging Face IDs, each with its minimum GPU |

Each option entity lists the **components** it needs in `spec.dependsOn`
(`resource:default/component-vllm`, …). Components are catalog entities too
(`spec.type: phoenix-component`), and they list their own prerequisites in
`spec.dependsOn` (`component-cloudnative-pg-cluster` → `component-cloudnative-pg`).

So the install set for a request = the always-on baseline ∪ the chosen options'
components, closed over `dependsOn`; the install **order** = a topological sort
of that graph; teardown = the reverse. The orchestrator computes both from the
catalog. Adding a workload type = one `phoenix-workload` entity (+ any new
component module and its entity).

Option entities also carry the platform's pinned values as annotations
(e.g. `phoenix/gpu-instance-families: g6`, `phoenix/model-min-gpu: l4`), so the
template copies them into the unit YAML without hard-coding them.

### 2. Component sets (first iteration)

| Set | Components |
|---|---|
| **Baseline** (every cluster, never shown) | `cluster-config` (gp3), `karpenter` (controller + default NodePool), `kyverno`, `falco`, `reloader`, `external-secrets`, `grafana-stack` |
| **Delivery** (with every workload type) | `argo-cd`, `kargo` |
| **service** | `aws-load-balancer-controller`, `istio` (Gateway API), `external-dns`, `cert-manager` |
| **model-serving** | `vllm`, `istio` (Gateway API + Inference Extension), `nvidia-gpu-operator`, `langfuse` |
| **GPU type ≠ none** | `karpenter-nodepool.<gpu>` (one NodePool + EC2NodeClass per GPU type) + `nvidia-gpu-operator` |
| **postgres** | sandbox: `cloudnative-pg` + `cloudnative-pg-cluster`; stage+: Layer 2 `data-rds` |
| **redis** | sandbox: `valkey-redis` + `valkey-redis-cluster`; stage+: Layer 2 `data-elasticache` |
| **kafka** | sandbox: `strimzi-kafka` + `strimzi-kafka-cluster`; stage+: Layer 2 `data-msk` |

Module fate in this repo:

| Fate | Modules |
|---|---|
| Keep, convert | cluster-config, aws-load-balancer-controller, external-dns, istio, cert-manager (EKS only), external-secrets (EKS only), kyverno, falco, reloader, cloudnative-pg(+cluster), valkey-redis(+cluster), strimzi-kafka(+cluster), argo-cd, kargo |
| New | karpenter, karpenter-nodepool, nvidia-gpu-operator, grafana-stack, langfuse, vllm |
| Remove | groundcover-sensor, cert-manager-aws-pca-issuer, k8s-image-swapper, cloudflare, keycloak, keycloak-operator, cluster-autoscaler, traefik |

**Kargo topology:** one Kargo per environment. The environment's management
cluster (`spec.management_cluster`, default `"1"`) runs the full Kargo; its
other clusters run spoke controllers that read the management cluster's state
(`<env_id>/<region>/k8s/<management_cluster>/kargo`). This replaces the
hand-kept `_kargo_management` map.

**Argo CD:** one per cluster; the Git repository it watches is a GitHub URL in
`spec`; Helm charts are pulled through the group's ECR pull-through cache
(replacing the old shared-account `helm-charts/` repository).

### 3. Units, paths, state

```text
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/<component>[.<instance>].yaml
state key: <env_id>/<region>/k8s/<cluster>/<component>[.<instance>]/terraform.tfstate
```

`<cluster>` is the core-platform `clusters` key (`"1"`). The module is the file
name up to the first dot. `<instance>` exists for components a cluster can hold
several of — one per model (`vllm.llama-3-8b.yaml`), per database
(`cloudnative-pg-cluster.app.yaml`), per GPU type
(`karpenter-nodepool.l4.yaml`); singletons (`karpenter.yaml`) have none.
Instances are what keep "add another one" a new file rather than an edit to a
shared one. The YAML carries the
same identity block as Layer 2 (organisation, group, environment, requester,
tier, region, account_id, module_ref, state, tags) plus `cluster: "1"` and the
component's `spec`. Path and YAML must agree, as in Layer 2.

### 4. Module shape

Each component is a plain Terraform root, like Layer 2:

- `_context.tf` uses `../../../infrastructure/modules/context` (one source
  of naming, tags, state keys and identifier rules across both layers).
- `modules/cluster` (new, shared, this repo): reads core-platform and dns remote
  state for this env, selects `clusters[<cluster>]`, and outputs cluster name,
  endpoint, CA, OIDC/pod-identity facts, VPC, and the cluster's DNS zone.
  Missing core-platform state fails the plan with a clear message (same
  precondition pattern as Layer 2).
- `providers.tf`: `aws` (allowed_account_ids, default_tags), `helm` and
  `kubernetes` from `modules/cluster` with an `aws_eks_cluster_auth` token —
  no kubeconfig, no `aws` CLI exec.
- Pod Identity associations in the component that needs AWS access (existing
  pattern), names from `module.context.name_prefix`.
- `tests/*.tftest.hcl` with `mock_provider` for aws, helm, kubernetes.

The observability bindings already created by core-platform (`monitoring/mimir`,
`monitoring/loki`, `monitoring/tempo`, `langfuse/langfuse`, grafana CloudWatch)
are what `grafana-stack` and `langfuse` deploy into: namespaces and service
account names must match.

### 5. Workflow

The one `.github/workflows/terraform.yml` serves both layers:

- `config_file` becomes repo-root-relative: `infrastructure/environments/…`
  or `k8s-installs/environments/…`. The first segment picks the project and
  its path rule; the stage-1 Backstage template's `targetPath` gains the
  `infrastructure/` prefix.
- `runs-on`: GitHub-hosted for `infrastructure`, `[self-hosted, phoenix-mgmt]`
  for `k8s-installs`.
- PRs: module tests run on GitHub-hosted runners (mocks, no cluster access).

### 6. Backstage

- New template **Phoenix workload** (or a second page on the environment
  template — builder's call): pick environment + cluster (from catalog, the
  env's core-platform clusters), workload type, database type, GPU type, model.
- It writes the unit YAMLs for every component in the resolved set (§1) that
  the cluster does not already have; instances (§3) are always new files.
- Clusters must be pickable: the environment template registers a
  `phoenix-cluster` Resource per core-platform cluster (builder's call how).
- The orchestrator (separate design) applies them in order and sends a
  Backstage notification to the requester on success or failure.
- Removing a workload: destroy the components no other remaining option needs,
  in reverse order.

## Deferred (owner decision, 2026-10-24)

- **Image routing:** every image in a cluster will be rewritten cluster-wide
  (e.g. a Kyverno mutate policy) to the group account's ECR pull-through cache,
  fed from the central ECR hub and the company Artifactory. Built together
  with the tooling account and its assets. Until then components pull their
  upstream images; `spec.image_registry` exists on cloudnative-pg only.

## Left to the builder

- Chart versions (latest stable, ≥ 2 weeks old) and the exact values per chart.
- Splitting `grafana-stack` into several releases inside one module vs several
  modules (one unit is preferred unless state size argues otherwise).
- How `modules/cluster` names its outputs.

## My calls (owner to confirm)

1. Databases: in-cluster operators for sandbox (cheap, die with the weekend
   teardown); managed AWS services (Layer 2) for stage/UAT/prod.
2. One Gateway API implementation, **Istio**, for both services and model
   serving (it supports the Inference Extension's `InferencePool`); `traefik`
   removed rather than running two gateways.
3. GPU nodes come from Karpenter NodePools (per GPU type) rather than managed
   GPU node groups; core-platform keeps only the system node group. The stage-1
   template's `gpu` toggle moves to this flow.
4. Models are a curated catalog list, not free text — consistent with "they
   select what is available".
5. Langfuse uses its chart's bundled ClickHouse/Redis/Postgres in sandbox, with
   blobs in the group's observability bucket (`langfuse/` prefix).
6. Kargo management cluster = the environment's cluster `"1"` unless set; promotion
   across environments waits for the promotion design.
7. Falco in the baseline (every cluster).
