# langfuse

[Langfuse](https://langfuse.com) (chart `2.1.4`, Langfuse 4.50.0, pinned) in
`langfuse`: tracing, prompt management and evaluation for the cluster's LLM
workloads. Part of the **model-serving** set.

- **Databases:** the chart's own Postgres and Valkey, and ClickHouse through
  the `clickhouse-operator` unit (required: the chart refuses to install
  without its CRDs). Sandbox-sized.
- **Blob storage:** the group's long-lived observability bucket, under
  `langfuse/<eks cluster name>/{events,media,exports}/` — the only path the
  observability unit's `langfuse` writer role allows. Credentials come from
  core-platform's Pod Identity binding `langfuse/langfuse` (web and worker run
  as that service account); no access keys. Virtual-hosted S3 addressing.
- **Secrets:** salt, encryption key (64 hex), NextAuth secret and the database
  passwords are generated here and kept in state (rotate by tainting).
- **UI:** `https://langfuse-<cluster>.<internal zone>` through istio's internal
  gateway (output `url`). Applications send traces to output `otel_endpoint`.

Needs, applied first: clickhouse-operator, cert-manager, istio, and the group's
observability unit. `spec`: `chart_version`, `observability_environment`
(`shared`), `enabled`.
