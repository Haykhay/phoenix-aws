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
| `cloud` | no | `aws` (default) or `azure`; anything else fails |
| `organisation`, `group`, `environment` | yes | lowercase identifiers |
| `requester` | no | standalone requests only |
| `tier` | yes | `sandbox`, `stage`, `uat`, `prod` |
| `region` | no | absent = `global` scope |
| `global_region` | no | provider region for global scope, default `us-east-1` (Azure: `westeurope`) |
| `account_id` | AWS | quoted string |
| `state.bucket`, `state.region` | AWS | `state.kms_key_id` optional |
| `subscription_id`, `azure.tenant_id`, `azure.client_id` | Azure | the environment's managed identity; `azure.principal_id` optional |
| `state.resource_group`, `state.storage_account` | Azure | `state.container` optional, default `env_id`; `state.subscription_id` defaults to `subscription_id` |
| `name_prefix` | no | overrides the derived prefix |
| `tags` | yes | `owner.team` and `Reason` required; `LongLive` boolean |
| `spec` | no | the resource set's own settings |

The unit names no role: the workflow signs in to the unit's account as
`Terraform-Role` (or `Terraform-Plan-Role` for a plan), and the providers and
state reads use those credentials as they are (ADR-0013).

## Outputs

| Output | Example |
|---|---|
| `env_id` | `research-sandbox-jdoe` (`<group>-<environment>[-<requester>]`) |
| `scope` / `region` | `eu-west-1` / `eu-west-1`; `global` / `us-east-1` |
| `cloud` | `aws` or `azure` |
| `azure` | `{ tenant_id, client_id, principal_id, subscription_id }`; `null` on AWS |
| `region_code` | `euw1` (AWS, from the direction words), `weu` (Azure, from a fixed map); `null` for global |
| `name_prefix` | `research-sandbox-jdoe-euw1`; `research-sandbox-jdoe` for global |
| `state_key` | `research-sandbox-jdoe/eu-west-1/core-platform/terraform.tfstate` |
| `state` | AWS `{ bucket, region, kms_key_id }`; Azure `{ subscription_id, resource_group, storage_account, container }` |
| `tags` | `Project=Phoenix`, `Organisation`, `Group`, `Requester`, `Environment`, `Tier`, `Scope`, `Region`, `ResourceSet`, `ManagedBy`, plus YAML `tags` |
| `network` | the selected VPC from core-network's `networks` output, or `null` |
| `spec`, `config` | the YAML `spec`, the whole YAML |
| `organisation`, `group`, `requester`, `environment`, `tier`, `account_id` (`null` on Azure), `pipeline_user` | as given |

`network` binds to `spec.vpc` when set, else core-network's `default_vpc_name`.
It is `null` — never an error — when core-network has no state, so a consumer
can still be destroyed after its network is gone. core-network's state is read
from S3 on AWS and from the environment's container (`azurerm`) on Azure.

The state key has the same shape on both clouds.

## Checks

Plan fails when `cloud` is not `aws` or `azure`, `owner.team` or `Reason` is
missing, `LongLive` is not a boolean, an identifier breaks the charset, or the
region has no code. AWS codes come from the region's direction words (add a
word to `directions`); Azure codes from `azure_region_codes` in `main.tf`
(add the region there).

## Tests

```bash
terraform init -backend=false && terraform test
```
