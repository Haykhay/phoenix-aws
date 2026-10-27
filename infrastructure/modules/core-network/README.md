# core-network

Bundled resource-set module for environment networking. It creates a **named set
of VPCs** for one environment/region and publishes them in the common network
state that every other resource set reads.

Per VPC:

- VPC
- subnets (data and platform roles, plus public)
- route tables
- NAT (independent egress only)
- optional VPC endpoints
- transit gateway attachment to its region's network, associated with its
  segment's route table and propagated per the segment
- associations with the forwarding rules shared from the hub (on-prem DNS)
- base security groups

The region's network (transit gateway, segment tables, IPAM pools, peerings)
is the `networking/` layer's; this module only joins it.

## Where this runs

```text
environments/<tier>/<env_id>/<region>/core-network.yaml
state: <env_id>/<region>/core-network/terraform.tfstate
```

A VPC is regional, so core-network always lives under a region scope, never
under `global`. Nothing sits between the scope and the resource set in that key,
so this state is the environment's common network state by construction.
Downstream resource sets never build the key themselves — `modules/context`
(`network = true`) reads it and exposes the VPC they bind to as
`module.context.network`. A resource set binds to `default_vpc` unless its spec
sets `vpc: <key>`.

## Configuration

Values only, under `spec` in the unit's YAML (the identity, state and tag fields
are described in `modules/context/README.md`):

```yaml
spec:
  default_vpc: vpc-1
  vpcs:
    vpc-1:
      azs: [eu-west-1a, eu-west-1b, eu-west-1c]
      enable_vpc_endpoints: true
  network: { ... }                 # the platform settings, copied by Backstage (../../../networking/README.md)
  vpc_netmask: 20                  # the platform's size for this tier, copied by Backstage
  providers:
    network:
      account_id: "<networking account id>"   # role: its Terraform-Role
      state_bucket: <networking account state bucket>
      state_region: <its region>
      state_kms_key_id: <key id>   # optional
```

`vpc_defaults` applies to every VPC; an entry in `vpcs` overrides it. Precedence
is module defaults (`locals.tf`) → `vpc_defaults` → the individual VPC.

| Key | Default | Notes |
|---|---|---|
| `enabled` | `true` | The file existing enables the unit; `false` plans a destroy of everything in it |
| `default_vpc` | — | Required once more than one VPC exists |
| `name` | `<name_prefix>-<vpc key>` | Name tag / prefix for that VPC's resources |
| `segment` | from the tier | Only `shared` may be set, and only in the tooling account (`spec.network.tooling_account_id`); `prod` → production, `sandbox`/`stage`/`uat` → non-production |
| `netmask` | `spec.vpc_netmask`, else sandbox `20`, others `18` | Size of the VPC, `/17` to `/22` |
| `azs` | — | Exactly 3 |
| `enable_nat_gateway` | `false` central, `true` independent | Follows the platform's `egress_mode` |
| `single_nat_gateway` | `true` | |
| `enable_vpn_gateway` | `false` | Attaches a VGW to the VPC |
| `enable_tgw_attachment` | `true` | Every VPC joins its region's transit gateway |
| `tgw_destination_cidrs` | central `0.0.0.0/0`; independent `address_space` + `onprem_cidrs` | Private routes toward the transit gateway |
| `enable_vpc_endpoints` | `false` | Per-VPC cost: ~15 interface endpoints × AZ. Interface endpoints do not span VPCs |
| `enable_elb_subnet_tags` | `false` | Load balancer subnet discovery tags — see below. Turn on before any load balancer exists in the VPC |
| `endpoint_services` | 15 common services | Includes `s3`, created as a gateway endpoint |

There is no literal `cidr` or subnet list: a VPC carrying `cidr`,
`private_subnets_data`, `private_subnets_platform` or `public_subnets` is
rejected at plan. Addresses come from IPAM only, and IPAM's atomic allocation is
what keeps VPCs from overlapping.

**Cost note.** Endpoints are billed per VPC and default to off for that
reason. In central egress mode NAT is the region's egress VPC, shared by every
environment.

## Tests

```bash
terraform init -backend=false && terraform test
```

Mock providers; no AWS access. The networking `region` unit's state is
overridden with fixed transit gateway, table and pool IDs.

## VPCs from IPAM

New VPCs do not pick a CIDR. IPAM hands out the next free block from the
region's pool for the VPC's segment (the networking `region` unit's
`pool_ids`, shared with the organisation).

- `netmask` defaults to the tier's size. The block is claimed first
  (`aws_vpc_ipam_pool_cidr_allocation`), then the VPC is created with that exact
  CIDR and its subnets carved from it. The allocation is atomic, so any number
  of accounts sharing a pool can apply at the same time without racing for a
  block. It stays in the pool, described with the VPC name, environment and
  account, until the VPC is destroyed.
