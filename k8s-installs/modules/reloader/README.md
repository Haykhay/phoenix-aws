# reloader

[Stakater Reloader](https://github.com/stakater/Reloader): restarts workloads
when the ConfigMaps or Secrets they use change (for example after
external-secrets rotates a value). Part of every cluster's baseline.

| `spec.settings` | Default | |
|---|---|---|
| `chart_version` | `2.2.12` | pinned by the platform |
| `namespace` | `reloader` | |
| `auto_reload_all` | `false` | reload every workload, not just annotated ones |
| `values` | `{}` | extra chart values |

`spec.enabled: false` installs nothing.
