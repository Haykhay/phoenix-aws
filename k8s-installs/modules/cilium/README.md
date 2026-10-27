# cilium

[Cilium](https://cilium.io/) as the cluster's network policy engine, chained
with the AWS VPC CNI: pods keep VPC addresses (so IPAM and the transit gateway
routing are unchanged) and Cilium only enforces policy. Part of every
cluster's baseline, installed right after cluster-config.

The AWS network lets a segment's VPCs reach each other; Cilium decides what
pods may actually reach.

## Default egress

A `CiliumClusterwideNetworkPolicy`, `phoenix-default-egress`, selects every
pod and allows:

- the cluster's own VPC CIDR;
- the platform's shared segment (tooling VPC, hub DNS);
- DNS to kube-dns, through Cilium's DNS proxy (so FQDN rules work);
- EKS Pod Identity (`169.254.170.23`) and instance metadata (`169.254.169.254`);
- the API server, the node and other nodes;
- the internet: everything outside RFC 1918.

Everything else private (other environments, on-prem) is denied until it is
opened, by the platform through `egress_allow` below, or by a team with a
namespaced `CiliumNetworkPolicy` shipped with its app through Argo CD (FQDN
rules such as `*.corp.local` included). Ingress is not restricted by default.

| `spec.settings` | Default | |
|---|---|---|
| `chart_version` | `1.20.2` | pinned by the platform (released 2026-09-16) |
| `egress_allow.cidrs` | `[]` | extra destinations for every pod (platform-managed) |
| `egress_allow.fqdns` | `[]` | extra FQDN patterns for every pod |
| `values` | `{}` | extra chart values |

`spec.network` (the platform settings, copied by Backstage) is required: the
shared segment comes from it. `spec.enabled: false` installs nothing.

## Running it

### Before you run it

**Infrastructure units**, applied first:

- `core-platform` for the environment and region: the cluster this unit targets (the plan fails without it)

**Cluster components**, applied first on the same cluster:

- `cluster-config` (baseline order; no catalog `dependsOn`).

**Access**: as every cluster component (see [`../reloader/README.md`](../reloader/README.md#running-it)): Terraform ≥ 1.15, the `aws` CLI, `Terraform-Role` in the unit's account, and reach to the cluster's private API (the `phoenix-mgmt` runner).

### The unit file

```text
k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/cilium.yaml
state: <env_id>/<region>/k8s/<cluster>/cilium/terraform.tfstate
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`chaining_values`, `default_policy_destinations`, `egress_allow_extends_policy`, `disabled_plans_nothing`). The policy chart renders with `helm template manifests/cilium-policy`.

### Removing it

Destroying it removes the default policy first, then Cilium; pods keep their
VPC CNI networking.
