# cluster

Shared lookup, not a component: every k8s-installs root calls it to find the
EKS cluster its unit targets. It reads infrastructure's state for the same
environment:

| State | Key | Gives |
|---|---|---|
| core-platform | `<env_id>/<region>/core-platform/terraform.tfstate` | cluster name, endpoint, CA, KMS key, VPC, node subnets, node SG, Karpenter facts |
| dns (optional) | `<env_id>/global/dns/terraform.tfstate` | the cluster's zone (`dns_zone`, default `zone-1`) |

A missing core-platform state or an unknown cluster key fails the plan on
`terraform_data.validation` with a message naming both — before any Helm or
Kubernetes provider call (they get a placeholder endpoint meanwhile).
`dns` is `null` when the environment has no dns unit; components that need a
zone check for that themselves.

The helm and kubernetes providers authenticate with `aws eks get-token` per
call (see `_boilerplate`), not a token fetched once: that one expires after 15
minutes, shorter than some Helm waits.

```hcl
module "cluster" {
  source   = "../cluster"
  state    = module.context.state
  env_id   = module.context.env_id
  region   = module.context.region
  cluster  = module.context.config.cluster
  dns_zone = try(module.context.config.dns_zone, "zone-1")
}
```
