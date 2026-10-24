# ecr

Pull-through cache **spoke**: each group account gets its own ECR, filled on
demand from the company's central ECR **hub**.

```text
Artifactory ──(scheduled sync, outside this repo)──► hub ECR ──(pull-through cache)──► group account ECR
```

ECR's pull-through cache cannot use Artifactory as an upstream (it supports ECR
Public, the Kubernetes registry, Quay, Docker Hub, Azure CR, GHCR, GitLab SaaS,
Chainguard, and another ECR). So one sync job copies the images the company
uses from Artifactory into the hub, and every group account caches from the
hub. A group account holds only what its workloads actually pull; AWS
refreshes cached tags from the hub at least every 24 hours.

The hub, its registry policy and the Artifactory sync live with the shared
tooling (like account vending), not here.

One per group account per region, account-level:

```text
environments/<tier>/<group>-shared/<region>/ecr.yaml
state: <group>-shared/<region>/ecr/terraform.tfstate
```

## Creates

| Resource | Name |
|---|---|
| Pull-through cache rule `<cache prefix>/` → hub | — |
| IAM role ECR assumes to pull from the hub (trust `pullthroughcache.ecr.amazonaws.com`) | `<name_prefix>-ecr-pull-through` |
| Repository creation template for `<cache prefix>/`: KMS, immutable tags, lifecycle | — |
| KMS key + alias | `alias/<name_prefix>-ecr` |
| IAM policy for first pulls (`BatchImportUpstreamImage`, `CreateRepository`) | `<name_prefix>-ecr-pull-through` |

## Configuration

```yaml
environment: shared
spec:
  hub:
    account_id: "999999999999"   # required: the central ECR account
    region: eu-west-1            # default: this unit's region
    repository_prefix: base/     # optional: only cache hub repos under this prefix
  cache_prefix: artifactory      # default
  untagged_expiry_days: 7        # default
  keep_images: 30                # default
```

## Using it

Images are referenced as
`<account>.dkr.ecr.<region>.amazonaws.com/<cache prefix>/<hub repo>:<tag>`
(output `registry_url_prefix`). The first pull of an image creates its cache
repository, which plain pull rights do not allow: add output
`node_pull_policy_arn` to core-platform's `node_role_additional_policies`.

**Hub side** (outside this repo): the hub's registry policy must allow
`ecr:BatchGetImage`, `ecr:GetDownloadUrlForLayer` and
`ecr:BatchCheckLayerAvailability` to each group account's
`<name_prefix>-ecr-pull-through` role — or to the whole organisation path
(`aws:PrincipalOrgPaths`), so new group accounts need no hub change.

## Tests

```bash
terraform init -backend=false && terraform test
```
