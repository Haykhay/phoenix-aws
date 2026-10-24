# core-platform

Bundled resource-set module for environment compute. It creates a **named set of
EKS clusters** for one environment/region, all in one state.

Per cluster:

- EKS control plane and managed node groups
- cluster IAM, KMS and access entries
- cluster addons (Pod Identity is always installed)
- optional EBS CSI pod identity role
- optional Karpenter IAM, interruption queue and node access entry
- optional VPN and CI-runner ingress to the API endpoint
- GPU node groups (configuration only)
- Pod Identity bindings to the group's observability roles

## Where this runs

```text
environments/<tier>/<env_id>/<region>/core-platform.yaml
state: <env_id>/<region>/core-platform/terraform.tfstate
```

One state holds every cluster in the region. Removing a cluster's entry destroys
exactly that cluster and leaves the others untouched. Backstage applies it after
core-network and observability, and destroys it before core-network.

## Configuration

Values only, under `spec` in the unit's YAML:

```yaml
spec:
  default_cluster: "1"
  cluster_defaults:
    version: "1.34"
    cluster_addons:
      coredns: {}
  clusters:
    "1":
      node_groups:
        cpu-1: { instance_types: [m6i.large], min_size: 2, max_size: 4, desired_size: 2 }
    "2":
      vpc: vpc-2
      node_groups:
        test-1: { instance_types: [t3.medium], desired_size: 1 }
  vpn_cidr: 10.0.0.0/24          # optional: API endpoint ingress from the VPN
  ci_runners_cidr: 10.1.0.0/19   # optional: from self-hosted CI runners
  observability:
    enabled: true                # see Observability
```
`cluster_defaults` applies to every cluster; an entry in `clusters` overrides it.
Precedence is module defaults (`local.tf`) → `cluster_defaults` → the individual
cluster.

**Map-valued keys merge per entry rather than replacing.** A cluster that pins
one addon keeps the others from `cluster_defaults`; without that, naming one
entry would drop the rest, and a dropped addon is a *destroyed* addon — losing
`vpc-cni` that way takes pod networking with it. The same applies to
`node_groups`, `pod_identity`, `karpenter`, `node_role_additional_policies` and
`access_entries.admin`/`.view`. Scalars (`version`, `vpc`, `cluster_name`, ...) replace
as you would expect.

This is what makes shared settings practical: write them in `cluster_defaults`
once and let each cluster override only what it needs.

| Key | Default | Notes |
|---|---|---|
| `default_cluster` | — | Required once more than one cluster exists |
| `cluster_name` | `<prefix>-<key>-eks` | Name for that cluster's resources |
| `vpc` | network's default | Which VPC this cluster sits in |
| `version` | — | Kubernetes version. **Required** — no default |
| `node_groups` | `{}` | Managed node groups |
| `cluster_addons` | `{}` | Installed after Pod Identity — see Addons |
| `access_entries` | `{}` | Extra principals: `admin` (cluster-admin) and `view` (read-only, `AmazonEKSViewPolicy`), each `name => role ARN` |
| `pod_identity` | `{}` | `aws_ebs_csi.enabled` creates the CSI role |
| `karpenter` | `{}` | `enabled` creates Karpenter's AWS resources — see Karpenter |
| `enable_irsa` | `false` | OIDC provider for IAM roles for service accounts |
| `endpoint_public_access` | `false` | Exposes the API server to the internet — see Access |
| `enable_cluster_creator_admin_permissions` | `false` | Grants the applying principal cluster-admin |
| `admin_role_names` | `[]` | Extra roles, unioned with DevOps/DevOpsLead/SolutionArchitect |
| `node_role_additional_policies` | `{}` | Extra managed policies on the node role |
| `cluster_enabled_log_types` | api, audit, authenticator, controllerManager, scheduler | Control-plane logs |
| `tags` | `{}` | Ownership tags |

## Addons

Addons are installed in three phases so an addon can rely on a Pod Identity
association existing before its pods start:

1. `module.eks` installs **only** `eks-pod-identity-agent`, so the agent is
   running before anything needs it
2. Pod Identity roles and associations are created
3. every configured addon is created, keyed `<cluster>/<addon>`

