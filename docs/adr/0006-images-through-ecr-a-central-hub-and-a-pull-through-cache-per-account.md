# ADR-0006: Images through ECR: a central hub and a pull-through cache per account

Status: Accepted · 2026-10-25

## Context

Images come from a company Artifactory; ECR's pull-through cache cannot use Artifactory as an upstream.

## Decision

A **central ECR hub** in a tooling account is filled from Artifactory by a scheduled sync. Each group account has an **ECR pull-through cache** from that hub. A **cluster-wide rewrite** of every image to the account's cache (for example a Kyverno mutate policy) is built together with the tooling account.

## Consequences

- Until then, components pull their upstream images.
- Kyverno already reports (Audit) internal images that do not come from the group account's own registry.
