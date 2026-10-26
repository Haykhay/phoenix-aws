# ipam

The platform's address plan. One IPAM in the networking account, a top pool
per segment (production, non-production, shared, each one summary block), and
a **regional pool** per segment per joined region, shared with the
organisation through RAM. core-network allocates every VPC from the regional
pool of its segment.

## Where this runs

```text
networking/environments/global/ipam.yaml
state: platform-network/global/ipam/terraform.tfstate
```

Global scope; the provider talks to IPAM's home region, the YAML's
`global_region` (the first hub).

## Configuration

```yaml
global_region: eu-west-1          # IPAM home region = hub_regions[0]
spec:
  regions: [eu-west-1, eu-central-1]   # every region that has joined; Backstage appends
  network: { ... }                     # the platform settings, see ../../README.md
```

`regions` must include the home region. A region is added by appending it;
**never remove one**: the regional pool CIDRs are `prevent_destroy`, so a
removal fails the apply rather than freeing a block that routes, firewalls and
on-prem still point at.

Regional pools are described `<segment>/<region>`, hold one `region_netmask`
block (the first free one in the segment) and hand out `/17`–`/22`.

## Before the first apply

From the management account, once: delegate IPAM administration to the
networking account and enable RAM sharing with the organisation (see the
first-time setup in [`../../README.md`](../../README.md)).

## Outputs

| Output | |
|---|---|
| `ipam_id` | IPAM ID |
| `segments` | `{ production, non-production, shared }` blocks |
| `regional_blocks` | `{ <region> = { <segment> = <cidr> } }` |
| `regional_pool_ids` | `{ <region> = { <segment> = <pool id> } }` |

## Tests

`terraform test` (mock provider): segment pools, three regional pools of
`region_netmask` per region, operating regions, RAM sharing, and the home
region check. `prevent_destroy` cannot be exercised by a plan against mocks;
it is checked by review.
