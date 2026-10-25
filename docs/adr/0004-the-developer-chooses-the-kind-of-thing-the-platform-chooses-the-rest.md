# ADR-0004: The developer chooses the kind of thing; the platform chooses the rest

Status: Accepted · 2026-10-25

## Context

People asking for environments should not need to know what cert-manager or Karpenter are, or pick chart versions and sizes.

## Decision

The workload form asks only for a **workload type** (service, model serving), a **database type**, a **GPU type** and a **model**. Each option is a **Backstage catalog entity** that lists every component it needs; components list their direct prerequisites (`dependsOn`), which give the install order. Versions and sizes are module defaults. Adding a workload type, database, GPU or model means adding catalog data, not changing the form.

## Consequences

- An offline check keeps each option's list closed under the prerequisites and the graph free of cycles.
- GPU capacity is a Karpenter node pool per GPU type (`karpenter-nodepool.<gpu>`), not managed GPU node groups.
- Sandbox databases run in the cluster (operators); stage and above use managed RDS, ElastiCache and MSK.
