# Partial: the workflow supplies bucket, key, region, kms_key_id, encrypt and
# use_lockfile at `terraform init` from the unit's YAML.
terraform {
  backend "s3" {}
}
