# ADR-0007: Secrets live under the environment's prefix only

Status: Accepted · 2026-10-25

## Context

Several components need credentials (databases, Argo CD's deploy key, model tokens), and a cluster must never read another environment's secrets.

## Decision

Every secret a cluster may read lives in Secrets Manager under **`<organisation>/<env_id>/`**. External Secrets Operator's role may read only that prefix in its own account and region, value by value: no `ListSecrets`. Database passwords come from one shared `credentials` module with fixed policies and are published at `<organisation>/<env_id>/<service>/<binding>[/<instance>]`.

## Consequences

- A component needing a secret elsewhere must ask for an explicit override.
- In-cluster databases, Argo CD, Kargo and vLLM all follow the same path rule.
