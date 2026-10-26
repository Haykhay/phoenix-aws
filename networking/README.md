# networking

Layer 1 of Phoenix on AWS: the network every environment sits on. One hub
region (two for dual Direct Connect), and a transit gateway in every other
region from the moment its first environment is requested, peered with every
region that already has one. Production and non-production never reach each
other by any AWS path; the tooling VPC reaches both.

![Networking](docs/architecture/phoenix-networking.png)

Same conventions as [`../infrastructure`](../infrastructure/README.md): plain
Terraform roots in `modules/<unit>`, one YAML per unit written by Backstage,
`infrastructure/modules/context`, the one GitHub workflow, `terraform test`
with mock providers.

## Units

All run in the networking account, as one environment: `group: platform`,
`environment: network`, `tier: prod` (names `platform-network-<region code>-…`).

| Unit | YAML | Creates |
|---|---|---|
| `ipam` | `global/ipam.yaml` | IPAM, a pool per segment, a regional pool per segment per joined region, RAM shares |
| `region` | `<region>/region.yaml` | transit gateway, its three route tables and blackholes; central egress: the egress VPC |
| `peering` | `<region>/peering.<peer>.yaml` | peering attachment and the static routes on both sides |
| `hub` | `<hub region>/hub.yaml` | hub DNS VPC, Route 53 Resolver endpoints, shared forwarding rules |
| `hybrid` | `<first hub>/hybrid.yaml` | VPN and/or Direct Connect to on-prem |

A new region is applied in that order: `ipam` (the region added to
`regions`), `region`, then one `peering` per region that already has a
transit gateway. Then the environment's own units (core-network first).

## Platform settings

Backstage copies the adopter's decisions (`phoenix/platform.yaml` in the
Backstage repository) into `spec.network` of every unit that needs them;
`modules/context` validates them and derives the segments
(`platform_network` output). Terraform never reads the settings file itself.

## State

One bucket in the networking account; keys follow context
(`platform-network/<scope>/<unit>[.<instance>]/terraform.tfstate`):

| Unit | Key |
|---|---|
| ipam | `platform-network/global/ipam/terraform.tfstate` |
| region | `platform-network/<region>/region/terraform.tfstate` |
| peering | `platform-network/<region>/peering.<peer>/terraform.tfstate` |
| hub | `platform-network/<hub region>/hub/terraform.tfstate` |
| hybrid | `platform-network/<first hub>/hybrid/terraform.tfstate` |

Units read each other's outputs from these keys, and core-network reads the
`region` unit's.
