# cloudnative-pg-cluster

One PostgreSQL cluster ([CloudNativePG](https://cloudnative-pg.io) `Cluster`)
per unit: `cloudnative-pg-cluster.<instance>.yaml` → cluster `cnpg-<instance>`
in `cnpg-system`. Needs the `cloudnative-pg` operator unit and
`external-secrets`. Used for a **postgres** request in sandbox; stage and above
use infrastructure's managed `data-rds`.

| `spec` | Default | |
|---|---|---|
| `instances` | `1` | |
| `storage_size` | `10Gi` | |
| `databases` | one, named after the instance | `[{ name, owner? }]`; owner defaults to the name |
| `nlb_enabled` | `false` | internal NLB + `<cluster>.<internal zone>` record |

**Credentials** come from infrastructure's `credentials` module (policy
`postgres_incluster`) and are published where external-secrets may read them:

```text
<organisation>/<env_id>/postgres/in-cluster/<instance>            superuser
<organisation>/<env_id>/postgres/in-cluster/<instance>/<database> each database (address, port, endpoint, database)
```

The chart's `ExternalSecret`s turn them into the Kubernetes secrets CNPG uses.
Output `cluster` lists the service address and every secret name.
