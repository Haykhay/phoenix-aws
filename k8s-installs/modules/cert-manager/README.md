# cert-manager

[cert-manager](https://cert-manager.io) (chart `v1.20.2`, pinned) with two
Let's Encrypt `ClusterIssuer`s, `letsencrypt-prod` and `letsencrypt-staging`,
solving DNS-01 through Route53 in the cluster's own public and internal zones.
Pod Identity: `cert-manager/cert-manager` → `<name_prefix>-cert-manager`,
allowed to change only those two zones. Part of the **service** set; istio's
wildcard certificates come from it.

| `spec.settings` | Default | |
|---|---|---|
| `acme_email` | none | Let's Encrypt no longer needs an account email |
| `install_crds` | `true` | |
| `hosted_zone_arns` | the cluster's two zones | |
| `enable_gateway_api` | `false` | see below |

`enable_gateway_api` is off: certificates are explicit `Certificate` resources,
and with it on cert-manager will not start until the Gateway API CRDs exist —
which istio installs, after cert-manager. Order: cert-manager →
aws-load-balancer-controller → istio.

The plan fails clearly without the environment's dns unit.
