# karpenter

The [Karpenter](https://karpenter.sh) controller plus a default
`EC2NodeClass`/`NodePool` (both named `default`). Part of every cluster's
baseline. The AWS side — controller role (Pod Identity), node role, SQS
interruption queue — is infrastructure's core-platform (`clusters.<key>.karpenter.enabled`);
this module reads those facts back through `modules/cluster` and fails the
plan clearly if they are missing.

| Default pool | |
|---|---|
| AMI | `al2023@latest` |
| Capacity | on-demand + spot, amd64, categories c/m/r, generation > 5 |
| Limit | 64 vCPU |
| Disruption | consolidate when empty or underutilised after 1m; nodes expire after 7 days |
| Subnets / security group | core-platform's node subnets and node security group, **by ID** (no discovery tags) |
| Node tags | the unit's tags + `Cluster` |

GPU capacity is not here: each GPU type is its own `karpenter-nodepool.<type>`
unit. Chart `1.14.0` (oci://public.ecr.aws/karpenter), pinned; core-platform's
controller policy covers Karpenter up to 1.15 — re-check it before bumping.

The node class and pool are a local Helm chart (`manifests/karpenter-defaults`),
not `kubernetes_manifest`: their CRDs arrive with the controller chart, and
`kubernetes_manifest` needs CRDs to exist at plan time.

`spec` overrides: `ami_alias`, `capacity_types`, `instance_category`,
`instance_gen_min`, `cpu_limit`, `expire_after`, `consolidate_after`, `enabled`.
