# hybrid

The AWS side of the connection to the adopter's data centre, per the
platform's `hybrid` setting:

| `hybrid` | Builds | Hubs |
|---|---|---|
| `none` | nothing | 1–2 |
| `vpn` | customer gateway; one site-to-site VPN (two IPsec tunnels, BGP) on the first hub's transit gateway | 1 |
| `dx_vpn` | Direct Connect gateway, a transit virtual interface on the adopter's connection, associated with the first hub; plus the VPN as backup (AWS prefers Direct Connect for equal prefixes) | 1 |
| `dual_dx` | one Direct Connect gateway; a transit virtual interface on each of two connections (one near each hub); the gateway associated with **both** hubs | 2 |

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
    connections:                                              # 1 for dx_vpn, 2 for dual_dx
      - { connection_id: dxcon-..., vlan: 101, bgp_asn: 65010 }   # [i] near hub_regions[i]
      # optional per connection: amazon_address, customer_address, bgp_auth_key
```

The Direct Connect connections are ordered by the adopter; this unit takes
their IDs and creates the virtual interfaces, gateway and associations.

## Prefixes

AWS advertises the three segment summaries (the Direct Connect gateway
association's allowed prefixes); it expects `onprem_cidrs` back over BGP.

**Verify at the first real `dual_dx` apply:** both gateway associations
advertise the same summaries. If AWS rejects overlapping allowed prefixes on
one gateway, advertise each hub's own regional blocks instead.

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
