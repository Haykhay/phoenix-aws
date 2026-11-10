# aws-fsx-csi-driver

The FSx for Lustre CSI driver, the platform's `phoenix-shared` StorageClass,
and, when the cluster has a model cache (infrastructure's
`model-cache.<cluster>`), one static read-only volume on it. vLLM pods
mount claim `model-cache` in namespace `models` with subPath `weights` at
`/models`, so a model's weights are at `/models/<model>/<version>/`.

| Installs | |
|---|---|
| `aws-fsx-csi-driver` chart `1.18.0` (driver v1.10.0) | `kube-system`; the node daemonset tolerates every taint, so it runs on GPU (`nvidia.com/gpu`) and Neuron (`aws.amazon.com/neuron`) nodes |
| PersistentVolume `model-cache-models` | static, `ReadOnlyMany`, `readOnly`, `Retain`: the file system belongs to `model-cache`, never to this claim |
| PersistentVolumeClaim `model-cache` | in `models`, bound to that volume |
| StorageClass `phoenix-shared` | the cloud-neutral name for a file system many pods share: one FSx for Lustre file system per claim (`PERSISTENT_2`, 125 MB/s per TiB, in the first node subnet), tagged `PhoenixCluster=<cluster>`, deleted with its claim. Sizes: 1200 GiB, then steps of 2400 GiB |
| IAM role `<prefix>-fsx-csi` (Pod Identity, `fsx-csi-controller-sa`) | the driver's documented minimum, scoped: create file systems only tagged with this cluster, change or delete only those |
| Security group `<prefix>-fsx-shared` | on the `phoenix-shared` file systems: Lustre (988, 1018-1023) from the nodes and from itself |

Without a model cache (a cluster that serves no models) it installs the driver
and `phoenix-shared` only; `vllm` itself refuses to start without the cache.
Nodes need no Lustre package: the driver's node image carries the Lustre
client and loads its kernel module. Ask for `phoenix-shared` through the
`volume` component.

| `spec` | Default | |
|---|---|---|
| `chart_version` | `1.18.0` | |

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-platform` for the environment and region: the cluster this unit targets (the plan fails without it)
- `model-cache.<cluster>`, if the cluster serves models: the cache's file system

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

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_with_defaults`, `volume_comes_from_state`, `no_model_cache_installs_driver_only`, `shared_class_uses_fsx`, `driver_role_scoped_to_cluster`, `lustre_ports_from_nodes`, `disabled_plans_nothing`).

### Outputs

| Output | |
|---|---|
| `pvc_name` | Read-only claim on the model cache, in namespace models. |
| `mount_path` | Where model servers mount the claim: weights are at <mount_path>/<model>/<version>. |
| `sub_path` | Claim subPath to mount at mount_path: the weights bucket's directory inside the file system. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Used by: vllm (every model on the cluster mounts the claim) and every `volume` on `phoenix-shared`. Destroy those first: a `phoenix-shared` claim's file system is deleted with the claim. Removing it never touches the model cache's file system or the weights.
