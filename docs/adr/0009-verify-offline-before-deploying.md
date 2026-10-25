# ADR-0009: Verify offline before deploying

Status: Accepted · 2026-10-25

## Context

Nothing has been applied to a real account yet, and a mistake in a chart value or a custom resource only shows at deploy time.

## Decision

Every Terraform root has **`terraform test`** suites against mock providers. Every chart is **rendered with real Helm** from the generated values, and custom resources are validated with **`kubeconform -strict`** against published or vendored schemas. The Backstage forms are **dry-run** through Backstage's API, and every file they generate passes the workflow's path checks and a `terraform plan`.

## Consequences

- Rendering caught bugs unit tests could not, for example external-dns never filtering zones, an invalid `ECRAuthorizationToken` field, and Langfuse's ClickHouse operator prerequisite.
- Runtime behaviour (scheduling, GPUs, real AWS permissions) is verified when the platform goes live.
