# kargo

[Kargo](https://kargo.io) (chart `1.11.2`, pinned) for promoting versions
between stages, with Argo CD doing the syncing. Part of the **delivery** set.
One Kargo per environment:

| Cluster | Mode | Runs |
|---|---|---|
| `spec.management_cluster` (default `"1"`) | **management** | API + UI, management controller, garbage collector, a shard controller, Pod Identity for ECR warehouse scans |
| every other cluster of the environment | **spoke** | a shard controller (`<env_id>-<cluster>`) watching the management cluster's Kargo resources |

The mode follows from the unit's `cluster`; nothing else to configure.

**How a spoke reaches the management cluster** (same environment = same
account; same VPC assumed):

1. The management unit creates a `kargo-spoke-agent` service account, binds it
   to Kargo's controller roles, and publishes a kubeconfig with a rotating
   (300-day) token at `<organisation>/<env_id>/kargo/remote-kubeconfig`
   (output `remote_kubeconfig_secret`).
2. A spoke reads that output from the management unit's state
   (`<env_id>/<region>/k8s/<management cluster>/kargo`) — planning a spoke
   before its management cluster fails with a clear message — mounts the
   kubeconfig, and opens the management cluster's API (security group rule,
   443) to **its own node security group only**.

**UI:** `https://kargo.<internal zone>`, an HTTPRoute on istio's internal
gateway. Admin password and token-signing key at
`<organisation>/<env_id>/kargo/admin`. Deep links to each cluster's Argo CD
(`settings.argocd_urls` adds others).

Needs, applied first: argo-cd, cert-manager (Kargo's webhook certificates),
istio (management route). Promotion across environments (sandbox → stage →
prod) is a separate design.
