# cloudnative-pg

The operator for `cloudnative-pg-cluster` units, in its own namespace. Installed when a request asks for that database type in sandbox. Chart version pinned in `locals.tf`; `spec.enabled: false` installs nothing.

Images are the upstream ones unless `spec.image_registry` is set (e.g. the group's ECR pull-through prefix `<account>.dkr.ecr.<region>.amazonaws.com/artifactory`); then the operator and Postgres images come from there.
