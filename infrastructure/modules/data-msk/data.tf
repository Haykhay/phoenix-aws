data "aws_caller_identity" "current" {}

data "terraform_remote_state" "core_platform" {
  count   = local.read_core_platform_state ? 1 : 0
  backend = "s3"

  config = {
    bucket       = module.context.state.bucket
    key          = local.core_platform_state_key
    region       = module.context.state.region
    encrypt      = true
    use_lockfile = true
  }
}
