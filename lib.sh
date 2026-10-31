#!/usr/bin/env bash
# Shared helpers. Source this file; do not execute it.
# shellcheck disable=SC2034,SC2016  # variables are used by the sourcing scripts; envsubst needs literal ${VAR} names

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${REPO_ROOT}/terraform"
BUILD_DIR="${REPO_ROOT}/.build"

# Upstream Operator source, pinned. Full SHA, not a branch.
# Why this commit and not main: upstream main (d577804 and later, checked
# 2026-10-27) does not compile - internal/config/config.go references an
# undefined `failureType`. 6bfdfbc is the last commit that builds and it
# contains every feature V1 needs.
OPERATOR_REPO_URL="https://github.com/aws-samples/kr-tech-blog-sample-code.git"
OPERATOR_COMMIT="6bfdfbc0a5b3db43f6b554e03b4b26780c539fe3"
OPERATOR_SUBDIR="containers/devops-agent-operator"

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
ok()   { printf '\033[1;32m[ ok ]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

require_cmd() {
  local missing=0
  for c in "$@"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      printf '\033[1;31m[fail]\033[0m missing dependency: %s\n' "$c" >&2
      missing=1
    fi
  done
  [ "$missing" -eq 0 ] || exit 1
}

# Read a Terraform output (raw string). Fails loudly if infra is not applied.
tf_out() {
  terraform -chdir="${TF_DIR}" output -raw "$1" 2>/dev/null \
    || die "terraform output '$1' not found - run 'terraform apply' first"
}

# Load everything the scripts need from Terraform outputs.
load_tf_outputs() {
  AWS_REGION="$(tf_out region)"
  AWS_ACCOUNT_ID="$(tf_out aws_account_id)"
  EKS_CLUSTER_NAME="$(tf_out eks_cluster_name)"
  OPERATOR_REPO_URL_ECR="$(tf_out operator_ecr_repository_url)"
  DEMO_REPO_URL_ECR="$(tf_out demo_ecr_repository_url)"
  INCIDENT_BUCKET="$(tf_out incident_bucket_name)"
  INCIDENT_LOG_GROUP="$(tf_out incident_log_group_name)"
  export AWS_REGION AWS_ACCOUNT_ID EKS_CLUSTER_NAME OPERATOR_REPO_URL_ECR \
         DEMO_REPO_URL_ECR INCIDENT_BUCKET INCIDENT_LOG_GROUP
}

ecr_login() {
  local registry="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  log "Logging Docker in to ${registry}"
  aws ecr get-login-password --region "${AWS_REGION}" \
    | docker login --username AWS --password-stdin "${registry}" >/dev/null
}

# 0 if repo:tag already exists in ECR (tags are immutable, so we skip rebuilds).
ecr_tag_exists() {
  local repo_name="$1" tag="$2"
  aws ecr describe-images --region "${AWS_REGION}" --repository-name "${repo_name}" \
    --image-ids imageTag="${tag}" >/dev/null 2>&1
}

# Render a *.tpl manifest, substituting ONLY the listed variables so other
# `$` characters are left alone.
render() {
  local file="$1"
  envsubst '${AWS_REGION} ${AWS_ACCOUNT_ID} ${EKS_CLUSTER_NAME} ${INCIDENT_BUCKET} ${INCIDENT_LOG_GROUP} ${OPERATOR_IMAGE} ${DEMO_IMAGE}' < "${file}"
}
