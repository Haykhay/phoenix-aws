# cluster-config

Cluster-wide settings every other component relies on. Part of every cluster's
baseline. Installs the `gp3` StorageClass (default class, encrypted, EBS CSI)
into `kube-system`.

EBS volumes created through it carry the unit's tags (`module.context.tags`
plus `Cluster`) as `tagSpecification_N` parameters, so they show up in cost
and ownership reports like every Terraform-created resource.

Spec: `enabled` (default `true`). Nothing else.
