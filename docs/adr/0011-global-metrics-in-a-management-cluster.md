# ADR-0011: Global metrics in a management cluster

Status: Accepted · 2026-11-10

## Context

Every cluster keeps its own Grafana stack (ADR-0005), so nothing shows GPU
use, inference load or cost across clusters, and later across clouds. No
cluster runs outside the workload accounts.

## Decision

A **management cluster**, an ordinary Phoenix environment built from the
existing modules, runs the global Mimir and Grafana (and hosts Backstage). It
stays self-hosted and cloud-neutral, like ADR-0005.

- **Sending** (`grafana-stack` `global_metrics`): Alloy forwards an allowlist
  of series (GPU use, inference load, gateway traffic, node pools, OpenCost's
  costs) over HTTPS, labelled `cluster`, `env_id`, `tier` and `cloud`. Every
  other series stays in the cluster's own Mimir.
- **Receiving** (`grafana-stack` `global_receiver`): an nginx on the internal
  gateway's TLS listener checks a password file and forwards remote writes,
  and nothing else, to Mimir. Mimir's own gateway stays unauthenticated inside
  the cluster, so its local Alloy, Grafana and OpenCost are unchanged.
- **Credentials** follow ADR-0007: one write credential, stored under each
  environment's prefix (`<organisation>/<env_id>/global-metrics`: `username`
  and `password` where it sends, `htpasswd` where it receives).

## Consequences

- An always-on cluster to run and pay for.
- One tenant: series are told apart by their labels, not by Mimir tenants.
- The credential is copied into each sending environment's prefix when it
  joins (a platform step at go-live), and rotated the same way.
- Other clouds and on-prem reach the receiver only over private paths, so in
  practice after interconnect (Phase 7), unless a public endpoint is approved.
