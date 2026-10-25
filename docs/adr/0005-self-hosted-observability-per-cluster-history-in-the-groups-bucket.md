# ADR-0005: Self-hosted observability per cluster, history in the group's bucket

Status: Accepted · 2026-10-25

## Context

Clusters are torn down at weekends; their telemetry history should not be. GPU and LLM workloads need metrics, logs, traces and LLM tracing.

## Decision

Every cluster runs its own **Grafana stack** (Mimir, Loki, Tempo, Alloy, Grafana) and, for model serving, **Langfuse**. Data goes to the group's **long-lived observability bucket**, one path per cluster and signal, enforced by IAM on the Pod Identity session tag: `mimir/<cluster>/`, `loki-<cluster>/`, `tempo/<cluster>/`, `langfuse/<cluster>/`. Mimir runs its chart's default architecture (ingest storage with its own Kafka).

## Consequences

- Loki's prefix is `loki-<cluster>/` because Loki's storage prefix cannot contain a slash.
- Mimir's alertmanager and ruler are off (their state would sit outside the cluster's path); alerting is in Grafana.
- Kafka makes Mimir heavier per cluster; chosen over overriding the chart's built-in configuration.
