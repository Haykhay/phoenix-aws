# Modules

Each module is a self-contained Terraform root that deploys one Helm chart (or a small cluster of related charts) to EKS. Modules are grouped by function; the group name maps directly to the group JSON file in `config/environments/<env>/`.

## Module reference

| Module | Group | Helm Repository | Default Chart Version | Namespace | IAM | Notes |
|---|---|---|---|---|---|---|
| cluster-config | core | — (local chart) | — | kube-system | None | Cluster-wide config that must exist before any other module. Currently installs the `gp3` StorageClass. `stacks/common.hcl` declares a dependency on this stack so Terragrunt always applies it first |
| groundcover-sensor | core | https://helm.groundcover.com | 1.11.86 | groundcover | None | Mints a fresh per-account ingestion key via the `groundcover` Terraform provider (Vault-authenticated, `secret/sre` → `groundcover_token`) and injects it directly into the sensor's `helm_release` via `set_sensitive`. `stacks/groundcover-sensor.hcl` generates the `vault` + `groundcover` providers; `vault_addr`/`vault_token` are populated from `VAULT_ADDR`/`VAULT_TOKEN` env vars in CI |
| traefik | network | https://traefik.github.io/charts | 40.3.0 (app v3.7.4) | traefik | None | Two independent releases — `traefik-internal` and `traefik-external` — each with `service.type: LoadBalancer` (NLB on AWS via aws-lb-controller, MetalLB IP on-prem) and its own `IngressClass`. Bundled `traefik-extras` chart deploys cert-manager wildcard Certificates + TLSStore so all Ingresses get HTTPS with no `spec.tls` entries. Optional ALB mode via `settings.alb.enabled: true` |
| aws-load-balancer-controller | network | https://aws.github.io/eks-charts | 3.4.0 | kube-system | Pod Identity — official `AWSLoadBalancerControllerIAMPolicy` | Also installs upstream Gateway API CRDs + AWS's own Gateway CRDs (`LoadBalancerConfiguration`, `TargetGroupConfiguration`, `ListenerRuleConfiguration`) via a bundled `bedag/raw` chart |
| external-dns | network | https://kubernetes-sigs.github.io/external-dns/ | 1.21.1 | external-dns | Pod Identity — Route53 list/change, scoped to public+internal zones | Sources: `ingress`, `gateway-httproute`, filtered by `external-dns.alpha.kubernetes.io/hostname` annotation |
| cloudflare | network | — (pure Terraform, no Helm) | — | — | None | `cloudflare_zone` data lookup by `settings.zone_name`, plus `cloudflare_dns_record` and `cloudflare_zone_setting` (SSL mode). See [Cloudflare details](#cloudflare) below |
| istio | network | https://istio-release.storage.googleapis.com/charts | 1.30.1 | istio-system | None | Minimal install: `base` + `istiod` only — no `istio-ingressgateway` chart, no sidecar injection anywhere. Gateway API auto-provisions a dedicated Envoy `Deployment`+`Service` per `Gateway` object |
| cloudnative-pg | data | https://cloudnative-pg.github.io/charts | 0.29.0 (operator 1.30.0) | cnpg-system | None | CloudNativePG operator. Sets `OPERATOR_IMAGE_NAME` and `POSTGRES_IMAGE_NAME` in the operator ConfigMap to ECR pull-through URLs so k8s-image-swapper's image rewrites don't restart pods. `pg_image_tag` in config controls the default PostgreSQL image tag |
| cloudnative-pg-cluster | data | — (local chart) | — | cnpg-system | Pod Identity — SecretsManager write | Provisions one or more CloudNativePG `Cluster` CRs. See [modules/cloudnative-pg-cluster/README.md](cloudnative-pg-cluster/README.md) |
| valkey-redis | data | https://valkey-io.github.io/valkey-helm/ | 0.4.1 (operator v0.4.0) | valkey-operator | None | Valkey Redis operator. Required by `valkey-redis-cluster` |
| valkey-redis-cluster | data | — (local chart) | — | valkey-operator | Pod Identity — SecretsManager write | Provisions one or more Valkey Redis `ValkeyCluster` CRs. See [modules/valkey-redis-cluster/README.md](valkey-redis-cluster/README.md) |
| strimzi-kafka | data | https://strimzi.io/charts/ | 1.1.0 | strimzi-operator | None | Strimzi Kafka operator. Required by `strimzi-kafka-cluster` |
| strimzi-kafka-cluster | data | — (local chart) | — | strimzi-operator | None | Provisions one or more Strimzi Kafka clusters in KRaft mode. See [modules/strimzi-kafka-cluster/README.md](strimzi-kafka-cluster/README.md) |
| cert-manager | security | https://charts.jetstack.io | v1.20.2 | cert-manager | Pod Identity — Route53 DNS01 challenges | Gateway API support enabled. Bundles two `bedag/raw` charts — see [cert-manager details](#cert-manager) below |
| external-secrets | security | https://charts.external-secrets.io | 2.6.0 | external-secrets | Pod Identity — SecretsManager + SSM read, optional KMS decrypt | |
| kyverno | security | https://kyverno.github.io/kyverno/ | 3.8.1 | kyverno | None | Installs Kyverno and a module-owned policies chart. Policies default to `Audit`; promote to `Enforce` via `settings.policy_mode`. Image controls configured with `managed_image_patterns` and `allowed_image_patterns`. Excludes the `k8s-image-swapper` namespace to prevent infinite image-rewrite loops |
| falco | security | https://falcosecurity.github.io/charts | 0.3.1 (operator 0.4.1) | falco-operator | None | Falco runtime security via the falco-operator. Three Helm releases in dependency order: operator + CRDs, artifact CRs, then the `Falco` instance CR. See [modules/falco/README.md](falco/README.md) |
| keycloak-operator | security | — (local chart) | — | keycloak | None | Installs the official Keycloak Operator with vendored manifests pinned at `operator_version` (currently 26.6.3). Bumping `operator_version` means re-vendoring `manifests/operator/templates/` — see note in module. Required by `keycloak` |
| keycloak | security | — (local chart) | — | keycloak | None | Provisions the `Keycloak` CR, its DB credentials Secret, and internal + external + Cloudflare-fronted Ingresses. See [modules/keycloak/README.md](keycloak/README.md) |
| cluster-autoscaler | tools | https://kubernetes.github.io/autoscaler | 9.57.0 | kube-system | Pod Identity — EC2/ASG describe + scale | Scale actions gated by `k8s.io/cluster-autoscaler/<cluster>=owned` tag |
| reloader | tools | https://stakater.github.io/stakater-charts | 2.2.12 | reloader | None | Stakater Reloader. Use `settings.auto_reload_all` or `settings.values` for chart overrides |
| k8s-image-swapper | tools | https://estahn.github.io/charts/ | 1.11.0 (app 1.6.5) | k8s-image-swapper | Pod Identity — ECR create/push/pull for image cache repositories | Mirrors images into ECR. Uses cert-manager for webhook TLS by default. Note: `chart_version: 1.11.0` defaults to app image `1.5.10` — this module overrides it to `1.6.5` to meet EKS Pod Identity minimum SDK requirement |
| argo-cd | delivery | https://argoproj.github.io/argo-helm | 7.9.1 (app v2.14.x) | argocd | Pod Identity — ECR pull (repo-server) | One ArgoCD per cluster. Admin password and repo SSH key are self-provisioned by the module on first apply (stored in Secrets Manager). `settings.url` sets the ingress hostname; `settings.repo_url` sets the gitops repo. `application.resourceTrackingMethod: annotation` is set for Kargo compatibility |
| kargo | delivery | https://charts.kargo.io | 1.11.2 (app v1.11.2) | kargo | SecretsManager read (spoke: management kubeconfig); SecretsManager write + EC2 SG (management: credentials + spoke registration) | Runs in **management** or **spoke** mode, derived automatically from `stacks/kargo.hcl`. See [modules/kargo/README.md](kargo/README.md) for full topology docs |

## Module details

### Cloudflare

- The zone itself is not Terraform-managed — domain **registration** (Cloudflare as registrar) is a dashboard-only purchase flow. Register the domain first; Cloudflare auto-provisions the zone. Only then does `data.cloudflare_zone` resolve — keep `enabled: false` in the config until that's done, since `run-all` would otherwise fail environment-wide on a missing zone
- `cloudflare_dns_record` — one per entry in `settings.dns_records` (`name`/`type`/`content`/`proxied`/`ttl`/`comment`). `ttl` is forced to `1` ("automatic") whenever `proxied: true`
- `cloudflare_zone_setting` for `settings.ssl_mode` (default `full`). Use `strict` only when the origin's own cert actually covers the proxied hostname — records here typically front an origin under a different domain, so the origin cert SANs never match and `strict` returns a Cloudflare 526
- Cloudflare preserves the client's original Host header when proxying, so the origin needs a matching routing rule per Cloudflare-fronted hostname. The clean fix (an Origin Rule rewriting the Host header) requires a paid plan — until upgraded, add the Cloudflare-fronted hostname directly to the origin's routing rules
- `stacks/cloudflare.hcl` generates the `cloudflare` provider; `cloudflare_api_token` is populated from the `CLOUDFLARE_API_TOKEN` CI/CD variable

### cert-manager

One bundled chart is included:

- `cluster-issuers` — one `ClusterIssuer` per ACME server (`letsencrypt-prod`, `letsencrypt-staging`), each with two DNS-01 solvers (public zone + internal zone, selected via `dnsZones`)

### kyverno + k8s-image-swapper

Configure them separately in the relevant group file:

```json
"kyverno": {
  "enabled": true,
  "chart_version": "3.8.1",
  "settings": {
    "policy_mode": "Audit",
    "managed_image_patterns": ["*.dkr.ecr.*.amazonaws.com/apps/*"],
    "allowed_image_patterns": ["*.dkr.ecr.*.amazonaws.com/apps/sandbox/*"]
  }
},
"k8s-image-swapper": {
  "enabled": true,
  "chart_version": "1.11.0"
}
```

Promote policies from `Audit` to `Enforce` by setting `settings.policy_mode`. `k8s-image-swapper` uses cert-manager for webhook TLS by default — set `settings.patch_enabled: true` only if cert-manager is unavailable.
