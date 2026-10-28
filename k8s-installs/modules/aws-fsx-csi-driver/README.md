# aws-fsx-csi-driver

The FSx for Lustre CSI driver, plus one static read-only volume on the
cluster's model cache (infrastructure's `model-cache.<cluster>`). vLLM pods
mount claim `model-cache` in namespace `models` with subPath `weights` at
`/models`, so a model's weights are at `/models/<model>/<version>/`.

| Installs | |
|---|---|
| `aws-fsx-csi-driver` chart `1.18.0` (driver v1.10.0) | `kube-system`; the node daemonset tolerates every taint, so it runs on GPU (`nvidia.com/gpu`) and Neuron (`aws.amazon.com/neuron`) nodes |
| PersistentVolume `model-cache-models` | static, `ReadOnlyMany`, `readOnly`, `Retain`: the file system belongs to `model-cache`, never to this claim |
| PersistentVolumeClaim `model-cache` | in `models`, bound to that volume |

No IAM: with a static volume the controller never calls AWS. Nodes need no
Lustre package: the driver's node image carries the Lustre client and loads its
kernel module.

| `spec` | Default | |
|---|---|---|
| `chart_version` | `1.18.0` | |

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-platform` for the environment and region: the cluster this unit targets (the plan fails without it)
- `model-cache.<cluster>`: the file system (the plan fails without it)

**Cluster components:** none.

**Access** (the workflow has all of this; locally you need it too):

- Terraform ≥ 1.15 and the `aws` CLI: the helm and kubernetes providers fetch an EKS token per call (`aws eks get-token`).
- Credentials for `Terraform-Role` in the unit's account, and the account's state bucket.
- Network reach to the cluster's **private** API endpoint: in the pipeline that is the `phoenix-mgmt` self-hosted runner in the management VPC.

### The unit file

```text
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/aws-fsx-csi-driver.yaml
state: <env_id>/<region>/k8s/<cluster>/aws-fsx-csi-driver/terraform.tfstate
```

The identity block is the same as every unit's (see [`../../README.md`](../../README.md#a-units-yaml)). `spec.enabled: false` plans nothing.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd k8s-installs/modules/aws-fsx-csi-driver
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/k8s/<cluster>/aws-fsx-csi-driver/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/aws-fsx-csi-driver.yaml
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_with_defaults`, `volume_comes_from_state`, `missing_model_cache_rejected`, `disabled_plans_nothing`).

### Outputs

| Output | |
|---|---|
| `pvc_name` | Read-only claim on the model cache, in namespace models. |
| `mount_path` | Where model servers mount the claim: weights are at <mount_path>/<model>/<version>. |
| `sub_path` | Claim subPath to mount at mount_path: the weights bucket's directory inside the file system. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Used by: vllm (every model on the cluster mounts the claim). Destroy those first. Removing it never touches the file system or the weights.
