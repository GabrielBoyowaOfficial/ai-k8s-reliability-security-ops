#!/usr/bin/env bash
# Create/update the Kubernetes Secret holding the DevOps Agent webhook URL and
# HMAC secret. Values come from your shell environment only:
#
#   export DEVOPS_AGENT_WEBHOOK_URL="https://..."
#   export DEVOPS_AGENT_WEBHOOK_SECRET="..."
#
# They never touch Git, Terraform state, or disk: the Secret is streamed to
# kubectl through process substitution.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd kubectl

: "${DEVOPS_AGENT_WEBHOOK_URL:?Set DEVOPS_AGENT_WEBHOOK_URL (see docs/AWS_DEVOPS_AGENT_SETUP.md)}"
: "${DEVOPS_AGENT_WEBHOOK_SECRET:?Set DEVOPS_AGENT_WEBHOOK_SECRET (see docs/AWS_DEVOPS_AGENT_SETUP.md)}"

case "${DEVOPS_AGENT_WEBHOOK_URL}" in
  https://*) ;;
  *) die "DEVOPS_AGENT_WEBHOOK_URL must start with https://" ;;
esac

NS="devops-agent-operator-system"
kubectl get namespace "${NS}" >/dev/null 2>&1 || die "Namespace ${NS} not found - apply kubernetes/namespaces first"

log "Applying Secret devops-agent-operator-webhook in ${NS}"
kubectl -n "${NS}" create secret generic devops-agent-operator-webhook \
  --from-file=webhook-url=<(printf '%s' "${DEVOPS_AGENT_WEBHOOK_URL}") \
  --from-file=webhook-secret=<(printf '%s' "${DEVOPS_AGENT_WEBHOOK_SECRET}") \
  --dry-run=client -o yaml \
  | kubectl apply -f - >/dev/null

# Environment variables are read at start-up, so a running Operator must restart.
if kubectl -n "${NS}" get deployment devops-agent-operator >/dev/null 2>&1; then
  log "Restarting Operator to pick up the new Secret"
  kubectl -n "${NS}" rollout restart deployment/devops-agent-operator >/dev/null
  kubectl -n "${NS}" rollout status deployment/devops-agent-operator --timeout=180s
fi

ok "Webhook Secret configured"
