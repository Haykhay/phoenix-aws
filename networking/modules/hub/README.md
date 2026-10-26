# hub

Name resolution between the platform and on-prem, in a hub region: the hub
DNS VPC (networking account, shared segment) with a Route 53 Resolver
**inbound** endpoint (on-prem forwards the platform's zones to it) and, when
`dns_forwarding` is set, an **outbound** endpoint with one forwarding rule
per on-prem domain, shared with the organisation.

Backstage writes this unit for each hub region when `hybrid` or
`dns_forwarding` is set.

## Where this runs

```text
networking/environments/<hub region>/hub.yaml
state: platform-network/<hub region>/hub/terraform.tfstate
```

The hub region's `region` unit must be applied first.

## Configuration

```yaml
spec:
  network: { ... }        # the platform settings: dns_forwarding, onprem_cidrs, share_with
  dns_vpc_netmask: 24     # optional
  dns_azs: [...]          # optional; default the region's first two AZs
```

## What it builds

- DNS VPC: a `/24` from the region's shared pool, two private subnets. Its
  attachment is associated with `shared` and propagates into all three tables;
  its route table sends `address_space` and `onprem_cidrs` to the transit
  gateway.
- Security group: DNS (53/tcp+udp) in and out, to and from `address_space`
  and `onprem_cidrs`.
- Endpoints (an IP in each subnet), forwarding rules, RAM share of the rules.
  core-network associates every rule shared with its account with each VPC it
  creates; the dns unit associates each environment's internal zone with this
  VPC, so on-prem resolves environment names through the inbound endpoint.

Rules are regional: a VPC outside the hub regions cannot use them, so it does
not resolve on-prem domains (an open decision, see the networking design).

## Outputs

`dns_vpc_id`, `dns_vpc_region`, `inbound_endpoint_ips` (give these to the
on-prem DNS team), `resolver_rule_ids` (`{ <domain> = <rule id> }`).

## Tests

`terraform test` (mock provider, region state overridden): endpoints and one
rule per domain with its targets, RAM sharing, the DNS VPC in shared and its
routes, the security group, no outbound side without forwarding, and the
missing-region check.
