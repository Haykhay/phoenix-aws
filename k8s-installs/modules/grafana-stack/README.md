# grafana-stack

Each cluster's own observability stack, in namespace `monitoring`. Part of
every cluster's baseline. History goes to the group's long-lived
observability bucket (infrastructure's `observability` unit in
`<group>-shared`), so it survives weekend teardowns.

| Release | Chart (pinned) | Role | Service account |
|---|---|---|---|
| `mimir` | grafana/mimir-distributed 6.2.1 (Mimir 3.2.1) | metrics; chart-default ingest storage with its own Kafka | `mimir` |
| `loki` | grafana/loki 7.3.0 (Loki 3.6.12), single binary | logs | `loki` |
| `tempo` | grafana-community/tempo 3.1.0, single binary | traces | `tempo` |
| `alloy` | grafana/alloy 1.13.1 | collection: annotated pod metrics → Mimir, all pod logs → Loki, OTLP (4317/4318) → Tempo | `alloy` |
| `grafana` | grafana-community/grafana 13.5.0 | Mimir, Loki, Tempo and CloudWatch data sources | `grafana` |

The service accounts are exactly the ones core-platform binds with Pod
Identity (`monitoring/mimir|loki|tempo|grafana`); renaming one breaks AWS
access silently.

## Where data lands

Every object goes under the writer role's only allowed path,
`<signal prefix><cluster name>/` (prefixes from the observability unit's
`signal_prefixes` output):

| Signal | Path | How |
|---|---|---|
| Mimir | `mimir/<cluster>/` | `storage_prefix: mimir` (alphanumeric only), tenant `no_auth_tenant` = cluster name |
| Loki | `loki-<cluster>/` | `storage_prefix` (no slash allowed), Thanos object store client |
| Tempo | `tempo/<cluster>/` | `prefix` |

Mimir's alertmanager and ruler are off (their state would live outside that
path); alert in Grafana. Usage reporting is off.

## Sending signals

| What | Where |
|---|---|
| Prometheus metrics | annotate the pod `prometheus.io/scrape: "true"`; the GPU operator's DCGM exporter (`app=nvidia-dcgm-exporter`) and Karpenter's controller (`http-metrics` port) are scraped without it. Scrapes keep the exporter's own `namespace`/`pod` labels (`honor_labels`), so kube-state-metrics and DCGM describe the pods they measure |
| Logs | automatic (every pod) |
| Traces | OTLP to `alloy.monitoring.svc:4317` (gRPC) or `:4318` (HTTP) |

## Model serving

With `spec.model_serving` (default `true`) Grafana gets a **Model serving**
folder, and the stack adds `kube-state-metrics` (prometheus-community chart
`8.6.0`, 2026-09-26) for pod start times and Pending reasons. Backstage reads
the dashboards and alerts from Grafana; it never needs Kubernetes access.

| Dashboard | uid | |
|---|---|---|
| Model serving | `phoenix-model-serving` | per model (`request_host`) and per consumer (`x-phoenix-consumer`, tagged on istio's gateway metrics): requests, p95 latency; per model: tokens, time to first token; start time (created → Ready); Pending reasons (kube-state-metrics, Karpenter); GPU and NeuronCore utilisation |
| llm-d vLLM Overview | `llm-d-vllm-overview` | vendored unmodified from llm-d `v0.10.0`, `guides/recipes/observability/grafana/dashboards/` |
| Inference Gateway | `llm-d-inference-gateway` | same source |
| llm-d Performance | `llm-d-performance-kv-cache` | same source |
| llm-d Failure & Saturation | `llm-d-failure-saturation` | same source |

Alerts (folder Model serving, labelled with the environment's `owner.team` and
the cluster), one per anti-goal:

| Alert | Fires when |
|---|---|
| `ModelStartSlow` | a model pod has been created but not Ready for over 1800 s |
| `AcceleratorIdle` | a model's GPUs (DCGM) or a node's NeuronCores average under 5% for 30 minutes |
| `ModelPendingCapacity` | a model pod has been unschedulable for over 15 minutes: Karpenter couldn't get the capacity (see karpenter-nodepool's "What you can achieve") |

Updating llm-d's dashboards: copy the new release's files over
`manifests/dashboards/llm-d/` and change the version here.

## Spec

| `spec` | Default | |
|---|---|---|
| `observability_environment` | `shared` | the group environment holding the observability unit |
| `chart_versions` | as above | platform-pinned, per release |
| `model_serving` | `true` | model-serving dashboards, alerts and kube-state-metrics (below) |
| `enabled` | `true` | |

The plan fails clearly if the group's observability unit has not been applied.

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-platform` for the environment and region: the cluster this unit targets (the plan fails without it)
- `observability` in the group's shared environment (`<group>-shared`, same region): the bucket and writer roles (the plan fails without it)
- `core-platform` applied with `spec.observability.enabled: true`, so the `monitoring/*` service accounts are bound to those roles (the plan fails without it)

**Cluster components**, applied first on the same cluster (Backstage orders them from the catalog's `dependsOn`):

- None.

**You provide:**

- Nothing beyond the unit YAML; Backstage writes it.

**Access** (the workflow has all of this; locally you need it too):

- Terraform ≥ 1.15 and the `aws` CLI: the helm and kubernetes providers fetch an EKS token per call (`aws eks get-token`).
- Credentials for `Terraform-Role` in the unit's account, and the account's state bucket.
- Network reach to the cluster's **private** API endpoint: in the pipeline that is the `phoenix-mgmt` self-hosted runner in the management VPC.

### The unit file

```text
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/grafana-stack.yaml
state: <env_id>/<region>/k8s/<cluster>/grafana-stack/terraform.tfstate
```

One file per cluster. The identity block is the same as every unit's (see [`../../README.md`](../../README.md#a-units-yaml)); `spec` is described above. `spec.enabled: false` plans nothing.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd k8s-installs/modules/grafana-stack
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/k8s/<cluster>/grafana-stack/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/grafana-stack.yaml
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_with_defaults`, `bindings_match_core_platform`, `gpu_metrics_scraped`, `bucket_from_observability_state`, `missing_observability_rejected`, `disabled_plans_nothing`, `model_serving_dashboards`, `model_serving_off`).

### Outputs

| Output | |
|---|---|
| `namespace` | Namespace it runs in. |
| `grafana_service` | In-cluster Grafana service. |
| `endpoints` | Where other components send signals. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Nothing else on the cluster depends on it. Backstage destroys in reverse install order.
