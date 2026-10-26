# falco

Deploys [Falco](https://falco.org/) runtime security via the falco-operator. The operator pattern is used so Falco instances, rules, and plugins are managed as Kubernetes custom resources rather than a bespoke DaemonSet Helm chart, keeping the deployment model consistent with the other operator-backed modules in this repo (cloudnative-pg, valkey-redis, strimzi-kafka).

## What gets deployed

Three Helm releases in dependency order:

| Helm release | Chart | What it does |
|---|---|---|
| `falco-operator` | `falcosecurity/falco-operator` | Installs the operator controller and 5 CRDs (`Falco`, `Component`, `Rulesfile`, `Plugin`, `Config`) in the `falco-operator` namespace |
| `falco-artifacts` | local (`manifests/falco-artifacts/`) | Creates artifact CRs; must exist before the Falco instance so the artifact-operator sidecar is running when the Falco CR initialises |
| `falco-instance` | local (`manifests/falco-instance/`) | Creates the `Falco` CR; applied last so Terraform's destroy order is reversed correctly (see Uninstalling) |

### Custom resources created by `falco-artifacts`

| CR | Kind | Purpose |
|---|---|---|
| `container` | `Plugin` | Container metadata plugin from `ghcr.io/falcosecurity/plugins/plugin/container`. Required by any rule referencing `container.*` fields — load this before rules |
| `k8smeta` | `Plugin` | Kubernetes metadata plugin from `ghcr.io/falcosecurity/plugins/plugin/k8smeta`. Works with the metacollector to enrich events with pod name, namespace, and labels |
| `falco-rules` | `Rulesfile` | Standard CNCF Falco ruleset from `ghcr.io/falcosecurity/rules/falco-rules`; priority 50 |
| `metacollector` | `Component` | k8s-metacollector deployment — watches the Kubernetes API and streams metadata to Falco pods via gRPC; required for `k8smeta` plugin enrichment |

### Custom resources created by `falco-instance`

| CR | Kind | Purpose |
|---|---|---|
| `falco` | `Falco` | Falco instance — `spec: {}` tells the operator to use defaults (modern_ebpf driver, DaemonSet mode) |

## Why three Helm releases

**Artifact CRs before instance**: The operator runs an artifact-operator sidecar inside each Falco pod. If the `Falco` CR is created before Plugin/Rulesfile CRs exist, the instance starts with no rules or plugins loaded. Applying artifacts first guarantees they are present when the DaemonSet initialises.

**Instance last for safe uninstall**: On `terraform destroy`, Terraform reverses `depends_on` order:

```
falco-instance → falco-artifacts → falco-operator
```

This matches the required deletion sequence from the Falco operator docs — the `Falco` CR must be deleted *before* Plugin/Rulesfile CRs, otherwise the artifact-operator sidecar terminates while those resources still have finalizers set, leaving them stuck in `Terminating` indefinitely. See [Uninstalling](#uninstalling) below.

## Driver

`spec: {}` defaults to `modern_ebpf`, which attaches as an eBPF program compiled into the kernel image — no kernel module compilation, no kernel headers, works out of the box on EKS AL2023 and Bottlerocket (≥5.8 kernel).

## OCI artifact tags

Rules and plugins are pulled from `ghcr.io` as OCI artifacts at operator reconcile time. Tags default to `latest` (a known gap: they float); pin them in the unit's `spec` for reproducibility:

```yaml
spec:
  settings:
    rules_tag: "0.9.0"
    plugin_tag: "0.2.0"
    k8smeta_tag: "0.2.0"
```

## Configuration reference

All under `spec.settings` in the unit YAML (`spec.enabled: false` installs nothing). Part of every cluster's baseline; users never set these.

| Setting | Default | Description |
|---|---|---|
| `namespace` | `falco-operator` | Namespace for all Helm releases and CRs |
| `chart_version` | `0.3.1` | `falco-operator` Helm chart version |
| `values` | `{}` | Raw Helm values passed to the operator chart |
| `rules_tag` | `latest` | OCI tag for `falcosecurity/rules/falco-rules` |
| `plugin_tag` | `latest` | OCI tag for `falcosecurity/plugins/plugin/container` |
| `k8smeta_tag` | `latest` | OCI tag for `falcosecurity/plugins/plugin/k8smeta` |
| `timeout` | `300` | Helm install/upgrade timeout in seconds |

## Uninstalling

The operator uses finalizers on artifact CRs that are only resolved by the artifact-operator sidecar running inside each Falco pod. **The `Falco` CR must be deleted before Plugin/Rulesfile/Config CRs** — deleting artifacts first terminates the sidecar and their finalizers can never be resolved.

`terraform destroy` handles this automatically via the three-release dependency chain. If you need to destroy manually:

```bash
# 1. Falco instance CR first
helm uninstall falco-instance -n falco-operator

# 2. Artifact CRs once instance pods are gone
helm uninstall falco-artifacts -n falco-operator

# 3. Operator last
helm uninstall falco-operator -n falco-operator
kubectl delete namespace falco-operator
```

Note: Helm does not delete CRDs on uninstall. Remove them manually if needed:

```bash
kubectl delete crd \
  falcos.instance.falcosecurity.dev \
  components.instance.falcosecurity.dev \
  configs.artifact.falcosecurity.dev \
  plugins.artifact.falcosecurity.dev \
  rulesfiles.artifact.falcosecurity.dev
```

## Verifying the deployment

```bash
# Operator pod
kubectl get pods -n falco-operator

# All CRs
kubectl get falco,plugin,rulesfile,component -n falco-operator

# Falco DaemonSet and metacollector Deployment
kubectl get daemonset,deployment -n falco-operator

# Live event stream (pick any Falco pod)
kubectl logs -n falco-operator -l app.kubernetes.io/name=falco -f
```

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-platform` for the environment and region: the cluster this unit targets (the plan fails without it)

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
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/falco.yaml
state: <env_id>/<region>/k8s/<cluster>/falco/terraform.tfstate
```

One file per cluster. The identity block is the same as every unit's (see [`../../README.md`](../../README.md#a-units-yaml)); `spec` is described above. `spec.enabled: false` plans nothing.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd k8s-installs/modules/falco
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/k8s/<cluster>/falco/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/falco.yaml
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_with_defaults`, `disabled_plans_nothing`).

### Outputs

| Output | |
|---|---|
| `enabled` | Whether Falco is installed. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Nothing else on the cluster depends on it. Backstage destroys in reverse install order.
