# external-dns

[external-dns](https://kubernetes-sigs.github.io/external-dns/) for Route53,
with Pod Identity (`external-dns/external-dns` → `<name_prefix>-external-dns`).
Part of the **service** set.

- Sources: `service`, `ingress`, `gateway-httproute` — only resources annotated
  `external-dns.alpha.kubernetes.io/hostname` get a record.
- Zones: the cluster's own public + internal zone by default; naming zone keys
  (`spec.settings.providers.route53.zones: [zone-1, zone-2]`) widens both what
  it reconciles (`--zone-id-filter`; the chart has no `zoneIdFilters` value)
  and what its IAM policy may change.
- Records are owned per cluster (`txtOwnerId` = the cluster's name prefix) and
  never deleted by default (`policy: upsert-only`).

Chart `1.21.1`, pinned. The plan fails clearly without the environment's dns unit.
