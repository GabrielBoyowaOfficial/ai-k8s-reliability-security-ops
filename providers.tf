provider "aws" {
  region = var.region

  # Optional named profile. When null the standard AWS credential chain is used
  # (env vars, SSO, instance profile...). No credentials are ever stored in code.
  profile = var.aws_profile

  default_tags {
    tags = local.common_tags
  }
}
