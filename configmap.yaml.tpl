apiVersion: v1
kind: ConfigMap
metadata:
  name: devops-agent-operator-config
  namespace: devops-agent-operator-system
  labels:
    app.kubernetes.io/name: devops-agent-operator
data:
  # V1 scope: only the demo namespace is processed.
  WATCH_NAMESPACES: "reliability-lab"
  EXCLUDE_NAMESPACES: "kube-system,kube-public,kube-node-lease"
  # Node evidence (kubelet, containerd, dmesg/OOM) via SSM Run Command.
  ENABLE_SSM_COLLECTION: "true"
  AWS_REGION: "${AWS_REGION}"
  WEBHOOK_TIMEOUT: "30s"
  PROCESSED_TTL: "1h"
  LOG_SINCE_MINUTES: "15"
  # Filters left empty on purpose: every detected failure is reported in V1.
  WEBHOOK_SKIP_CATEGORIES: ""
  WEBHOOK_MIN_SEVERITY: ""
