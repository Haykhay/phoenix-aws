# dns

Route 53 zones for one account: **one or more** public/internal zone pairs, and
the NS delegation records that hook them into their parent zones.

One AWS account can host several clusters, and each cluster's
external-dns should be scoped to its own zone rather than sharing write access
to a single account-wide. Zones are therefore a **named map**,
the same shape `core-network` uses for VPCs and `core-platform` for clusters.

## Where this runs

```text
environments/<tier>/<env_id>/global/dns.yaml
state: <env_id>/global/dns/terraform.tfstate
```

**Global, not regional.** A hosted zone has no region; a dns YAML that sets
`region` fails the plan.

Global stacks still need a region for the provider to make API calls;
`modules/context` uses `us-east-1`, overridable with `global_region`. Route 53
resources are region-independent, so this affects no resource identity.

## Configuration

Values only, under `spec` in the unit's YAML:

```yaml
spec:
  providers:
    management:                   # delegated admin account holding the parent zones
      account_id: "444444444444"  # only the ID: its role is always Terraform-Role
  zones:
    zone-1:
      public_zone_name: env1.example.com
      internal_zone_name: env1.internal.example.com
    zone-2:
      public_zone_name: env2.example.com
      internal_zone_name: env2.internal.example.com
```

The **management account** is the delegated admin account that owns the parent
zones — not the AWS Organizations management account. Only its ID is given:
the role is always that account's deploy role,
`arn:aws:iam::<account_id>:role/Terraform-Role` (`modules/context`, `role_name`),
assumed from the pipeline's own credentials (provider alias `aws.management`) to
write the delegation record. The plan fails if a zone is delegated without it,
or if the ID is not 12 digits.

| Key | Default | Notes |
|---|---|---|
| `zones` | `{}` | Named map of zone pairs. Keys are lowercase dash-separated, like VPC names |

Per zone:

| Key | Default | Notes |
|---|---|---|
| `public_zone_name` | **required** | Public hosted zone |
| `internal_zone_name` | **required** | Internal zone, delegated from this zone's own public zone. Set it to `public_zone_name` to use one zone for both — see below |
| `parent_zone_name` | the name one label up | Zone in the management account that delegation is written into. Derived; set it only when the immediate parent is not a zone we own |
| `public_zone_exists` | `false` | **Adopt** an existing zone instead of creating one |
| `internal_zone_exists` | `false` | Same, for the internal zone |
| `delegate_public_zone` | `true` | Write the NS record into the parent zone. **Turn off for an apex domain** — it has no parent we own |
| `tags` | `{}` | Ownership tags, layered over the resource set's and the environment's |

**Zone names are explicit, never derived.** A zone does not inherit or extend
another zone's name, so `zones` can hold unrelated domains as easily as
siblings under one parent.

**The delegation parent is derived, not configured.** For a name being
delegated, the zone one label up is the only place its NS record can come
from — `env1.example.com` is delegated from `example.com`, necessarily. Naming both
would allow them to disagree, and an NS record for `env1.example.com` written
into `sandbox.example.com` delegates nothing and fails only at resolution time.
`parent_zone_name` remains available for the one case the derivation cannot
see: an immediate parent that is not itself a hosted zone we own, so
delegation has to come from further up.

An **apex** domain (`example-cx.com`) has no parent we own, so it must set
`delegate_public_zone: false`. Nothing can detect that from the name — the
label count of a registrable domain depends on the public suffix — but
the plan rejects the common single-suffix case (a delegated two-label name with
no `parent_zone_name`).

**On-prem resolution.** The internal zone is a *public* hosted zone delegated
from the public one (its records point at private addresses), so it resolves
from anywhere: on-prem resolvers reach it by normal recursion, or through the
hub's Resolver inbound endpoint (`networking/modules/hub`). There is no VPC
association to make; Route 53 associates only private zones with VPCs.

