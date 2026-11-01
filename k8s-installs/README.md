# k8s-installs

What runs **inside** each Phoenix EKS cluster (Layer 3). People ask Backstage
for a workload type, a database type, a GPU type and a model; Backstage works
out the components that needs, writes one YAML per component into this repo,
and runs them in order through the shared GitHub workflow. Plain Terraform, no
Terragrunt, no helper scripts. Versions and sizes are decided here, never in
the form.

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

## What gets installed

| Choice in the form | Components |
|---|---|
| (every cluster, not shown) | cluster-config, karpenter, kyverno, falco, reloader, external-secrets, grafana-stack |
| **Service** | cert-manager, aws-load-balancer-controller, istio, external-dns, argo-cd, kargo |
| **Model serving** | the service set + aws-fsx-csi-driver, model-weights.&lt;model&gt;, vllm.&lt;model&gt;, clickhouse-operator, langfuse; llm-d when any llm-d option is chosen. Infrastructure first: model-store (once per group and region) and model-cache.&lt;cluster&gt; |
| **GPU type** | karpenter-nodepool.&lt;gpu&gt;, plus nvidia-gpu-operator (NVIDIA) or neuron-device-plugin (Trainium/Inferentia) |
| **Postgres / Redis / Kafka** | cloudnative-pg + cloudnative-pg-cluster.&lt;name&gt; / valkey-redis + valkey-redis-cluster.&lt;name&gt; / strimzi-kafka + strimzi-kafka-cluster.&lt;name&gt; (sandbox; stage and above use infrastructure's managed data-*) |

The sets are Backstage catalog data (the Backstage repository's `phoenix/catalog/`); so are the
components' prerequisites, which give the install order (teardown is the
reverse):

```text
cluster-config > karpenter > kyverno > falco > reloader > external-secrets > grafana-stack
> cert-manager > aws-load-balancer-controller > external-dns > istio > argo-cd > kargo
> nvidia-gpu-operator | neuron-device-plugin > karpenter-nodepool > aws-fsx-csi-driver > model-weights > llm-d > vllm
> clickhouse-operator > langfuse
> cloudnative-pg > cloudnative-pg-cluster > valkey-redis > valkey-redis-cluster > strimzi-kafka > strimzi-kafka-cluster
```

Model serving also needs, from infrastructure, applied before `aws-fsx-csi-driver`:
`model-store` (the group's weights bucket, in `<group>-shared`) and
`model-cache.<cluster>` (FSx for Lustre linked to it). Backstage writes both
with the model; the cache's `LongLive` is the tier's setting from the
environment form.

Each module's README has its spec, versions and what it needs first.

## A unit's YAML

Same identity block as infrastructure, plus `cluster`:

```yaml
# environments/sandbox/research-sandbox-jdoe/eu-west-1/1/vllm.llama-3-1-8b.yaml
organisation: acme
group: research
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
  owner.team: research
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
3. A `component-<name>` entity in the Backstage repository's `phoenix/catalog/components.yaml`
   with its prerequisites, and the component added to every option that needs
   it (options list their full set).
4. A `README.md` saying what it installs and its `spec`, then a **Running it**
   section like every other module's: the infrastructure units and components
   it needs first, what someone must provide, the unit file and state key, how
   to run it, its outputs (every output has a `description`), and what to
   destroy before it.
