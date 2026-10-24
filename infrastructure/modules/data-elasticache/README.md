# data-elasticache

Bundled resource-set module for in-memory caches. It creates a **named set of
ElastiCache replication groups** (Valkey/Redis) for one environment/region, each
with its own KMS key, security group and credentials secret.

## Where this runs

```text
environments/<tier>/<env_id>/<region>/data-elasticache.yaml
state: <env_id>/<region>/data-elasticache/terraform.tfstate
```

## Configuration

Values only, under `spec` in the unit's YAML:

```yaml
clusters:
  core-cache:
    engine: valkey
    engine_version: "8.0"
    node_type: cache.t4g.micro
    num_cache_clusters: 1
    vpc: vpc-1
    eks_clusters: ["1"]
```

| Key | Default | Notes |
|---|---|---|
| `engine`, `engine_version` | — | Required per cluster |
| `node_type`, `num_cache_clusters` | — | Required per cluster |
| `vpc` | resource set's, else network default | Which VPC this cluster sits in |
| `eks_clusters` | see below | EKS clusters whose nodes may reach it |
| `base_name_postfix` | the map key | Trailing component of the name |
| `port` | 6379 | |
| `automatic_failover`, `multi_az` | `false` | |
| `transit_encryption` | — | When true, an AUTH token is generated |
| `at_rest_encryption` | — | Uses the cluster's KMS key |
| `snapshot_retention_limit` | — | |
| `allowed_cidr_blocks` | `[]` | Extra ingress |
| `allowed_security_group_ids` | `[]` | Extra ingress |
| `allow_eks_node_security_group` | `true` | `false` skips the cluster binding entirely |
| `tags` | `{}` | Ownership tags |

Resource-set level values apply to every cluster; an entry in `clusters`
overrides them.

## Which clusters can reach it

`eks_clusters` lists the EKS clusters whose node security group gets ingress. It
is a list because one cache can legitimately serve several clusters.

This is a security boundary, not a placement choice, and getting it wrong fails
**silently** — the cache simply becomes unreachable from the cluster that needed
it. So the plan
refuses an unbound item once more than one EKS cluster exists; with exactly one it is unambiguous and may be omitted.

Set `allow_eks_node_security_group: false` for a cache no cluster should reach.

## Naming

```text
<name_prefix>-<base_name_postfix>
```

An ElastiCache **replication group ID caps at 40 characters** — the limit that
forced the short region codes in `modules/context`. Long group, environment or
requester names reach it quickly (`computational-biology-sandbox-jdoe-euw1-core-cache`
is 50). The plan fails with the offending IDs and their lengths rather than
truncating or hashing; shorten the cluster key or set `base_name_postfix`.

## Credentials

AUTH tokens come from the shared [`credentials`](../credentials/README.md)
module, so the policy cannot be right in one module and wrong in another.
The standard policy is 30 alphanumeric characters, which sidesteps the
ElastiCache AUTH-token character restriction rather than encoding it.

A token is only generated for clusters with `transit_encryption` on; without
it there is nothing to authenticate. Rotation is deliberate, via
`password_keepers`:

```json
"clusters": { "core-cache": { "password_keepers": { "rotated": "2026-08-18" } } }
```

## Secrets

Each cluster gets a Secrets Manager secret holding the primary and reader
endpoints, the port, and the AUTH token when transit encryption is on.
