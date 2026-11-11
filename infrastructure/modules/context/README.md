# context

Child module every resource-set root calls first. It reads the unit's YAML
(`environments/<tier>/<env_id>/<scope>/<resource-set>.yaml`, written by
Backstage) and returns everything a root needs to know about where it is and
what it is called, so no root builds a name, a tag set or a state key itself.

```hcl
module "context" {
  source        = "../context"
  config_file   = var.config_file
  resource_set  = "core-platform"
  network       = true            # VPC-bound sets only
  pipeline_user = var.pipeline_user
}
```

## YAML fields it reads

| Field | Required | Notes |
|---|---|---|
| `organisation`, `group`, `environment` | yes | lowercase identifiers |
| `requester` | no | standalone requests only |
| `tier` | yes | `sandbox`, `stage`, `uat`, `prod` |
| `region` | no | absent = `global` scope |
| `global_region` | no | provider region for global scope, default `us-east-1` |
| `account_id` | yes | quoted string |
| `state.bucket`, `state.region` | yes | `state.kms_key_id` optional |
| `name_prefix` | no | overrides the derived prefix |
| `tags` | yes | `owner.team` and `Reason` required; `LongLive` boolean |
| `spec` | no | the resource set's own settings |

The deploy role is named in the unit (`deploy_role_name`, written by Backstage
from the account registry; required): one name in every workload account, so a
cross-account reference is just an account ID and the ARN is
`arn:aws:iam::<account id>:role/<deploy_role_name>` (ADR-0012). The plan fails
if it is missing or not an IAM role name. `oidc_role_arn`, the role the
pipeline signs in as, is read by the workflow, not here.

## Outputs

| Output | Example |
|---|---|
| `env_id` | `research-sandbox-jdoe` (`<group>-<environment>[-<requester>]`) |
| `scope` / `region` | `eu-west-1` / `eu-west-1`; `global` / `us-east-1` |
| `region_code` | `euw1`; `null` for global |
| `name_prefix` | `research-sandbox-jdoe-euw1`; `research-sandbox-jdoe` for global |
| `state_key` | `research-sandbox-jdoe/eu-west-1/core-platform/terraform.tfstate` |
| `state` | `{ bucket, region, kms_key_id }` |
| `tags` | `Project=Phoenix`, `Organisation`, `Group`, `Requester`, `Environment`, `Tier`, `Scope`, `Region`, `ResourceSet`, `ManagedBy`, plus YAML `tags` |
| `network` | the selected VPC from core-network's `networks` output, or `null` |
| `spec`, `config` | the YAML `spec`, the whole YAML |
| `role_name` | `deploy_role_name`: the deploy role's name in every account |
| `deploy_role_arn` | the deploy role in the unit's account; the backend, providers and state reads assume it |
| `organisation`, `group`, `requester`, `environment`, `tier`, `account_id`, `pipeline_user` | as given |

`network` binds to `spec.vpc` when set, else core-network's `default_vpc_name`.
It is `null` — never an error — when core-network has no state, so a consumer
can still be destroyed after its network is gone.

## Checks

Plan fails when `owner.team` or `Reason` is missing, `LongLive` is not a
boolean, an identifier breaks the charset, or the region has no code. Add a
region by adding it to `region_codes` in `main.tf`.

## Tests

```bash
terraform init -backend=false && terraform test
```
