# ADR-0010: Teardown is a normal operation

Status: Accepted · 2026-10-25

## Context

Personal sandboxes are torn down on Friday evenings or when idle; group environments follow a manager-approved schedule.

## Decision

Every unit can be destroyed in reverse dependency order by the same workflow. Nothing blocks a destroy (no `prevent_destroy` on CRDs); history that must survive (observability) lives in account-level units marked `LongLive: true`. Mandatory tags (`owner.team`, `Reason`, `LongLive`) are checked at plan time.

## Consequences

- Backstage's orchestrator owns the schedule, idle detection and reverse ordering (still to build).
- A destroy after a dependency is already gone still plans, rather than failing on missing state.
