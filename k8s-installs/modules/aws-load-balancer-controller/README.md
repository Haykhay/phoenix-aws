# aws-load-balancer-controller

The [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
(chart `3.4.0`, pinned) in `kube-system`, with Pod Identity
(`aws-load-balancer-controller` → `<name_prefix>-aws-load-balancer-controller`,
AWS's reference policy in `iam-policy.json`). Part of the **service** set;
istio's gateways get their NLBs from it.

- `vpcId` and `region` are set explicitly: nodes require IMDSv2 with the
  default hop limit, so the controller cannot rely on instance metadata.
- Load balancers it creates carry the unit's tags (`defaultTags`) plus `Cluster`.
- Gateway API CRDs are **not** installed here any more — istio owns them.