**One zone for both roles.** An account whose internal records already live in
its public zone (mgmt: internal ALB records in `mgmt.example.com`) sets
`internal_zone_name` to the same name as `public_zone_name`. Nothing is created
or adopted twice, no internal NS record is written (it would be the zone's own
apex NS), and `internal_zone_id`/`internal_zone_name` resolve to the public zone,
so consumers such as the in-cluster external-dns and cert-manager work
unchanged. `public_zone_exists` alone decides create vs. adopt;
the plan rejects an explicit `internal_zone_exists` that disagrees with it.

```yaml
zone-1:
  public_zone_name: mgmt.example.com
  internal_zone_name: mgmt.example.com
  public_zone_exists: true
  delegate_public_zone: false
```

Adopting an existing subdomain zone that is already delegated: set
`delegate_public_zone: false` too, or the module takes over the parent's NS
record — and a later destroy deletes the delegation.

**`*_zone_exists` chooses between creating and adopting.** Flipping it from
`false` to `true` destroys the zone Terraform created — with every record in it —
and replaces it with a data lookup. It is the most destructive flag in the repo;
treat a change here as a migration, not a setting.

## Tests

```bash
terraform init -backend=false && terraform test
```

Mock providers; no AWS access. Covers zone names and delegation, the global-only
check, the management-role, apex and shared-zone checks.

## Outputs

```hcl
zones        # { "<key>" = { public_zone_id, public_zone_name,
             #               internal_zone_id, internal_zone_name } }
zone_names   # every config key

# Deprecated single-zone shims — null once there is more than one zone:
public_zone_id, public_zone_name
internal_zone_id, internal_zone_name
```

`zones` is the contract. The flat outputs are kept so consumers that predate
multiple zones keep working **while there is only one** — the in-cluster repo reads
`public_zone_id`/`internal_zone_id` in external-dns and cert-manager, and the
zone names in keycloak and cloudnative-pg-cluster. New consumers should index
`zones` by name; external-dns already does, via its own `zones` setting.

## Running it

### Before you run it

**Needs:**

- The group's AWS account, its `Terraform-Role` and its state bucket (account vending).
- Delegated zones only: the management account holding the parent zones (`spec.providers.management.account_id`) and its `Terraform-Role`; for an apex domain set `delegate_public_zone: false` instead.

**Access** (the workflow has all of this; locally you need it too):

- Terraform ≥ 1.15.
- Credentials for `Terraform-Role` in the unit's account (account vending creates it), and the account's state bucket.
- Runs on GitHub-hosted runners: it talks to AWS APIs only.

### The unit file

```text
infrastructure/environments/<tier>/<env_id>/global/dns.yaml
state: <env_id>/global/dns/terraform.tfstate
```

The identity block is described in [`../context/README.md`](../context/README.md); `spec` is described above.

### Run it

Through the pipeline: Backstage dispatches `.github/workflows/terraform.yml` with `config_file` set to the unit's path and `action` `plan`, `apply` or `destroy`. Locally:

```bash
cd infrastructure/modules/dns
terraform init -backend-config="bucket=<state bucket>" -backend-config="region=<state region>" \
  -backend-config="key=<env_id>/global/dns/terraform.tfstate" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform plan -var config_file=/path/to/dns.yaml -var pipeline_user=$USER
```

Tests, no AWS needed: `terraform init -backend=false && terraform test` (`dns_zone_names`, `dns_global_only`, `delegation_requires_management_role`, `apex_delegation_rejected`, `shared_zone_exists_mismatch_rejected`, `management_account_id_must_be_valid`).

### Outputs

| Output | |
|---|---|
| `zones` | Every hosted zone pair in this resource set, keyed by its config name. |
| `zone_names` | Config keys of every zone in this resource set. |
| `public_zone_id` | With one zone only: public zone ID. |
| `public_zone_name` | With one zone only: public zone name. |
| `internal_zone_id` | With one zone only: internal (private) zone ID. |
| `internal_zone_name` | With one zone only: internal zone name. |

Plus `resource_summary`, for the pipeline's summary.

### Removing it

Used by: cert-manager, external-dns, istio, argo-cd, kargo, langfuse, vllm (through `modules/cluster`). Destroy those first.
