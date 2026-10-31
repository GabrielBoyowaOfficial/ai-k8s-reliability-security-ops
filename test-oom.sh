#!/usr/bin/env bash
# Helper for watching the OOMKilled incident flow and verifying each stage.
#
#   ./scripts/test-oom.sh watch      watch pods until OOMKilled appears
#   ./scripts/test-oom.sh verify     check every stage of the pipeline
#   ./scripts/test-oom.sh commands   print the manual commands
#   ./scripts/test-oom.sh restart    redeploy the demo to trigger a fresh incident
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd kubectl aws terraform
load_tf_outputs

NS="reliability-lab"
OP_NS="devops-agent-operator-system"
APP="memory-leak-demo"

pod_name() {
  kubectl -n "${NS}" get pods -l "app.kubernetes.io/name=${APP}" \
    -o jsonpath='{.items[0].metadata.name}'
}

last_reason() {
  kubectl -n "${NS}" get pods -l "app.kubernetes.io/name=${APP}" \
    -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated.reason}'
}

cmd_commands() {
  cat <<EOF
# Pods
kubectl -n ${NS} get pods -w
kubectl -n ${NS} describe pod -l app.kubernetes.io/name=${APP}
kubectl -n ${NS} logs -l app.kubernetes.io/name=${APP}
kubectl -n ${NS} logs -l app.kubernetes.io/name=${APP} --previous
kubectl -n ${NS} get events --sort-by=.lastTimestamp

# Operator
kubectl -n ${OP_NS} logs deploy/devops-agent-operator --tail=100

# CloudWatch incident log (needs AWS CLI v2)
aws logs tail ${INCIDENT_LOG_GROUP} --region ${AWS_REGION} --since 1h
aws logs describe-log-streams --log-group-name ${INCIDENT_LOG_GROUP} --region ${AWS_REGION}

# S3 incident evidence
aws s3 ls s3://${INCIDENT_BUCKET}/incidents/ --recursive --region ${AWS_REGION}
EOF
}

cmd_watch() {
  log "Watching pods in ${NS}. Ctrl-C when you see OOMKilled / restarts."
  log "(In a second terminal: kubectl -n ${OP_NS} logs -f deploy/devops-agent-operator)"
  kubectl -n "${NS}" get pods -w
}

cmd_restart() {
  log "Restarting ${APP} to produce a fresh OOM cycle"
  kubectl -n "${NS}" rollout restart "deployment/${APP}"
}

cmd_verify() {
  local pod
  pod="$(pod_name)"

  log "Stage 1: pod status for ${pod}"
  kubectl -n "${NS}" get pod "${pod}"
  local reason
  reason="$(last_reason)"
  if [ "${reason}" = "OOMKilled" ]; then
    ok "Last terminated reason: OOMKilled"
    kubectl -n "${NS}" get pod "${pod}" \
      -o jsonpath='{range .status.containerStatuses[*]}exit code: {.lastState.terminated.exitCode}{"\n"}{end}'
  else
    die "Not OOMKilled yet (last reason: '${reason:-none}'). Wait ~2 minutes and retry."
  fi

  log "Stage 2: previous container logs (memory growth before the kill)"
  kubectl -n "${NS}" logs "${pod}" --previous --tail=5

  log "Stage 3: Operator log lines for this incident"
  kubectl -n "${OP_NS}" logs deploy/devops-agent-operator --tail=200 | grep -Ei "${APP}|oom|webhook|s3|cloudwatch" || die "No matching Operator log lines yet"

  log "Stage 4: CloudWatch incident log streams"
  aws logs describe-log-streams --region "${AWS_REGION}" --log-group-name "${INCIDENT_LOG_GROUP}" \
    --query 'logStreams[].logStreamName' --output text | tr '\t' '\n' | grep . || die "No log streams in ${INCIDENT_LOG_GROUP}"

  log "Stage 5: S3 incident evidence"
  aws s3 ls "s3://${INCIDENT_BUCKET}/incidents/" --recursive --region "${AWS_REGION}" | head -30

  ok "Pipeline evidence found. Webhook success shows in the Operator log ('Webhook request ... successful')."
  log "Final step is manual: open your Agent Space in the AWS DevOps Agent console and check the new investigation."
}

case "${1:-}" in
  watch)    cmd_watch ;;
  verify)   cmd_verify ;;
  commands) cmd_commands ;;
  restart)  cmd_restart ;;
  *) echo "usage: $0 {watch|verify|commands|restart}" >&2; exit 2 ;;
esac
