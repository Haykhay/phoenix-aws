locals {
  defaults = {
    enabled = true
    model   = null # defaults to the instance slug
    # huggingface: HF repo id; s3: s3://bucket/prefix/; https: https://…
    source   = { type = "huggingface", uri = null, credentials = false }
    version  = null # 40-char commit SHA for huggingface; a label for s3/https
    sha256   = null # required for https
    size_gib = 200  # scratch volume the source is fetched into
  }

  config = merge(local.defaults, module.context.spec)
  source = merge(local.defaults.source, local.config.source)

  namespace = "models"
  model     = coalesce(local.config.model, local.instance, "missing")
  version   = coalesce(local.config.version, "missing")
  uri       = local.source.uri == null ? "" : local.source.uri
  sha256    = local.config.sha256 == null ? "" : local.config.sha256

  # Helm release names are DNS labels: a label like 2026.10_rc1 becomes
  # 2026-10-rc1. A SHA is cut to 7; a label is kept whole, since
  # 2026-10-01 and 2026-10-02 share their first 7.
  version_slug = (local.source.type == "huggingface" ? substr(local.version, 0, 7)
  : replace(lower(local.version), "/[._]/", "-"))
  release = "weights-${local.model}-${local.version_slug}"

  store     = try(data.terraform_remote_state.model_store.outputs, {})
  bucket    = try(local.store.bucket_name, "missing")
  key       = "${local.model}/${local.version}"
  s3_prefix = "s3://${local.bucket}/${local.key}/"

  # Hugging Face keeps vllm's token path; other sources get their own. An s3
  # source reads with the copy role, so it never has one.
  credentials_secret = !local.source.credentials || local.source.type == "s3" ? "" : (
    local.source.type == "huggingface"
    ? "${local.organisation}/${local.environment}/models/hf-token"
    : "${local.organisation}/${local.environment}/models/${coalesce(local.instance, "missing")}-source"
  )

  images = {
    upload = "amazon/aws-cli:2.38.0"        # 2026-10-13
    s3     = "amazon/aws-cli:2.38.0"        # 2026-10-13
    https  = "curlimages/curl:8.22.0"       # 2026-09-02
    hf     = "python:3.13.16-slim-bookworm" # 2026-09-30
  }
  hf_package = "huggingface_hub==2.1.1" # 2026-10-01
}
