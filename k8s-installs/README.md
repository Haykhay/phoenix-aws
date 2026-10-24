# k8s-installs

What runs **inside** each Phoenix EKS cluster (Layer 3). People ask Backstage
for a workload type, a database type, a GPU type and a model; Backstage works
out the components that needs, writes one YAML per component into this repo,
and runs them in order through the shared GitHub workflow. Plain Terraform, no
Terragrunt, no helper scripts. Versions and sizes are decided here, never in
the form.

Design: [`docs/superpowers/specs/2026-10-24-k8s-installs-backstage-design.md`](docs/superpowers/specs/2026-10-24-k8s-installs-backstage-design.md)
· Plan: [`docs/superpowers/plans/2026-10-24-k8s-installs-backstage.md`](docs/superpowers/plans/2026-10-24-k8s-installs-backstage.md)

## Layout

```text
environments/<tier>/<env_id>/<region>/<cluster>/<component>[.<instance>].yaml   one unit per file, written by Backstage
modules/<component>/        one plain Terraform root per component
modules/cluster/            shared: finds the unit's EKS cluster in infrastructure's state
modules/_boilerplate/       the four files every component starts from (documentation, not a module)
```

- `<cluster>`: the key in core-platform's `clusters` (`"1"`).
- `<instance>`: for components a cluster can hold several of — one per model
  (`vllm.llama-3-1-8b.yaml`), per database (`cloudnative-pg-cluster.app.yaml`),
  per GPU type (`karpenter-nodepool.l4.yaml`). Lowercase, digits, hyphens.
- State: `<env_id>/<region>/k8s/<cluster>/<component>[.<instance>]/terraform.tfstate`,
  in the account's state bucket.

Working example — model serving on an L4 with Llama 3.1 8B and a Postgres,
exactly as the Backstage workload form writes it:
[`environments/sandbox/vision-sandbox-jdoe/eu-west-1/1/`](environments/sandbox/vision-sandbox-jdoe/eu-west-1/1/).

## What gets installed

| Choice in the form | Components |
|---|---|
| (every cluster, not shown) | cluster-config, karpenter, kyverno, falco, reloader, external-secrets, grafana-stack |
| **Service** | cert-manager, aws-load-balancer-controller, istio, external-dns, argo-cd, kargo |
| **Model serving** | the service set + nvidia-gpu-operator, vllm.&lt;model&gt;, clickhouse-operator, langfuse |
| **GPU type** | karpenter-nodepool.&lt;gpu&gt;, nvidia-gpu-operator |
| **Postgres / Redis / Kafka** | cloudnative-pg + cloudnative-pg-cluster.&lt;name&gt; / valkey-redis + valkey-redis-cluster.&lt;name&gt; / strimzi-kafka + strimzi-kafka-cluster.&lt;name&gt; (sandbox; stage and above use infrastructure's managed data-*) |

The sets are Backstage catalog data (`backstage/phoenix/catalog/`); so are the
components' prerequisites, which give the install order (teardown is the
reverse):

```text
cluster-config > karpenter > kyverno > falco > reloader > external-secrets > grafana-stack
> cert-manager > aws-load-balancer-controller > external-dns > istio > argo-cd > kargo
> nvidia-gpu-operator > karpenter-nodepool > vllm > clickhouse-operator > langfuse
> cloudnative-pg > cloudnative-pg-cluster > valkey-redis > valkey-redis-cluster > strimzi-kafka > strimzi-kafka-cluster
```

Each module's README has its spec, versions and what it needs first.

## A unit's YAML

Same identity block as infrastructure, plus `cluster`:

```yaml
# environments/sandbox/vision-sandbox-jdoe/eu-west-1/1/vllm.llama-3-1-8b.yaml
organisation: acme
group: vision
environment: sandbox
requester: jdoe
tier: sandbox
region: eu-west-1
cluster: "1"
account_id: "111111111111"
module_ref: main
state:
  bucket: acme-tfstate-111111111111
  region: eu-west-1
tags:
  owner.team: vision
  Reason: "jdoe vLLM model evaluation"
  LongLive: false
spec:
  model: "meta-llama/Llama-3.1-8B-Instruct"
  gpu: "l4"
```

## How it runs

The workflow (`../.github/workflows/terraform.yml`, shared with
infrastructure) checks the path against the YAML (tier, env_id, region,
cluster, a known component, a valid instance), assumes
`arn:aws:iam::<account_id>:role/Terraform-Role`, and runs the unit on the
**`phoenix-mgmt` self-hosted runner** in the management VPC — EKS endpoints
are private, and the runner reaches every cluster in the IPAM range
(networking is designed separately; each cluster allows the runner range
through core-platform's `ci_runners_cidr`). Module tests run on GitHub-hosted
runners with mock providers; any change to infrastructure's modules re-runs
every k8s module's tests too.

Every component reaches its cluster through `modules/cluster` (endpoint, CA,
token, subnets, security groups, Karpenter facts from core-platform's state;
DNS zones from dns) and reuses infrastructure's `modules/context` for naming,
tags and checks. A unit planned before what it needs (core-platform, dns,
istio, its GPU pool, the observability unit, a Kargo management cluster)
fails with a message saying what to apply first.

**The `phoenix-mgmt` runner** can reach every cluster, so:

- register it in a **runner group restricted to this repository and to
  `.github/workflows/terraform.yml` at `refs/heads/main`** ("selected
  workflows"). A pull request from a fork runs its own copy of the workflow;
  the workflow already skips k8s units for forks, but only the runner group
  stops an edited workflow from using the runner;
- in the repository's Actions settings, require approval before workflows run
  for outside contributors;
- install `aws` CLI (the providers fetch EKS tokens with `aws eks get-token`),
  `yq` and `jq`; Terraform comes from the workflow.

**Secrets** all live under `<organisation>/<env_id>/` in Secrets Manager — the
only prefix external-secrets may read.

**Images** come from upstream registries for now; routing every image through
the group account's ECR pull-through cache is deferred to the tooling account
work (see the design's Deferred section).

## Adding a component

1. `modules/<component>/` with the four files from
   [`modules/_boilerplate`](modules/_boilerplate/README.md) (set `resource_set`),
   plus its resources reading `module.context.spec`; pin chart versions in
   `locals.defaults` (released at least two weeks earlier).
2. `tests/<component>.tftest.hcl` with `plans_with_defaults` and
   `disabled_plans_nothing` at least (mock aws, helm, kubernetes).
3. A `component-<name>` entity in `backstage/phoenix/catalog/components.yaml`
   with its prerequisites, and the component added to every option that needs
   it (options list their full set).
