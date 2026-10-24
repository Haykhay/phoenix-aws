# credentials

One implementation of password generation for every backing service, managed
and in-cluster, shared by Layer 2 (`infrastructure`) and Layer 3
(`k8s-installs`).

Unlike every other module in this repo, this is **not a resource set**. No
YAML unit ever names it and the workflow never runs it on its own. It is a
library module, consumed from inside other modules.

## Why it exists

Before this module, five places generated passwords with three different
policies and five incompatible secret names:

| Site | Length | Specials |
|---|---|---|
| `data-rds` | 20 | `!#$%&*()-_=+[]{}<>:?` |
| `data-elasticache` | 32 | `!&#$^<>-` |
| `cloudnative-pg-cluster` | 32 | none |
| `valkey-redis-cluster` | 32 | none |
| `data-msk` | — | no credential at all (IAM SASL) |

A policy fix had to be made in two repos and four modules, and
the secret path convention's
discovery path was implemented in none of them.

## Consuming it

A library, not a resource set: no stack sources it directly. Modules in this
repo reference it by relative path:

```hcl
module "credentials" {
  source = "../credentials"

  organisation = local.organisation   # from module.context

  credentials = {
    for name, instance in local.instances : name => {
      policy   = "rds_master"
      username = instance.username
    }
  }
}
```

The workflow checks out the whole repo at the unit's `module_ref` — `main` for
sandboxes, a release tag for stage/UAT/prod — so `../credentials` always
resolves to the copy released alongside the consumer. There is no separate
version to bump.

A consumer outside this repo pins a release tag instead:
`git::https://github.com/<owner>/infrastructure.git//modules/credentials?ref=v<version>`.

## Policies

| Policy | Length | Charset | For |
|---|---|---|---|
| `rds_master` | 30 | `[A-Za-z0-9]` | RDS master passwords |
| `rds_app` | 30 | `[A-Za-z0-9]` | RDS application users |
| `elasticache_auth` | 30 | `[A-Za-z0-9]` | ElastiCache AUTH tokens |
| `msk_scram` | 30 | `[A-Za-z0-9]` | MSK SASL/SCRAM users |
| `postgres_incluster` | 30 | `[A-Za-z0-9]` | Layer 3 Postgres |
| `redis_incluster` | 30 | `[A-Za-z0-9]` | Layer 3 Redis |
| `generic` | 30 | `[A-Za-z0-9]` | anything else |

All carry `min_upper`, `min_lower` and `min_numeric` of 1.

**No punctuation, length instead.**  RDS rejecting `/ @ "` and space, 
ElastiCache allowing only eight specials, MSK storing credentials as JSON, 
in-cluster backings pasting the password into a connection URI, is a property 
of the punctuation, not of the password. Removing it kills all of them at once, 
and the length pays for it several times over: 30 alphanumeric characters is a 
search space of about 10⁵³, against roughly 10³⁸ for 20 mixed characters.

The keys hold identical values today. They stay separate so each can change
without dragging the others along.

**`policies` is append-only.** `random_password` regenerates whenever any
argument changes, so editing a policy in place rotates every password using it,
everywhere, on the next apply. To change one, add a new key — `rds_master_v2` —
and move consumers onto it individually. That bump *is* the rotation trigger,
and it shows up in review.

## There is no compatibility mode

A password either meets the standard or it does not. The module offers no
per-credential length or character-set override and no way to reproduce some
older generator's arguments, because both amount to the same thing: a
credential that claims to be on a policy while holding something else.

The cost is that adopting this module in a resource set with existing passwords
**rotates them**. Terraform sees the old `random_password` address leave the
configuration and a new one arrive, and generates a new value.

If a future environment ever needs to adopt a pre-existing credential without
rotating it, the honest way is a new policy key reproducing that generator's
arguments (`rds_master_legacy`), used by the one consumer that needs it and
retired when it rotates. Append a policy; do not add an override.

### Why there is no `ignore_changes`

Same reason. Suppressing the diff would let the code claim one policy while the
state holds another, exactly the drift this module exists to remove.

## Rotation

Two ways, for two different reasons.

**Rotate the policy** - move a consumer from `rds_master` to `rds_master_v2`.
Everything on that policy rotates as it migrates. This is how a policy change
reaches existing credentials.

**Rotate one password, same policy** - change a value in `keepers`. For a
suspected leak, or a scheduled rotation, where the policy is fine and only this
secret needs replacing.

```hclx
credentials = {
  core = { policy = "rds_master", keepers = { rotated = "2026-08-18" } }
}
```

The value is arbitrary — a date, a ticket, `v2`. Only the fact that it changed
matters.

Nothing rotates on its own: no timestamps, no `always` keepers. A credential
changes when a reviewer can see it changing in a diff.

## Publishing secrets

`publish` is optional and per credential. Omit it and the module only generates
a password, which is how `data-rds` and `data-elasticache` keep their existing
secrets exactly where they are.

```hcl
publish = {
  core = {
    environment = "sandbox"
    service     = "postgres"
    binding     = "managed"
    payload     = { endpoint = module.rds["core"].db_instance_endpoint }
    kms_key_arn = aws_kms_key.rds["core"].arn
  }
}
```

Secrets land at the secret path convention:

```text
<organisation>/<environment>/<service>/<binding>[/<instance>]
```

`binding` is `managed` or `in-cluster`. `instance` is only needed when one
environment holds several of the same service — omit it for the singleton case
the ADR describes.

Passing a `payload` value that depends on the backing resource is safe. The
password is generated before that resource exists and the secret version is
written after it, so there is no cycle.

### MSK is the one exception

AWS refuses to associate a SASL/SCRAM secret whose name does not begin with
`AmazonMSK_`, so the secret path convention cannot apply to it. A `msk_scram` credential
is published with the same components flattened into a legal name instead:

```text
AmazonMSK_<organisation>_<environment>_<service>_<binding>[_<instance>]
```

AWS also rejects an association whose secret uses the default
`aws/secretsmanager` key, so `kms_key_arn` is mandatory for that policy. The
module fails at plan time rather than at apply if it is missing.
