#!/usr/bin/env bash
# Remove Kubernetes workloads first, then destroy the AWS infrastructure.
# Only resources created by this project's Terraform are touched.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd terraform aws kubectl

if [ "${AUTO_APPROVE:-0}" != "1" ]; then
  read -r -p "This destroys the whole lab (EKS, VPC, NAT, ECR, S3 evidence). Type 'destroy' to continue: " answer
  [ "${answer}" = "destroy" ] || die "Aborted"
fi

# A missing output is a legitimate state here (nothing applied yet), so it is
# handled explicitly rather than ignored.
CLUSTER=""
REGION=""
if CLUSTER="$(terraform -chdir="${TF_DIR}" output -raw eks_cluster_name 2>/dev/null)"; then
  REGION="$(tf_out region)"
fi

if [ -n "${CLUSTER}" ] && [ -n "${REGION}" ]; then
  log "Refreshing kubeconfig and deleting Kubernetes resources"
  aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER}" >/dev/null
  # Deleting namespaces removes the workloads and the webhook Secret. If the
  # cluster is unreachable (for example your IP changed) this fails loudly;
  # fix admin_cidr, re-apply, and retry rather than skipping it.
  kubectl delete -f "${REPO_ROOT}/kubernetes/operator/rbac.yaml" --ignore-not-found
  kubectl delete namespace reliability-lab devops-agent-operator-system --ignore-not-found --timeout=180s
else
  log "No Terraform outputs found - skipping Kubernetes cleanup (infrastructure may already be gone)"
fi

log "terraform destroy"
terraform -chdir="${TF_DIR}" destroy -input=false -auto-approve

rm -rf "${BUILD_DIR}"
ok "Lab destroyed"
