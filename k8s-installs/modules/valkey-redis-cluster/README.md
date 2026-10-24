# valkey-redis-cluster

One Valkey (Redis-compatible) cluster per unit:
`valkey-redis-cluster.<instance>.yaml` → `ValkeyCluster` `valkey-<instance>` in
`valkey-operator`. Needs the `valkey-redis` operator unit and
`external-secrets`. Used for a **redis** request in sandbox; stage and above use
infrastructure's managed `data-elasticache`.

| `spec` | Default | |
|---|---|---|
| `shards` | `1` | |
| `replicas` | `0` | per shard |
| `storage_size` | `5Gi` | |
| `users` | `[]` | `[{ name, permissions? }]` (ACL, default `+@all ~* &*`) |

Passwords (policy `redis_incluster`) publish at
`<organisation>/<env_id>/redis/in-cluster/<instance>` (default user) and
`.../<instance>/<user>`. The service address in the payload
(`valkey-<instance>.<namespace>.svc`) assumes the operator names its Service
after the cluster — not yet confirmed against a running operator.
