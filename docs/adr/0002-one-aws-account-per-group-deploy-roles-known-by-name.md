# ADR-0002: One AWS account per group; deploy roles known by name

Status: Accepted · 2026-10-25

## Context

Developers always belong to a group. Backstage has to pass Terraform everything it needs, and the less it has to look up, the fewer things can go wrong.

## Decision

Each group gets **one AWS account**, created by account vending (CloudFormation StackSets, recorded in a DynamoDB account registry). Every account has a deploy role with a **known name**, so the only variable is the account ID: `arn:aws:iam::<account_id>:role/Terraform-Role`. Cross-account references in a unit (management, networking, ECR hub) are account IDs only. Resource names carry the group and, for personal sandboxes, the requester: `<group>-<environment>[-<requester>]-<region code>`.

## Consequences

- Backstage passes account IDs, never role ARNs.
- **Required before the pipeline is connected to AWS:** pull-request plans move to a read-only `Terraform-Plan-Role`; `Terraform-Role` (apply/destroy) is trusted only from `main`. Both names are still known.
- Account vending and the registry are a separate repository, still to build.
