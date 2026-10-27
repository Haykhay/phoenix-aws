# peering

One transit gateway peering between two regions, and the static routes on
both sides. Regions form a full mesh: a new region peers with every region
that already has a transit gateway, hubs included (AWS allows 50 peerings per
transit gateway). Never removed automatically (`prevent_destroy`).

## Where this runs

```text
networking/environments/<region>/peering.<peer region>.yaml
state: platform-network/<region>/peering.<peer region>/terraform.tfstate
```

Requested from `<region>`, accepted in `<peer region>` (the file name's
instance); both providers use the networking account. Both regions' `region`
units must be applied first: this unit reads their transit gateways, route
tables and blocks from their state.

## Configuration

```yaml
spec:
  network: { ... }   # the platform settings, see ../../README.md
```

Nothing else: everything comes from the two region states and the settings.

## Routes

Peering propagates nothing. Each side's attachment is associated with its
`shared` table, and each side gets:

| Table | Routes to the other region's |
|---|---|
| `production` | production block |
| `non-production` | non-production block |
| `shared` | production, non-production and shared blocks |

On a peering with the **first hub**, the side that is not the first hub (the
second hub included) also routes, from `production` and `non-production`:

- the first hub's shared block (tooling VPC, hub DNS);
- `onprem_cidrs`: on-prem attaches only to the first hub (with `dual_dx`, one
  Direct Connect gateway carrying both connections).

Losing the first hub's region (two hubs): swap `hub_regions` and re-apply
every peering (see the runbook in [`../../README.md`](../../README.md)).

## Outputs

`attachment_id`; `routes`, the planned keys per side (`<table>/<cidr>`).

## Tests

`terraform test` (mock providers, region states overridden): the route matrix
on both sides, no cross-segment route, association with `shared`, hub routes
whichever side requests, none between two regional transit gateways, the
second hub's routes to tooling and on-prem, and the missing-region check.
