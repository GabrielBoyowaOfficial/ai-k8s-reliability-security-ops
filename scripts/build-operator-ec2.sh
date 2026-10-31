#!/usr/bin/env bash
# Optional helper to run ON a temporary Amazon Linux 2023 EC2 build host.
# The EC2 instance role must be able to push to the target ECR repository.
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-west-2}"
ECR_REPO_NAME="${ECR_REPO_NAME:-ai-k8s-ops/devops-agent-operator}"
OPERATOR_REPO_URL="${OPERATOR_REPO_URL:-https://github.com/aws-samples/kr-tech-blog-sample-code.git}"
OPERATOR_COMMIT="${OPERATOR_COMMIT:-6bfdfbc0a5b3db43f6b554e03b4b26780c539fe3}"
OPERATOR_SUBDIR="${OPERATOR_SUBDIR:-containers/devops-agent-operator}"
TAG="${OPERATOR_COMMIT:0:12}"
SRC_DIR="${SRC_DIR:-/tmp/devops-agent-operator-src}"

log() { printf '[build-server] %s\n' "$*"; }
die() { printf '[build-server] ERROR: %s\n' "$*" >&2; exit 1; }

command -v aws >/dev/null 2>&1 || die "AWS CLI is required"

if ! command -v git >/dev/null 2>&1 || ! command -v docker >/dev/null 2>&1; then
  command -v dnf >/dev/null 2>&1 || die "This helper expects Amazon Linux 2023/dnf when dependencies are missing"
  log "Installing Docker and Git"
  sudo dnf install -y docker git
fi

log "Starting Docker"
sudo systemctl enable --now docker

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE="${REGISTRY}/${ECR_REPO_NAME}:${TAG}"

log "Checking ECR repository ${ECR_REPO_NAME}"
aws ecr describe-repositories --region "${AWS_REGION}" --repository-names "${ECR_REPO_NAME}" >/dev/null \
  || die "ECR repository does not exist yet. Apply the Terraform infrastructure first."

if aws ecr describe-images --region "${AWS_REGION}" --repository-name "${ECR_REPO_NAME}" \
     --image-ids imageTag="${TAG}" >/dev/null 2>&1; then
  log "Image already exists: ${IMAGE}"
  exit 0
fi

log "Logging Docker into ECR"
aws ecr get-login-password --region "${AWS_REGION}" \
  | sudo docker login --username AWS --password-stdin "${REGISTRY}" >/dev/null

rm -rf "${SRC_DIR}"
log "Fetching pinned Operator source ${OPERATOR_COMMIT}"
git init --quiet "${SRC_DIR}"
git -C "${SRC_DIR}" remote add origin "${OPERATOR_REPO_URL}"
git -C "${SRC_DIR}" fetch --quiet --depth 1 origin "${OPERATOR_COMMIT}"
git -C "${SRC_DIR}" checkout --quiet --force FETCH_HEAD

ACTUAL="$(git -C "${SRC_DIR}" rev-parse HEAD)"
[ "${ACTUAL}" = "${OPERATOR_COMMIT}" ] || die "Checked out ${ACTUAL}, expected ${OPERATOR_COMMIT}"

log "Building ${IMAGE}"
sudo docker build --platform linux/amd64 -t "${IMAGE}" "${SRC_DIR}/${OPERATOR_SUBDIR}"

log "Pushing ${IMAGE}"
sudo docker push "${IMAGE}"

log "Push complete: ${IMAGE}"
