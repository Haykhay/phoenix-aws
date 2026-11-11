# ADR-0012: Two pipeline roles, named by Backstage

Status: Accepted · 2026-11-11 · Amends [ADR-0002](0002-one-aws-account-per-group-deploy-roles-known-by-name.md)

## Context

ADR-0002 fixed one deploy role name, `Terraform-Role`, and had the workflow
sign in to each account's role directly over GitHub OIDC. Accounts and their
roles are now created by a pattern outside this repository, and cross-account
work (the networking and DNS accounts) needs a role it can assume from the
pipeline.

## Decision

The pipeline uses **two roles**, both named by Backstage in every unit (from
the account registry: `phoenix/oidc-role-arn`, `phoenix/deploy-role-name`):

- **`oidc_role_arn`**: the role the workflow signs in as over GitHub OIDC.
- **`deploy_role_name`**: the role assumed from it in each account the unit
  touches. It has **one name in every workload account**, so a cross-account
  reference stays an account ID: `arn:aws:iam::<account_id>:role/<deploy_role_name>`.

The S3 backend, every AWS provider, every remote state read and every cluster
login (`aws eks get-token --role-arn`) assume the deploy role. The networking
and management providers assume the deploy role in their own accounts.
`core-platform` makes the deploy role cluster-admin on the clusters it
creates. No role name is set in code; a unit without either fails clearly
(the workflow, and `modules/context` for the deploy role).

## Consequences

- Pull-request plans use the same two roles as applies: there is no separate
  read-only plan role. Anyone who can open a pull request in this repository
  can run a plan with deploy-role rights (forks get no OIDC token). The OIDC
  role's trust policy is where pull-request runs are limited.
- The trust between the two roles (the deploy role trusting the OIDC role) is
  set where the roles are created, not here.
- Running Terraform locally needs credentials that can assume the deploy role.
