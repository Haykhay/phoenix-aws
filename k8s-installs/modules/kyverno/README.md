# kyverno

[Kyverno](https://kyverno.io) plus a module-owned policies chart. Part of every
cluster's baseline.

The one policy today, `require-environment-images`, checks where internal
images come from:

| Setting (`spec.settings`, or under `kyverno_policies`) | Default | |
|---|---|---|
| `policy_mode` | `Audit` | `Audit` or `Enforce`; anything else fails the plan |
| `managed_image_patterns` | `*.dkr.ecr.*.amazonaws.com/*` | images that count as internal |
| `allowed_image_patterns` | `<account_id>.dkr.ecr.<region>.amazonaws.com/*` | where internal images must come from: the group account's own registry (its ECR pull-through cache) |
| `excluded_namespaces` | `kube-system`, `kube-public`, `kube-node-lease`, `kyverno` | |

So a pod pulling another group's ECR image is reported (Audit) or refused
(Enforce). Chart `3.8.1`, pinned. `spec.enabled: false` installs nothing.
