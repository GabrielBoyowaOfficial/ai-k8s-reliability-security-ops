#!/usr/bin/env bash
# Fetch the official AWS DevOps Agent Operator source at a pinned commit,
# build it, and push it to our ECR repository.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd git docker aws terraform
load_tf_outputs

SRC_DIR="${BUILD_DIR}/operator-src"
TAG="${OPERATOR_COMMIT:0:12}"
REPO_NAME="${OPERATOR_REPO_URL_ECR#*/}"
IMAGE="${OPERATOR_REPO_URL_ECR}:${TAG}"

ecr_login
mkdir -p "${BUILD_DIR}"

if ecr_tag_exists "${REPO_NAME}" "${TAG}"; then
  ok "Operator image ${IMAGE} already in ECR - nothing to do"
  echo "${IMAGE}" > "${BUILD_DIR}/operator-image.txt"
  exit 0
fi

if [ ! -d "${SRC_DIR}/.git" ]; then
  log "Fetching ${OPERATOR_REPO_URL} @ ${OPERATOR_COMMIT}"
  git init --quiet "${SRC_DIR}"
  git -C "${SRC_DIR}" remote add origin "${OPERATOR_REPO_URL}"
fi
git -C "${SRC_DIR}" fetch --quiet --depth 1 origin "${OPERATOR_COMMIT}"
git -C "${SRC_DIR}" checkout --quiet --force FETCH_HEAD

ACTUAL="$(git -C "${SRC_DIR}" rev-parse HEAD)"
[ "${ACTUAL}" = "${OPERATOR_COMMIT}" ] || die "Checked out ${ACTUAL}, expected ${OPERATOR_COMMIT}"

# x86_64 because the node group uses t3 instances (AL2023_x86_64_STANDARD).
log "Building ${IMAGE} (linux/amd64)"
docker build --platform linux/amd64 -t "${IMAGE}" "${SRC_DIR}/${OPERATOR_SUBDIR}"

log "Pushing ${IMAGE}"
docker push "${IMAGE}"

echo "${IMAGE}" > "${BUILD_DIR}/operator-image.txt"
ok "Operator image pushed: ${IMAGE}"
