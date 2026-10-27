# hub

Name resolution between the platform and on-prem: a DNS VPC (networking
account, shared segment) with, in hub regions, a Route 53 Resolver
**inbound** endpoint (on-prem forwards the platform's names to it) and, when
`dns_forwarding` is set, an **outbound** endpoint with one forwarding rule
per on-prem domain, shared with the organisation.

Backstage writes this unit for each hub region when `hybrid` or
`dns_forwarding` is set, and for **every other region** when
`dns_forwarding` is set. Resolver rules are regional (a rule shared through
RAM reaches other accounts in its own region only), so each region forwards
through its own outbound endpoint and shares its own rules; outside the hubs
there is no inbound endpoint. Each such region costs two endpoint interfaces
(about $180 a month at list price).

## Where this runs

```text
networking/environments/<region>/hub.yaml
state: platform-network/<region>/hub/terraform.tfstate
```

The region's `region` unit must be applied first. Outside the hub regions the
plan fails without `dns_forwarding`: there would be nothing to build.

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
- Endpoints (an IP in each subnet; inbound in hub regions only), forwarding
  rules, RAM share of the rules.
  core-network associates every rule shared with its account with each VPC it
  creates. The environments' internal zones are public, so the inbound
  endpoint resolves them like any other name.

Every region that runs this unit has its own rules, so VPCs in every region
resolve the on-prem domains.

## Outputs

`dns_vpc_id`, `dns_vpc_region`, `inbound_endpoint_ips` (give these to the
on-prem DNS team), `resolver_rule_ids` (`{ <domain> = <rule id> }`).

## Tests

`terraform test` (mock provider, region state overridden): endpoints and one
rule per domain with its targets, RAM sharing, the DNS VPC in shared and its
routes, the security group, no outbound side without forwarding, and the
missing-region check.
