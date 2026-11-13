# ADR-0013: Sign in to the account baseline's roles; one account per job

Status: Accepted · 2026-11-13 · Supersedes [ADR-0012](0012-two-pipeline-roles-named-by-backstage.md)

## Context

ADR-0012 had the pipeline sign in as an OIDC role named in the unit
(`oidc_role_arn`) and then assume a deploy role (`deploy_role_name`) in every
account the unit touched. `phoenix-aws-org` now vends every account with two
baseline roles that trust GitHub OIDC directly:

- `Terraform-Role`: trusts `repo:<repo>:ref:refs/heads/main`;
- `Terraform-Plan-Role`: trusts `repo:<repo>:pull_request`.

Neither trusts another account's role, so there is no hop to make.

## Decision

- A pull-request plan signs in to the unit's account as `Terraform-Plan-Role`.
  Apply and destroy, dispatched from `main`, sign in as `Terraform-Role`. The
  workflow builds the ARN from the unit's `account_id`; the unit names no role.
- The backend, every provider, every state read and every cluster login
  (`aws eks get-token`, through `module.cluster.exec`) use those credentials as
  they are.
- `core-platform` makes `Terraform-Role` cluster-admin and gives
  `Terraform-Plan-Role` `AmazonEKSAdminViewPolicy` (read everything, Helm's
  release secrets included, change nothing).
- A unit writes only into its own account. Steps in another account are the
  orchestrator's, from the unit's outputs:
  - `core-network` creates the transit gateway attachment; `tgw_links` gives the
    table to associate and the tables to propagate into, for the networking
    account to apply;
  - `dns` creates the zones; `delegations` gives the NS record for the parent
    zone's account to add.
- Reads across accounts (the networking state, the ECR hub) stay; the owning
  account's bucket or registry policy grants them.

## Consequences

- Unit YAML loses `oidc_role_arn` and `deploy_role_name`.
- Dispatched runs only start from `main`; a branch is planned through its
  pull request.
- Segment isolation is still decided and tested in `core-network`, but applied
  by the networking account.
