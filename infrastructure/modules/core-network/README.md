# core-network

Bundled resource-set module for environment networking. It creates a **named set
of VPCs** for one environment/region and publishes them in the common network
state that every other resource set reads.

Per VPC:

- VPC
- subnets (data and platform roles, plus public)
- route tables
- NAT
- optional VPC endpoints
- optional Transit Gateway attachment and cross-region peering routes
- base security groups

Per account/region (created once, no matter how many VPCs): the optional TGW RAM
share and the peering return routes on the regional route table.

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
  vpc_defaults:
    enable_tgw_attachment: true
    tgw_destination_cidrs: [172.16.0.0/12, 10.0.0.0/8]
  vpcs:
    vpc-1:
      pool: nonprod
      azs: [eu-west-1a, eu-west-1b, eu-west-1c]
      enable_nat_gateway: true
      enable_vpc_endpoints: true
  providers:
    network:                       # only needed for transit-gateway features
      account_id: "<networking account id>"   # role: its Terraform-Role
      state_bucket: <networking account state bucket>
      state_region: eu-west-1      # default
      state_kms_key_id: <key id>   # optional
```

`vpc_defaults` applies to every VPC; an entry in `vpcs` overrides it. Precedence
is module defaults (`locals.tf`) → `vpc_defaults` → the individual VPC.

| Key | Default | Notes |
|---|---|---|
| `enabled` | `true` | The file existing enables the unit; `false` plans a destroy of everything in it |
| `default_vpc` | — | Required once more than one VPC exists |
| `name` | `<name_prefix>-<vpc key>` | Name tag / prefix for that VPC's resources |
| `pool` | — | `nonprod`, `prod` or `infrastructure`: allocate from IPAM (see below) |
| `ipam_pool_id` | — | Pin the pool by ID instead of finding it by description |
| `netmask` | `18` | Size of the VPC, `/17` to `/22` |
| `azs` | — | Exactly 3 |
| `enable_nat_gateway` | `false` | Per-VPC cost — on for the default VPC, usually off elsewhere |
| `single_nat_gateway` | `true` | |
| `enable_vpn_gateway` | `false` | Attaches a VGW to the VPC |
| `tgw_route_table_id` | resolved per region | Override the TGW route table to associate with |
| `tgw_propagation_route_table_id` | resolved per region | Override the table routes propagate into |
| `enable_vpc_endpoints` | `false` | Per-VPC cost: ~15 interface endpoints × AZ. Interface endpoints do not span VPCs |
| `enable_elb_subnet_tags` | `false` | Load balancer subnet discovery tags — see below. Turn on before any load balancer exists in the VPC |
| `endpoint_services` | 15 common services | Includes `s3`, created as a gateway endpoint |

There is no literal `cidr` or subnet list: a VPC carrying `cidr`,
`private_subnets_data`, `private_subnets_platform` or `public_subnets` is
rejected at plan. Addresses come from IPAM only, and IPAM's atomic allocation is
what keeps VPCs from overlapping.

**Cost note.** Endpoints and NAT gateways are billed per VPC and default to off
for that reason. Isolated VPCs created for testing should normally stay lean and
reach shared services over the transit gateway.

## Tests

```bash
terraform init -backend=false && terraform test
```

Mock providers; no AWS access. `ipam_pool_id` in the fixtures stands in for the
pool lookup, whose `id` a mock provider cannot populate.

## VPCs from IPAM

New VPCs do not pick a CIDR. They name a tier and IPAM hands out the next free
block from the pool shared to the account:

```json
"vpcs": {
  "vpc-1": { "pool": "nonprod", "azs": ["eu-west-1a", "eu-west-1b", "eu-west-1c"] }
}
```

- `pool` is the tier. The module finds the pool shared to this account by its
  description, `<tier>/<region>` (e.g. `nonprod/eu-west-1`). An account only
  sees the pools shared to its OU: `workloads/nonprod` sees `nonprod`,
  `workloads/production` sees `prod`, `infrastructure` sees
  `infrastructure`. The pools themselves are managed in `infrastructure/terraform`
  (`aws-mgmt/eu-west-1/ipam`).
- `netmask` defaults to `/18`. The block is claimed first
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
- Routing needs no per-VPC change: each tier is one summary route on the
  transit gateways and Direct Connect (`aws-transit-gateway`).

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

## Transit Gateway architecture

All TGWs live in the networking account and are managed by the
`aws-transit-gateway` repo. This module runs with the workload account's
credentials and reaches into the networking account through two provider
aliases in `providers.tf`, both assuming the networking account's deploy role
(`arn:aws:iam::<spec.providers.network.account_id>:role/Terraform-Role`):

- `aws.network` — networking account, **same region** as the deployment
- `aws.network_dublin` — networking account, pinned to **eu-west-1**

Networking-account facts are read from its remote state:
`spec.providers.network.state_bucket`, key `<region>/terraform.tfstate` — the
read itself assumes the networking role (plain workload credentials get 403 on
that bucket). Enabling a transit-gateway feature without `account_id` and
`state_bucket` fails the plan at the attachment. Outputs are prefixed per region:

| Region | Output prefix | Peering-map key in Dublin's state |
|---|---|---|
| eu-west-1 (Dublin, hub) | `dublin` | — |
| eu-central-1 | `frankfurt` | `frankfurt` |
| sa-east-1 | `sao_paulo` | `saopaulo` (note: no underscore) |
| ap-northeast-2 | `seoul` | absent — resolved from Seoul's own state |

The FortiGate/VPN sits in the Dublin transit-hub VPC (`10.33.96.0/19`,
attachment associated with the Dublin hub route table
`transit-hub-eu-west-1`). Cross-region traffic rides TGW **peering**
attachments, and routes never propagate across peering — both directions need
static routes.

## Config flags (TGW-related)

Set these per VPC — or in `vpc_defaults` when every VPC in the account shares
them, which is the usual case. Defaults come from `vpc_defaults` in the module's
`locals.tf`; note `enable_tgw_propagation` defaults to **false** there.

`tgw_id` and the route-table overrides are resolved per VPC, so one VPC can be
pinned to a different transit gateway without moving the others. `enable_tgw_share`
and `tgw_peering_return_cidrs` drive account/region-level resources: they are
created once if *any* VPC asks for them, and the return CIDRs are deduplicated
across VPCs.

| Flag | Default | Purpose |
|---|---|---|
| `enable_tgw_attachment` | `false` | Attach the VPC to the regional TGW |
| `enable_tgw_association` | `true` | Associate the attachment with the regional hub route table |
| `enable_tgw_propagation` | `false` | Propagate the attachment into the hub route table — **required for the FortiGate (and anything else on the hub RT) to reach this VPC** |
| `enable_tgw_share` | `false` | RAM-share the regional TGW from the networking account to this account (share, resource + principal association via `aws.network`, accepter in the workload account; org-wide RAM auto-accept is NOT enabled). Skip or import first where a manual share already exists |
| `enable_tgw_peering_routes` | `false` | Non-Dublin regions only (no-op in eu-west-1): static route in the **Dublin hub RT** for this VPC's CIDR via the region's peering attachment (`aws.network_dublin`), plus return routes below |
| `tgw_peering_return_cidrs` | `[]` | With peering routes: Dublin-side CIDRs (e.g. `10.33.96.0/19`, the FortiGate/hub VPC) routed back via peering from the regional TGW RT |
| `tgw_destination_cidrs` | `[]` | Routes in this VPC's private route table toward the TGW (typically `10.0.0.0/8`, `172.16.0.0/12`) |
| `tgw_id`, `tgw_route_table_id`, `tgw_propagation_route_table_id` | `null` | Direct overrides; when unset they resolve from the networking remote state |

The peering attachment ID resolves automatically: first from the region's own
state output `<prefix>_tgw_peering_attachment_ids["dublin"]`, then from
Dublin's `dublin_tgw_peering_attachment_ids[<key>]` (see table above). If
neither has it, the plan fails with a precondition — the peering must first be
created in `aws-transit-gateway`.

## Full path: FortiGate/VPN → workload VPC (e.g. EKS)

Same region as the FortiGate (Dublin deployments, e.g. sandbox-2):

1. FortiGate VPC route table has a prefix covering the workload CIDR → TGW
   (`10.32.0.0/16` and others already exist) — manual, in the networking account.
2. Workload attachment associated with the hub RT — `enable_tgw_association`.
3. Hub RT has a route to the workload VPC — **`enable_tgw_propagation`**.
4. Return: workload VPC routes to Dublin ranges — `tgw_destination_cidrs`;
   hub RT already has a static `10.33.96.0/19` route back to the hub VPC.

Other regions (Frankfurt, São Paulo, Seoul) add on top:

5. Dublin hub RT static route: workload CIDR → peering — `enable_tgw_peering_routes`.
6. Regional TGW RT static return route: Dublin CIDRs → peering — `tgw_peering_return_cidrs`.
7. FortiGate VPC route table must still cover the workload CIDR (step 1);
   add it manually if the CIDR is outside the already-routed prefixes.

After routing works, remaining suspects for EKS access are application-layer:
private endpoint access and security-group rules permitting the VPN source
range (usually within `10.33.96.0/19`).

## Troubleshooting

- **403 on `eu-west-1/terraform.tfstate` during plan** — the remote-state read
  is running without the networking-account role; the `assume_role` block in
  `data.tf` must be present (the pipeline's stage role has no direct access to
  the networking state bucket or its KMS key).
- **FortiGate can't reach a VPC whose attachment exists** — check propagation:
  the attachment can be associated with the hub RT yet absent from its
  propagations (`enable_tgw_propagation` unset in the environment JSON falls
  back to the root default of `false`).
- **Peering-route precondition fails** — the region has no Dublin peering
  attachment in either state; create the peering in `aws-transit-gateway`
  first.
- **Duplicate RAM share / route conflicts** — some environments have manually
  created shares and static routes (e.g. the Dublin hub RT's `10.33.96.0/19`);
  import or delete the manual resource before enabling the corresponding flag.

