# strimzi-kafka-cluster

One Kafka cluster ([Strimzi](https://strimzi.io), KRaft) per unit:
`strimzi-kafka-cluster.<instance>.yaml` → `Kafka` `kafka-<instance>` in
`strimzi-operator`. Needs the `strimzi-kafka` operator unit and
`external-secrets`. Used for a **kafka** request in sandbox; stage and above use
infrastructure's managed `data-msk`.

`spec.tier` picks a preset (any field can be overridden):

| | `nonprod` (default) | `prod` |
|---|---|---|
| Nodes | one dual-role pool, 1 replica, 10Gi | 3 controllers + 3 brokers |
| Listeners | internal SCRAM `9093` | internal `9092` + external NLB `9096` |
| Replication | 1 | 3, min ISR 2 |
| Extras | — | CA lifecycle, Kafka exporter, PDB, zone spreading |

`topics: [{ name, partitions, replicas, config? }]` and `users: [{ name, acls? }]`.
Kubernetes objects are prefixed with the cluster name (`kafka-<instance>-<user>`,
`kafka-<instance>-<topic>`) so two clusters in one namespace never collide; a
topic keeps its real name, and the SCRAM username is the prefixed name.

User passwords (policy `generic`) publish at
`<organisation>/<env_id>/kafka/in-cluster/<instance>/<user>` with the bootstrap
address. Topics carry `helm.sh/resource-policy: keep`: removing one from the
spec does not delete its data.
