# region

A region's network hub, in the networking account: its transit gateway, the
three segment route tables, and, in central egress mode, the egress VPC. The
first environment requested in a region creates this; it is never removed
automatically (`prevent_destroy` on the transit gateway).

## Where this runs

```text
networking/environments/<region>/region.yaml
state: platform-network/<region>/region/terraform.tfstate
```

The region must have joined IPAM first (in `ipam.yaml` `regions`, applied):
this unit reads its blocks and pools from the ipam state, and fails the plan
with that instruction if they are missing.

## Configuration

```yaml
spec:
  network: { ... }            # the platform settings, see ../../README.md
  amazon_side_asn: 64512      # optional; give each hub its own with dual_dx
  egress_vpc_netmask: 24      # optional, central mode
  egress_azs: [...]           # optional; default the region's first three AZs
```

## Route tables

Default association and propagation are off and shared attachments are
auto-accepted: every association and propagation is made explicitly by the
unit that owns the attachment (core-network, hub, hybrid, peering).

| Table | Always | Central mode |
|---|---|---|
| `production` | blackhole: the non-production segment; blackhole: `address_space` | `0.0.0.0/0` → egress |
| `non-production` | blackhole: the production segment; blackhole: `address_space` | `0.0.0.0/0` → egress |
| `shared` | blackhole: `address_space` | `0.0.0.0/0` → egress |

The `address_space` blackhole drops traffic to private space nothing owns yet
(the reserved block, a region not peered yet). Every real destination has a
more specific route, propagated or static, that wins over it. Without it, central
mode would loop such a packet between the transit gateway and the egress VPC.

`shared` carries the default route too: the tooling VPC sits there, and in
central mode it has no NAT of its own.

## Central egress VPC

A `/24` from the region's shared pool: public subnets (`/26`) with one NAT
gateway per AZ, attachment subnets (`/28`) whose default route is the NAT.
The attachment is associated with `shared` and never propagated; the public
route table sends `address_space` back to the transit gateway.

## Outputs

`transit_gateway_id`, `transit_gateway_arn`, `amazon_side_asn`,
`route_table_ids` (per segment), `blocks` and `pool_ids` (this region's, per
segment), `egress_mode`, `egress_attachment_id` (null when independent).

## Tests

`terraform test` (mock provider, ipam state overridden): explicit transit
gateway settings, three tables, cross-segment and `address_space` blackholes,
central default routes and egress VPC, none of it in independent mode, and
the not-joined check.
