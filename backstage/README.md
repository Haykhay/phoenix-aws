# backstage

Local Backstage for Phoenix, built and run entirely in Docker (no Node on the host).

```bash
docker compose up -d --build     # first build ~10 min
open http://localhost:7007       # sign in as guest (a member of group vision)
```

Create → **Phoenix environment** writes one YAML per resource set under
`environments/sandbox/<env_id>/<scope>/`. Use the template editor's dry-run to
see the files; opening the PR comes in the next iteration.

| Path | What |
|---|---|
| `phoenix/templates/environment/` | environment form: infrastructure units + the cluster entity |
| `phoenix/templates/workload/` | workload form: k8s-installs units |
| `phoenix/catalog/` | components and the options the workload form offers |
| `phoenix/accounts.yaml` | stand-in for the account registry (DynamoDB): one `<group>-aws-account` Resource (incl. the group's apps repo for Argo CD) |
| `phoenix/org.yaml` | local groups and users |
| `app-config.docker.yaml` | local-only config (guest sign-in, Phoenix catalog locations) |

`phoenix/` and `app-config.docker.yaml` are mounted, so edits need no rebuild:
config needs `docker compose restart backstage`; catalog files refresh on
their own within a few minutes.

## Phoenix workload (k8s-installs)

Create → **Phoenix workload**: pick a cluster, a workload type (service, model
serving), and optionally a database type (+ name), a GPU type and a model. The
form writes one `k8s-installs` unit per component under
`k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/`.

Everything it offers is catalog data in `phoenix/catalog/` (all `Resource`s,
owned by `group:default/platform`):

| File | `spec.type` | What |
|---|---|---|
| `components.yaml` | `phoenix-component` | one per k8s-installs module; `dependsOn` = direct prerequisites (install order, reverse for teardown) |
| `workloads.yaml` | `phoenix-workload`, `phoenix-baseline` | workload types, and the baseline every cluster gets |
| `databases.yaml` | `phoenix-database` | postgres, redis, kafka |
| `gpus.yaml` | `phoenix-gpu` | GPU types; annotations become the Karpenter pool's `instance_families` / `gpu_count_max` |
| `models.yaml` | `phoenix-model` | curated models; annotation `phoenix/hf-id` |

Each option lists **every** component it needs (the form does not walk
`dependsOn`); keep that list closed under the components' prerequisites when
adding or changing one. Clusters are `phoenix-cluster` entities: the
environment form writes one (`catalog-info.yaml`) next to core-platform;
`phoenix/clusters.yaml` is the local stand-in until GitHub discovery (stage 2).

Adding an option = adding an entity here (and a module + component entity if
it needs a new component). No template change.

## Entra ID (toggle)

`ENTRA_ENABLED=true` in `.env` (template `.env.example`), then
`docker compose up -d --force-recreate backstage`. That loads, with no rebuild:

- the Microsoft sign-in and Microsoft Graph user/group sync plugins (always in
  the image, idle when off; `packages/backend/src/index.ts`),
- `app-config.entra.yaml` (start command in the `Dockerfile`),
- the "Microsoft Entra ID" button on the sign-in page (`packages/app/src/modules/signIn`),
- Phoenix naming (`packages/backend/src/modules/entraNaming.ts`): users are
  named from `mailNickname` (`jdoe`), groups from `displayName` minus
  `phoenix-` (`vision`), so both fit the infrastructure naming rule.
  Users or groups with no usable name are skipped.

Guest sign-in stays available alongside Entra, for local testing.

The Entra automation must produce:

| Thing | Detail |
|---|---|
| App registration | redirect URI `<backstage base URL>/api/auth/microsoft/handler/frame` |
| Delegated Graph permissions | `openid`, `offline_access`, `profile`, `email`, `User.Read` (sign-in) |
| Application Graph permissions + admin consent | `User.Read.All`, `GroupMember.Read.All` (sync) |
| Client secret | → `AZURE_CLIENT_SECRET`; store it in a secret store, rotate it |
| Outputs | tenant ID → `AZURE_TENANT_ID`, application (client) ID → `AZURE_CLIENT_ID` |
| Groups | `phoenix-<group>` (e.g. `phoenix-vision`); owners = the group's approvers |
| Users | `mailNickname` set to a short id (`jdoe`) |

With the `azuread` Terraform provider, take Graph permission IDs from
`azuread_service_principal_msgraph` (`app_role_ids`, `oauth2_permission_scope_ids`)
rather than hard-coding GUIDs.