- IPAM records the block as a pool allocation, not as a pool-linked VPC, so the
  VPC itself shows as `unmanaged` in IPAM compliance — the same as the legacy
  VPCs imported as reserved. The allocation is what stops overlaps.
- Subnets are derived, never configured, one per AZ:

  | Role | Share of the VPC | In a `/18` |
  |---|---|---|
  | platform (EKS nodes and pods) | quarters 0–2 | 3 × `/20` |
  | data (RDS, cache, MSK, TGW attachment) | sixteenths 12–14 | 3 × `/22` |
  | public | sixty-fourths 60–62 | 3 × `/24` |

  The last sixty-fourth is left free.
- Routing needs no per-VPC change: a region's share of each segment is one
  block, routed as one prefix by every peering, and each segment is one
  summary on Direct Connect.

## Load balancer subnet tags

`enable_elb_subnet_tags` tags the subnets the AWS Load Balancer Controller
discovers by role:

| Subnets | Tag |
|---|---|
| EKS subnets: platform, or every private subnet in a VPC with none | `kubernetes.io/role/internal-elb = 1` |
| Public | `kubernetes.io/role/elb = 1` |
| Data | none, so no load balancer is ever placed there |

Without any role tag, the controller (≥ 2.12.1) treats *every* private subnet
as a candidate and picks the lowest subnet ID per AZ — so internal load
balancers land in data subnets in whichever AZs the IDs happen to sort that way
(sandbox-1's internal NLBs sit in data subnets in two of three AZs).

The upstream VPC module can only tag all private subnets alike, so the
internal-elb tag is an `aws_ec2_tag` per subnet. The default AWS provider (`providers.tf`)
ignores that key (`ignore_tags`), otherwise the module's `aws_subnet` would
remove it on every apply; `aws_ec2_tag` does not honour `ignore_tags`.

**Opt-in.** On a VPC that already has internal load balancers, the tags change
which subnets the controller wants, and it will try to move them — for an NLB,
replacing a subnet within an AZ can be disruptive. Turn it on for new VPCs
before anything creates a load balancer; for existing ones, plan the move
first.

## Naming

VPC names are **derived, never written**:

```
<name_prefix>-<vpc key>     e.g. research-sandbox-euw1-vpc-1
```

Everything else is built from that one string — subnet names, interface and
gateway endpoint names, the endpoint security group, the TGW attachment.

Each resource's `Name` tag is its own name:

| Resource | `Name` |
|---|---|
| VPC, internet gateway | `<vpc name>` |
| Subnets | `<vpc name>-data-<n>`, `<vpc name>-platform-<n>`, `<vpc name>-public-<n>` (one per AZ, in `azs` order) |
| Route tables | `<vpc name>-public`; `<vpc name>-private` (`-private-<az>` per NAT gateway without `single_nat_gateway`) |
| NAT gateway, its EIP | `<vpc name>-<az>` |
| Default SG / NACL / route table | `<vpc name>-default` |

These come from `terraform-aws-vpc`, which merges the module-wide `tags` *after*
each resource's own `Name`. That is why `Name` must never go in `tags`: it would
overwrite every one of them with the VPC's name.

The `<name_prefix>` part (`<env_id>-<region code>`) is **not** built here.
`modules/context` derives it, so the scheme lives in exactly one place — the
line to change when the Phoenix naming convention is settled. It is
still **Proposed**. What holds meanwhile:

- `organisation`, `group`, `environment` and `requester` must match
  `^[a-z][a-z0-9]*(-[a-z0-9]+)*$`; `modules/context` fails the plan otherwise
- a region with no code in `modules/context` fails the plan rather than falling
  back to the long form
- `main.tf` requires the resulting VPC names to be unique across the VPC map
- The integer cluster suffix 1–20 applies to clusters, not VPCs

## Outputs

`networks` is the contract; the flat single-VPC outputs are deprecated shims
that resolve against the default VPC.

```hcl
networks = {
  "<vpc name>" = {
    name, vpc_id, vpc_cidr_block, azs
    private_subnet_ids, data_subnet_ids, platform_subnet_ids, public_subnet_ids
    private_subnet_cidrs, data_subnet_cidrs, platform_subnet_cidrs, public_subnet_cidrs
    private_route_table_ids, public_route_table_ids
    vpc_endpoint_security_group_id, vpc_endpoint_ids
    tgw_attachment_id
  }
}
default_vpc_name = "<vpc name>"
vpc_names        = ["<vpc name>", ...]
```

## Apply order

Backstage applies core-network before every resource set that binds to a VPC,
and destroys it after them. A consumer planned before core-network has state
gets `module.context.network = null` and fails on its own precondition rather
than planning on placeholders; a consumer destroyed after core-network is gone
still plans, because the lookup yields `null` instead of an error.

Any plan proposing to **replace** a VPC, subnet or NAT gateway is wrong — stop
and investigate. Renames are in-place `Name`-tag updates; the one exception is
the VPC-endpoint security group, whose `name` cannot change in place, so it is
replaced and the interface endpoints are updated to point at the new one.

## Joining the region's network

The transit gateways, their route tables and the peerings belong to the
networking account (`networking/` layer). This module runs with the workload
account's credentials and reaches the networking account through the
`aws.network` provider (its deploy role,
`arn:aws:iam::<spec.providers.network.account_id>:role/Terraform-Role`), which
makes the associations and propagations.

It reads the region's facts from the networking state:
`spec.providers.network.state_bucket`, key
`platform-network/<region>/region/terraform.tfstate`, assuming the same role.
Without `spec.network` and `spec.providers.network`, or before the region's
network exists, the plan fails with that instruction.

| Segment | Associated with | Propagates into |
|---|---|---|
| production | `production` | `production`, `shared` |
| non-production | `non-production` | `non-production`, `shared` |
| shared (tooling) | `shared` | all three |

Production and non-production never see each other's routes; the region's
blackholes drop anything that tries.

## Egress

The platform's `egress_mode` decides:

- **central**: no NAT gateway; private default route to the transit gateway,
  out through the region's egress VPC.
- **independent**: the VPC's own NAT gateway; only `address_space` and
  `onprem_cidrs` go to the transit gateway.

Either way the VPC keeps its public subnets and internet gateway for inbound
load balancers.

## Troubleshooting

- **403 on the networking state during plan**: the remote-state read is
  running without the networking-account role; the `assume_role` block in
  `data.tf` must be present.
- **"No transit gateway / pool for <region>"**: the region's network does not
  exist yet. Backstage creates it before the first environment; by hand, see
  [`../../../networking/README.md`](../../../networking/README.md).

## Running it

### Before you run it

**Needs:**

- The group's AWS account, its `Terraform-Role` and its state bucket (account vending).
- The region's network: the networking `region` unit applied in this region (Backstage does it on the region's first environment).
- The networking account (`spec.providers.network.account_id` and `.state_bucket`) and the platform settings (`spec.network`).

