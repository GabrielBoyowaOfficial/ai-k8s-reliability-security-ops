#!/usr/bin/env bash
# End-to-end deploy: infrastructure -> kubeconfig -> Operator -> demo workload.
#
# Required environment (never stored in Git):
#   DEVOPS_AGENT_WEBHOOK_URL, DEVOPS_AGENT_WEBHOOK_SECRET
# Optional:
#   AUTO_APPROVE=1   apply the Terraform plan without the interactive prompt
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SCRIPTS="${REPO_ROOT}/scripts"

require_cmd terraform aws kubectl docker git envsubst
: "${DEVOPS_AGENT_WEBHOOK_URL:?Set DEVOPS_AGENT_WEBHOOK_URL first (docs/AWS_DEVOPS_AGENT_SETUP.md)}"
: "${DEVOPS_AGENT_WEBHOOK_SECRET:?Set DEVOPS_AGENT_WEBHOOK_SECRET first (docs/AWS_DEVOPS_AGENT_SETUP.md)}"
[ -f "${TF_DIR}/terraform.tfvars" ] || die "Create terraform/terraform.tfvars (copy terraform.tfvars.example and set admin_cidr)"
docker info >/dev/null 2>&1 || die "Docker daemon is not running"

log "1/9 terraform init"
terraform -chdir="${TF_DIR}" init -input=false

log "2/9 terraform plan"
terraform -chdir="${TF_DIR}" plan -input=false -out=tfplan

log "3/9 terraform apply"
if [ "${AUTO_APPROVE:-0}" != "1" ]; then
  read -r -p "Apply this plan? (yes/no) " answer
  [ "${answer}" = "yes" ] || die "Aborted"
fi
terraform -chdir="${TF_DIR}" apply -input=false tfplan

load_tf_outputs

log "4/9 Configuring kubectl for ${EKS_CLUSTER_NAME}"
aws eks update-kubeconfig --region "${AWS_REGION}" --name "${EKS_CLUSTER_NAME}" >/dev/null
kubectl wait --for=condition=Ready nodes --all --timeout=600s
kubectl apply -f "${REPO_ROOT}/kubernetes/namespaces/namespaces.yaml"

log "5/9 Building and pushing the Operator image"
"${SCRIPTS}/build-operator.sh"
OPERATOR_IMAGE="$(cat "${BUILD_DIR}/operator-image.txt")"
export OPERATOR_IMAGE

log "6/9 Creating the webhook Secret"
"${SCRIPTS}/configure-webhook.sh"

log "7/9 Deploying the Operator"
kubectl apply -f "${REPO_ROOT}/kubernetes/operator/rbac.yaml"
render "${REPO_ROOT}/kubernetes/operator/configmap.yaml.tpl" | kubectl apply -f -
render "${REPO_ROOT}/kubernetes/operator/deployment.yaml.tpl" | kubectl apply -f -
kubectl -n devops-agent-operator-system rollout status deployment/devops-agent-operator --timeout=300s

log "8/9 Building and pushing the demo image"
"${SCRIPTS}/build-demo.sh"
DEMO_IMAGE="$(cat "${BUILD_DIR}/demo-image.txt")"
export DEMO_IMAGE

# Deployed after the Operator on purpose: it reacts to pod status UPDATES, so
# the Operator must already be running when the first OOMKill happens.
log "9/9 Deploying memory-leak-demo"
render "${REPO_ROOT}/kubernetes/apps/memory-leak-demo.yaml.tpl" | kubectl apply -f -
kubectl -n reliability-lab rollout status deployment/memory-leak-demo --timeout=180s

ok "Deployed. The pod should be OOMKilled in about 1.5-2 minutes. Run: ./scripts/test-oom.sh watch"
