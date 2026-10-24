# grafana-stack

Each cluster's own observability stack, in namespace `monitoring`. Part of
every cluster's baseline. History goes to the group's long-lived
observability bucket (infrastructure's `observability` unit in
`<group>-shared`), so it survives weekend teardowns.

| Release | Chart (pinned) | Role | Service account |
|---|---|---|---|
| `mimir` | grafana/mimir-distributed 6.2.1 (Mimir 3.2.1) | metrics; chart-default ingest storage with its own Kafka | `mimir` |
| `loki` | grafana/loki 7.3.0 (Loki 3.6.12), single binary | logs | `loki` |
| `tempo` | grafana-community/tempo 3.1.0, single binary | traces | `tempo` |
| `alloy` | grafana/alloy 1.13.1 | collection: annotated pod metrics → Mimir, all pod logs → Loki, OTLP (4317/4318) → Tempo | `alloy` |
| `grafana` | grafana-community/grafana 13.5.0 | Mimir, Loki, Tempo and CloudWatch data sources | `grafana` |

The service accounts are exactly the ones core-platform binds with Pod
Identity (`monitoring/mimir|loki|tempo|grafana`); renaming one breaks AWS
access silently.

## Where data lands

Every object goes under the writer role's only allowed path,
`<signal prefix><cluster name>/` (prefixes from the observability unit's
`signal_prefixes` output):

| Signal | Path | How |
|---|---|---|
| Mimir | `mimir/<cluster>/` | `storage_prefix: mimir` (alphanumeric only), tenant `no_auth_tenant` = cluster name |
| Loki | `loki-<cluster>/` | `storage_prefix` (no slash allowed), Thanos object store client |
| Tempo | `tempo/<cluster>/` | `prefix` |

Mimir's alertmanager and ruler are off (their state would live outside that
path); alert in Grafana. Usage reporting is off.

## Sending signals

| What | Where |
|---|---|
| Prometheus metrics | annotate the pod `prometheus.io/scrape: "true"`; the GPU operator's DCGM exporter (`app=nvidia-dcgm-exporter`) is scraped without it |
| Logs | automatic (every pod) |
| Traces | OTLP to `alloy.monitoring.svc:4317` (gRPC) or `:4318` (HTTP) |

## Spec

| `spec` | Default | |
|---|---|---|
| `observability_environment` | `shared` | the group environment holding the observability unit |
| `chart_versions` | as above | platform-pinned, per release |
| `enabled` | `true` | |

The plan fails clearly if the group's observability unit has not been applied.
