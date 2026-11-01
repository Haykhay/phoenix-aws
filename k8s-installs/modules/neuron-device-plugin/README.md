# neuron-device-plugin

The Neuron counterpart of `nvidia-gpu-operator`, for node pools with
`accelerator: neuron` (Trainium, Inferentia). The AL2023 Neuron AMI carries the
driver; this adds:

| Installs | |
|---|---|
| `neuron-helm-chart` `1.10.0` (2026-08-19, Neuron SDK 2.32) | `kube-system`: the Neuron device plugin (`aws.amazon.com/neuron` resources, tolerates `aws.amazon.com/neuron`) and the chart's node problem detector |
| `neuron-monitor` `1.12.0` (2026-08-18) | namespace `neuron-monitor`, a DaemonSet on `phoenix/accelerator=neuron` nodes exporting Neuron metrics on 8000; Alloy scrapes it (`prometheus.io/scrape`) |

| `spec` | Default | |
|---|---|---|
| `chart_version` | `1.10.0` | |
| `monitor_image` | `public.ecr.aws/neuron/neuron-monitor:1.12.0` | |

Keep the chart, the monitor and vllm's `neuron_image_tag` on the same Neuron
SDK release.

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-platform` for the environment and region: the cluster this unit targets (the plan fails without it)

**Cluster components:** none; it does nothing until a `karpenter-nodepool` with `accelerator: neuron` brings nodes.

**Access** (the workflow has all of this; locally you need it too):

- Terraform ≥ 1.15 and the `aws` CLI: the helm and kubernetes providers fetch an EKS token per call (`aws eks get-token`).
- Credentials for `Terraform-Role` in the unit's account, and the account's state bucket.
- Network reach to the cluster's **private** API endpoint: in the pipeline that is the `phoenix-mgmt` self-hosted runner in the management VPC.

### The unit file

```text
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/neuron-device-plugin.yaml
state: <env_id>/<region>/k8s/<cluster>/neuron-device-plugin/terraform.tfstate
```

The identity block is the same as every unit's (see [`../../README.md`](../../README.md#a-units-yaml)). `spec.enabled: false` plans nothing.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd k8s-installs/modules/neuron-device-plugin
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/k8s/<cluster>/neuron-device-plugin/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/neuron-device-plugin.yaml
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_with_defaults`, `disabled_plans_nothing`).

### Outputs

Only `resource_summary`, for the pipeline's summary.

### Removing it

Used by: vllm units with `hardware: neuron`. Destroy those first.
