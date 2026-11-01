# The group's weights bucket and its copy role, from infrastructure's model-store unit.
data "terraform_remote_state" "model_store" {
  backend = "s3"
  config = {
    bucket = module.context.state.bucket
    region = module.context.state.region
    key    = "${module.context.group}-shared/${local.region}/model-store/terraform.tfstate"
  }
  defaults = {}
}

resource "terraform_data" "validation" {
  lifecycle {
    precondition {
      condition     = !local.config.enabled || local.instance != null
      error_message = "model-weights is per model: name the file model-weights.<model slug>.yaml."
    }
    precondition {
      condition     = !local.config.enabled || can(local.store.bucket_name)
      error_message = "no model-store for ${module.context.group} in ${local.region}: apply infrastructure's ${module.context.group}-shared/${local.region}/model-store.yaml first."
    }
    # source_type_known
    precondition {
      condition     = !local.config.enabled || contains(["huggingface", "s3", "https"], local.source.type)
      error_message = "spec.source.type must be huggingface, s3 or https."
    }
    # uri_matches_type
    precondition {
      condition = !local.config.enabled || can(regex(lookup({
        huggingface = "^[\\w.-]+/[\\w.-]+$"
        s3          = "^s3://[a-z0-9.-]{3,63}/.*$"
        https       = "^https://"
      }, local.source.type, "^$"), local.uri))
      error_message = "spec.source.uri must match its type: huggingface <org>/<repo>, s3 s3://<bucket>/<prefix>/, https https://… (plain http is refused)."
    }
    # hf_version_is_sha
    precondition {
      condition     = !local.config.enabled || local.source.type != "huggingface" || can(regex("^[0-9a-f]{40}$", local.version))
      error_message = "a huggingface spec.version is the 40-character commit SHA, never a branch or tag: a branch moves."
    }
    # https_needs_sha256
    precondition {
      condition     = !local.config.enabled || local.source.type != "https" || can(regex("^[0-9a-f]{64}$", local.sha256))
      error_message = "an https source needs spec.sha256 (64 hex characters): the download is verified before it is copied."
    }
    # version_label
    precondition {
      # . and .. would leave /models/<model>/ and <model>/ in the bucket.
      condition     = !local.config.enabled || (can(regex("^[A-Za-z0-9._-]{1,64}$", local.version)) && !contains([".", ".."], local.version))
      error_message = "spec.version is required: letters, digits, '.', '_' or '-', at most 64 characters, and not . or .."
    }
    precondition {
      condition     = !local.config.enabled || length(local.release) <= 53
      error_message = "release ${local.release} is over Helm's 53 characters: shorten the model name or the version label."
    }
  }
}

resource "helm_release" "this" {
  count            = local.config.enabled ? 1 : 0
  name             = local.release
  chart            = "${path.module}/manifests/weights-job"
  namespace        = local.namespace
  create_namespace = true
  # A 600B model over the internet takes hours; state exists only after success.
  wait_for_jobs = true
  timeout       = 21600

  values = [yamlencode({
    name              = local.release
    serviceAccount    = local.release
    region            = local.region
    bucket            = local.bucket
    key               = local.key
    source            = { type = local.source.type, uri = local.source.uri }
    version           = local.version
    sha256            = local.sha256
    sizeGiB           = local.config.size_gib
    credentialsSecret = local.credentials_secret
    images            = local.images
    hfPackage         = local.hf_package
  })]

  depends_on = [terraform_data.validation, time_sleep.pod_identity_propagation]
}
