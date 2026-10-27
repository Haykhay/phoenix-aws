# hybrid

The AWS side of the connection to the adopter's data centre, per the
platform's `hybrid` setting:

| `hybrid` | Builds | Hubs |
|---|---|---|
| `none` | nothing | 1–2 |
| `vpn` | customer gateway; one site-to-site VPN (two IPsec tunnels, BGP) on the first hub's transit gateway | 1 |
| `dx_vpn` | Direct Connect gateway, a transit virtual interface on the adopter's connection, associated with the first hub; plus the VPN as backup (AWS prefers Direct Connect for equal prefixes) | 1 |
| `dual_dx` | per hub: a Direct Connect gateway, a transit virtual interface on the connection near that hub, and the gateway's association with that hub | 2 |

Every on-prem attachment sits in the hub's `shared` table and propagates into
all three, so on-prem reaches both segments and both reach on-prem. Which
on-prem networks may talk to which segment is the adopter's edge firewall:
documented, not enforced here.

## Where this runs

```text
networking/environments/<first hub>/hybrid.yaml
state: platform-network/<first hub>/hybrid/terraform.tfstate
```

The hub regions' `region` units must be applied first. With `dual_dx` a second
provider works in `hub_regions[1]`.

## Configuration

```yaml
spec:
  network: { ... }                     # the platform settings (hybrid, onprem_cidrs)
  hybrid_settings:
    customer_gateway: { ip: 203.0.113.10, bgp_asn: 65010 }   # vpn, dx_vpn
    dx_gateway_asn: 64600                                     # dx_vpn, dual_dx
    second_dx_gateway_asn: 64601                              # dual_dx, optional (default dx_gateway_asn)
    connections:                                              # 1 for dx_vpn, 2 for dual_dx
      - { connection_id: dxcon-..., vlan: 101, bgp_asn: 65010 }   # [i] near hub_regions[i]
      # optional per connection: amazon_address, customer_address, bgp_auth_key
```

The Direct Connect connections are ordered by the adopter; this unit takes
their IDs and creates the virtual interfaces, gateway and associations.

## Prefixes and preference

AWS advertises the three segment summaries (each Direct Connect gateway
association's allowed prefixes); it expects `onprem_cidrs` back over BGP.

With `dual_dx` the two connections land on different transit gateways
through different Direct Connect gateways, so both advertise the same
summaries without overlapping within a gateway.

**Paths are fixed by region on the AWS side.** Transit gateway peering
propagates nothing, so:

| Traffic from | To on-prem over |
|---|---|
| the second hub's region | the second hub's connection (learned over BGP) |
| every other region, the first hub's included | the first hub's connection (static route through the peering with the first hub) |

AS_PATH prepending and local preference on the on-prem side decide which
connection on-prem *sends* over, and AWS honours them, but they cannot move
the AWS→on-prem paths above: each transit gateway sees only its own
connection. For symmetric flows (stateful on-prem firewalls), on-prem should
prefer the first hub's connection for everything except the second hub's
regional blocks, and prepend on the other; or keep its edge stateless across
both connections.

**Failover.** On-prem→AWS fails over by BGP on its own. AWS→on-prem does not:
if the first hub's connection is lost, every region but the second hub loses
on-prem until the hubs are swapped (runbook in
[`../../README.md`](../../README.md)). Automatic AWS-side failover would need
dynamic routing between regions (AWS Cloud WAN), a non-goal.

## Handoff to the on-prem team

```sh
terraform output onprem
```

Tunnel outside addresses and inside addresses, AWS-side ASNs, the Direct
Connect gateway and virtual interfaces, and the prefixes advertised and
expected. Pre-shared keys are not output: read them from the VPN connection's
configuration in the networking account.

## Tests

`terraform test` (mock providers, hub region states overridden): each pattern
plans only its own resources, the attachments in `shared` with propagation
into all three tables, the allowed prefixes, both hubs under `dual_dx`, the
settings checks, and nothing under `none`. `dual_dx` with one hub is rejected
by `modules/context` (tested there).
