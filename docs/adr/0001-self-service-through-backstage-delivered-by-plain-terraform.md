# ADR-0001: Self-service through Backstage, delivered by plain Terraform

Status: Accepted · 2026-10-25

## Context

The starting point was a Terragrunt monorepo with JSON environment configs, helper scripts and GitLab CI. Environments were created by platform engineers, not requested by the people who use them.

## Decision

Developers, engineers and researchers request environments and workloads in **Backstage**. Backstage writes **one YAML file per unit** (`infrastructure/environments/…`, `k8s-installs/environments/…`) and opens a pull request. **One GitHub Actions workflow** runs **plain Terraform** for each unit: no Terragrunt, no helper scripts. Each Terraform root reads its unit through a shared `context` module. Sandboxes are merged by Backstage; stage, UAT and prod approvals come from Backstage groups.

## Consequences

- The YAML is the audit trail: every environment is a reviewed file.
- Ordering (core-network before core-platform, prerequisites before components) moves to Backstage's orchestrator, which is still to build.
- Contributors need Terraform only; there is no generator layer to learn.