Installed inside `module.eks`, an addon that needs an association could never
start: the association is created after the module completes, and the module
cannot complete until the addon is healthy. The EBS CSI driver hit exactly that
— its controller crash-looped on a 403 from `ec2:DescribeAvailabilityZones`,
the addon timed out after 20 minutes, and re-running repeated it.

### Versions

Two modes, in priority order:

| Config | Version used |
|---|---|
| `addon_version: "v1.22.3-eksbuild.1"` | Exactly that — explicit pin |
| everything else (`{}`, `most_recent: true`, or omitted) | Latest version compatible with the cluster's Kubernetes version, resolved at plan time |

`most_recent` defaults to `true`. Listing an addon with `{}` is enough to keep it
at the latest version. Set `most_recent: false` only to explicitly opt out and let
AWS pick the default at creation time (version unmanaged after that). `addon_version`
always wins over `most_recent`.

```yaml
cluster_defaults:
  cluster_addons:
    coredns: {}
    kube-proxy: {}
    vpc-cni: {}
    aws-ebs-csi-driver: {}
    eks-pod-identity-agent: {}
clusters:
  "1":
    cluster_addons:
      kube-proxy: { addon_version: v1.34.6-eksbuild.17 }
```

Cluster `1` gets `kube-proxy` pinned to that exact build; the other four addons
resolve to the latest compatible version at every apply. Cluster `2` inherits
everything from defaults and stays fully up to date automatically.

Version resolution runs per cluster against that cluster's own `version`, so
`cluster_defaults` is safe across clusters on different Kubernetes versions — each
gets the right latest build for its version.

Explicit `addon_version` pins are still tied to a Kubernetes version.
The plan rejects one pin shared by clusters on different versions:
the API only catches it at apply, leaving a green plan and an apply that fails
partway. Omitting the pin avoids that entirely.

There is no module-level default version map: the module is shared across
environments running different Kubernetes versions, so no single pin is right for
all of them.

## Karpenter

A cluster that sets `karpenter.enabled` gets Karpenter's AWS resources, from the
`modules/karpenter` submodule of the same `terraform-aws-modules/eks` version as
`module.eks`:

| Resource | Name |
|---|---|
| Controller IAM role + policy, Pod Identity association | `<cluster>-karpenter-controller` |
| Node IAM role + `EC2_LINUX` access entry | `<cluster>-karpenter-node` |
| SQS interruption queue + EventBridge rules | `<cluster>-karpenter` |

`<cluster>` is `cluster_name` without its `-eks` suffix. The node role gets the
same managed policies as the managed node group roles, including
`node_role_additional_policies`.

```yaml
clusters:
  "1":
    karpenter: { enabled: true }
```

| Key | Default | Notes |
|---|---|---|
| `enabled` | `false` | |
| `namespace` | `karpenter` | Pod Identity association namespace. Must match where the in-cluster repo deploys the controller |
| `service_account` | `karpenter` | Pod Identity association service account |
| `interruption_handling` | `true` | SQS queue + EventBridge rules for spot interruption, rebalance, health and state-change events |

The controller itself, its CRDs and NodePools are deployed by
the in-cluster repo's Karpenter module,
which reads the names above from the `clusters` output's `karpenter` entry. Apply
this first.

The submodule's v1 controller policy dates from Karpenter 1.0; `karpenter.tf`
adds what upstream has added since (up to 1.15) as a second managed policy,
`<cluster>-karpenter-controller-extra`, on the same role. It cannot go into the
submodule's policy: IAM caps a managed policy at 6,144 characters (whitespace
excluded), and the v1 policy alone is ~5,550. Diff it against the upstream
reference policy whenever the in-cluster repo bumps the Karpenter chart.

Disabling it with Karpenter nodes still running removes the role those nodes
use. Remove the controller and its NodePools in the in-cluster repo first.

## Access

`endpoint_public_access` is `false`, so the API server resolves only inside the
VPC. `vpn_cidr` and `ci_runners_cidr` each add an HTTPS ingress rule to the
endpoint when set; unset, there is no rule (network design — VPN, self-hosted
runners — is decided outside this module). GitHub-hosted runners have no fixed
range and cannot reach a private endpoint.

