#!/usr/bin/env bash
# Build the memory-leak-demo image and push it to ECR with a deterministic tag.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd docker aws terraform
load_tf_outputs

APP_DIR="${REPO_ROOT}/apps/memory-leak-demo"

# Tag = git short SHA; if the app directory has uncommitted changes, append a
# content hash so a different build can never reuse the same immutable tag.
if git -C "${REPO_ROOT}" rev-parse --git-dir >/dev/null 2>&1 && git -C "${REPO_ROOT}" rev-parse HEAD >/dev/null 2>&1; then
  TAG="$(git -C "${REPO_ROOT}" rev-parse --short=12 HEAD)"
  if [ -n "$(git -C "${REPO_ROOT}" status --porcelain -- apps/memory-leak-demo)" ]; then
    TAG="${TAG}-dirty-$(cat "${APP_DIR}/app.py" "${APP_DIR}/Dockerfile" | sha256sum | cut -c1-8)"
  fi
else
  TAG="src-$(cat "${APP_DIR}/app.py" "${APP_DIR}/Dockerfile" | sha256sum | cut -c1-12)"
fi

REPO_NAME="${DEMO_REPO_URL_ECR#*/}"
IMAGE="${DEMO_REPO_URL_ECR}:${TAG}"

ecr_login

mkdir -p "${BUILD_DIR}"
if ecr_tag_exists "${REPO_NAME}" "${TAG}"; then
  ok "Demo image ${IMAGE} already in ECR - nothing to do"
else
  log "Building ${IMAGE} (linux/amd64)"
  docker build --platform linux/amd64 -t "${IMAGE}" "${APP_DIR}"
  log "Pushing ${IMAGE}"
  docker push "${IMAGE}"
  ok "Demo image pushed: ${IMAGE}"
fi

echo "${IMAGE}" > "${BUILD_DIR}/demo-image.txt"
