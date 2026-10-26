# nvidia-gpu-operator

NVIDIA's [GPU operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
(chart `v26.7.1`, pinned) in `gpu-operator`. Installed whenever a request picks
a GPU type.

The AL2023 NVIDIA AMIs Karpenter launches already include the driver and the
container toolkit, so those are **off**; the operator adds the device plugin
(`nvidia.com/gpu` resources), GPU feature discovery and the **DCGM exporter**.
grafana-stack's Alloy scrapes the exporter's pods (label
`app=nvidia-dcgm-exporter`) into Mimir, so GPU utilisation, memory and
temperature show up per cluster in Grafana.

`spec`: `chart_version`, `enabled`.

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
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/nvidia-gpu-operator.yaml
state: <env_id>/<region>/k8s/<cluster>/nvidia-gpu-operator/terraform.tfstate
```

One file per cluster. The identity block is the same as every unit's (see [`../../README.md`](../../README.md#a-units-yaml)); `spec` is described above. `spec.enabled: false` plans nothing.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd k8s-installs/modules/nvidia-gpu-operator
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/k8s/<cluster>/nvidia-gpu-operator/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/nvidia-gpu-operator.yaml
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`driver_disabled_dcgm_on`, `disabled_plans_nothing`).

### Outputs

| Output | |
|---|---|
| `namespace` | Namespace it runs in. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Destroy these first, on the same cluster: `vllm`. Backstage destroys in reverse install order.