Both rules are created **inside** `module.eks` via
`cluster_security_group_additional_rules`, deliberately: declared outside, they
would depend on a module output, which makes them wait for the entire module —
so a failing addon would leave the cluster with no ingress at all, and
unfixable by re-running.

Setting `endpoint_public_access` `true` publishes the endpoint to everything in
`publicAccessCidrs`, which defaults to `0.0.0.0/0`. Narrow that in the same
change if you ever need it.

## GPU node groups

GPU capacity for model serving (vLLM) is configuration only — a managed node
group with the NVIDIA-ready EKS image and a taint so only GPU workloads land on
it:

```yaml
node_groups:
  gpu-1:
    ami_type: AL2023_x86_64_NVIDIA
    instance_types: [g6.xlarge]
    min_size: 0
    max_size: 2
    desired_size: 0
    taints:
      gpu: { key: nvidia.com/gpu, value: "true", effect: NO_SCHEDULE }
```

`min_size: 0` lets an idle group cost nothing. For on-demand GPU nodes that scale
to zero, enable Karpenter and define a GPU NodePool in the in-cluster repo; the
NVIDIA device plugin / GPU operator and DCGM exporter are deployed there too.

## Observability

With `observability.enabled: true`, each cluster's in-cluster stack is bound to
the group's long-lived `observability` resource set (S3 history that survives
weekend teardowns — see `modules/observability`). Its outputs are read from
`<group>-<observability.environment, default shared>/<region>/observability/terraform.tfstate`,
and one Pod Identity association is created per cluster and writer:

| Writer | Namespace / service account | Role |
|---|---|---|
| `mimir`, `loki`, `tempo` | `monitoring/<writer>` | writes `<writer>/<cluster name>/` |
| `langfuse` | `langfuse/langfuse` | writes `langfuse/<cluster name>/` |
| `grafana` | `monitoring/grafana` | CloudWatch read-only |

Override bindings with `observability.service_accounts.<writer> = { namespace,
service_account }`. Apply observability before this resource set.

## Naming

```text
<name_prefix>-<cluster key>-eks    e.g. vision-sandbox-jdoe-euw1-2-eks
```

`<name_prefix>` comes from `modules/context` (see the repo README). The
`cluster_name` override exists so a cluster can keep a name; changing it
**replaces the cluster**, since `name` is ForceNew on `aws_eks_cluster`.

The `Name` tag is the cluster's own name, on the cluster and on every resource
that carries the cluster's tags without a name of its own: IAM roles, KMS key,
addons, launch templates, and the IRSA OIDC provider. Resources that have one
keep it: security groups, the control-plane log group, node groups and the
instances, volumes and ENIs they launch.

Changing it does not roll nodes. The launch template's `tag_specifications`
merge the node group's `Name` *after* the cluster tags, and the launch
template's own `tags` are not versioned. Any other tag in the cluster's `tags`
(e.g. `CreatedBy`) does reach `tag_specifications` and does roll every node.

## Tests

```bash
terraform init -backend=false && terraform test
```

Mock providers; no AWS access. Covers VPC binding, GPU taint pass-through,
observability bindings on and off, the missing-network and shared-addon-pin
checks.

## Outputs

```hcl
clusters = {
  "<key>" = {
    cluster_name, cluster_id, cluster_arn, cluster_endpoint
    cluster_certificate_authority_data, cluster_kms_key_arn
    cluster_security_group_id, node_security_group_id, version, vpc, vpc_id
    karpenter = null | {
      controller_role_arn, node_role_name, node_role_arn,
      queue_name, namespace, service_account
    }
  }
}
default_cluster_name = "<key>"
cluster_names        = ["<key>", ...]
```

`cluster_security_group_id` is the EKS-managed cluster security group (distinct from the node security group). Spoke Kargo controllers read this via remote state to self-register an ingress rule for management API access — see the in-cluster repo's Kargo module.

## Binding to a cluster

Consumers name the cluster they want. The `data-*` sets do it per item with
`eks_clusters` (see the repo README) — that grants the cluster's node security
group ingress, so it is required once more than one cluster exists.

`default_cluster` only feeds the deprecated flat outputs (`cluster_name`,
`node_security_group_id`, ...), which exist for consumers that predate the
`clusters` map — currently the in-cluster repo. It is optional with one cluster and
required with more, and disappears once those consumers index `clusters` by name.
