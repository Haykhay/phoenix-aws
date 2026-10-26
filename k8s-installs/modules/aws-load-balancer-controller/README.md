# aws-load-balancer-controller

The [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
(chart `3.4.0`, pinned) in `kube-system`, with Pod Identity
(`aws-load-balancer-controller` → `<name_prefix>-aws-load-balancer-controller`,
AWS's reference policy in `iam-policy.json`). Part of the **service** set;
istio's gateways get their NLBs from it.

- `vpcId` and `region` are set explicitly: nodes require IMDSv2 with the
  default hop limit, so the controller cannot rely on instance metadata.
- Load balancers it creates carry the unit's tags (`defaultTags`) plus `Cluster`.
- Gateway API CRDs are **not** installed here any more — istio owns them.

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
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/aws-load-balancer-controller.yaml
state: <env_id>/<region>/k8s/<cluster>/aws-load-balancer-controller/terraform.tfstate
```

One file per cluster. The identity block is the same as every unit's (see [`../../README.md`](../../README.md#a-units-yaml)); `spec` is described above. `spec.enabled: false` plans nothing.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd k8s-installs/modules/aws-load-balancer-controller
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/k8s/<cluster>/aws-load-balancer-controller/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/aws-load-balancer-controller.yaml
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`plans_with_defaults`, `personal_env_names_fit`, `disabled_plans_nothing`).

### Outputs

| Output | |
|---|---|
| `release_name` | Helm release name. |
| `role_arn` | IAM role its service account uses, through Pod Identity. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Destroy these first, on the same cluster: `istio`. Backstage destroys in reverse install order.