**Access** (the workflow has all of this; locally you need it too):

- Terraform ≥ 1.15.
- Credentials for `Terraform-Role` in the unit's account (account vending creates it), and the account's state bucket.
- Runs on GitHub-hosted runners: it talks to AWS APIs only.

### The unit file

```text
infrastructure/environments/<tier>/<env_id>/<region>/core-network.yaml
state: <env_id>/<region>/core-network/terraform.tfstate
```

The identity block is described in [`../context/README.md`](../context/README.md); `spec` is described above.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd infrastructure/modules/core-network
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/<region>/core-network/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/core-network.yaml -var pipeline_user=$USER
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (segment per tier and the shared override, central and independent egress, shared Resolver rules, literal CIDRs and a missing network rejected).

### Outputs

| Output | |
|---|---|
| `networks` | All VPCs in this environment/region, keyed by VPC name. |
| `default_vpc_name` | VPC that resource sets bind to unless they set `vpc` explicitly. |
| `vpc_names` | Names of every configured VPC. |
| `name_prefix` | Naming prefix for account/region-level network resources. |
| `vpc_id` | Default VPC: ID. |
| `vpc_cidr_block` | Default VPC: CIDR block (from IPAM). |
| `private_subnets` | Default VPC: private subnet IDs. |
| `data_subnet_ids` | Default VPC: data subnet IDs (databases). |
| `platform_subnet_ids` | Default VPC: platform subnet IDs (EKS nodes). |
| `public_subnets` | Default VPC: public subnet IDs. |
| `private_subnet_cidrs` | Default VPC: private subnet CIDRs. |
| `public_subnet_cidrs` | Default VPC: public subnet CIDRs. |
| `private_route_table_ids` | Default VPC: private route table IDs. |
| `vpc_endpoint_security_group_id` | Default VPC: security group on its interface endpoints. |
| `vpc_endpoint_ids` | Default VPC: interface endpoint IDs, by service. |
| `tgw_attachment_id` | Default VPC: transit gateway attachment ID, if attached. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Used by: core-platform, data-rds, data-elasticache, data-msk (and anything with `network = true` in `modules/context`). Destroy those first.
