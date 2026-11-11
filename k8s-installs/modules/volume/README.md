# volume

One PersistentVolumeClaim on one of the platform's cloud-neutral storage
classes, per file `volume.<claim name>.yaml`. Workloads ask for the class's
name; each cloud's platform maps it to its own storage.

| `storage_class` | What | Access | Provided by |
|---|---|---|---|
| `phoenix-block` (default) | a disk for one pod at a time; encrypted gp3 EBS here | `ReadWriteOnce` | `cluster-config` |
| `phoenix-shared` | a file system many pods mount at once; one FSx for Lustre file system per claim here | `ReadWriteMany` | `aws-fsx-csi-driver` |

```yaml
spec:
  namespace: apps            # required: where the pods that mount it run (created if missing)
  storage_class: phoenix-block
  size_gib: 100              # required: whole GiB
```

The plan fails without a claim name (the file's instance), for a class other
than those two, without `size_gib`, for a system namespace (`kube-system`,
`kube-public`, `kube-node-lease`, `default`), and for a `phoenix-shared` size
other than 1200 GiB or a multiple of 2400 GiB (FSx for Lustre). The claim
binds when a pod mounts it (`phoenix-block` binds where the pod lands), so the
apply doesn't wait for it. Destroying the unit deletes the claim and, both
classes reclaiming `Delete`, the disk or file system behind it.

Backstage writes it from the workload form's optional **Storage type**,
**Storage name**, **Storage namespace** and **Storage size (GiB)**.

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-platform` for the environment and region: the cluster this unit targets (the plan fails without it)

**Cluster components**, applied first on the same cluster (Backstage orders them from the catalog's `dependsOn`):

- `cluster-config` (`phoenix-block`); `aws-fsx-csi-driver` too for `phoenix-shared`.

**You provide:**

- Nothing beyond the unit YAML; Backstage writes it.

**Access** (the workflow has all of this; locally you need it too):

- Terraform ≥ 1.15 and the `aws` CLI: the helm and kubernetes providers fetch an EKS token per call (`aws eks get-token`).
- Credentials that can assume the unit's deploy role (`deploy_role_name`) in its account, and the account's state bucket: the backend, providers and state reads all assume that role.
- Network reach to the cluster's **private** API endpoint: in the pipeline that is the `phoenix-mgmt` self-hosted runner in the management VPC.

### The unit file

```text
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/volume.<claim name>.yaml
state: <env_id>/<region>/k8s/<cluster>/volume.<claim name>/terraform.tfstate
```

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd k8s-installs/modules/volume
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/k8s/<cluster>/volume.<claim name>/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/volume.<claim name>.yaml
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_block_volume`, `shared_volume_is_read_write_many`, `volume_rejects_unknown_class`, `volume_requires_size`, `shared_size_in_lustre_steps`, `volume_rejects_system_namespace`, `volume_needs_a_name`, `disabled_plans_nothing`).

### Outputs

| Output | |
|---|---|
| `claim_name` | PersistentVolumeClaim name. |
| `namespace` | Namespace the claim lives in. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Nothing else on the cluster depends on it; the pods that mount it should go first. Destroying it deletes the data.
