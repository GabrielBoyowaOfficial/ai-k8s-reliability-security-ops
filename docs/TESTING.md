# Testing the V1 workflow

Run these after `./scripts/deploy.sh` completes.

## 1. Cluster health

```bash
kubectl get nodes                                   # all Ready
kubectl -n kube-system get pods -l app.kubernetes.io/name=eks-pod-identity-agent
kubectl -n amazon-cloudwatch get pods               # cloudwatch-agent, fluent-bit Running
kubectl -n devops-agent-operator-system get pods    # operator Running 1/1
kubectl -n devops-agent-operator-system logs deploy/devops-agent-operator --tail=20
aws eks list-pod-identity-associations --cluster-name ai-k8s-ops-lab --region us-west-2
```

## 2. Watch the OOM

```bash
./scripts/test-oom.sh watch
```

Expect `memory-leak-demo-...` Running, then `OOMKilled`, restart count 1, and later `CrashLoopBackOff`. About 1.5-2 minutes to the first kill.

```bash
kubectl -n reliability-lab describe pod -l app.kubernetes.io/name=memory-leak-demo | grep -A6 "Last State"
# Reason: OOMKilled   Exit Code: 137
kubectl -n reliability-lab logs -l app.kubernetes.io/name=memory-leak-demo --previous --tail=5
kubectl -n reliability-lab get events --sort-by=.lastTimestamp
```

## 3. Operator, CloudWatch, S3

```bash
./scripts/test-oom.sh verify
```

Manual equivalents:

```bash
kubectl -n devops-agent-operator-system logs deploy/devops-agent-operator | grep -i -E "oom|webhook|s3|cloudwatch"
aws logs tail /ai-k8s-ops/devops-agent/incidents --since 1h --region us-west-2
aws s3 ls s3://<incident_bucket_name>/incidents/ --recursive --region us-west-2
```

Expected S3 layout: `incidents/<timestamp>/reliability-lab/<pod>/collected-data.json`, `failure-info.json`, `pod-manifest.yaml`, `pod-describe.yaml`, `logs/`, `node-logs/dmesg.log`, `node-logs/mem-usage.txt`, and others.

## 4. DevOps Agent

Open the Agent Space in the AWS DevOps Agent console. A new investigation titled like `Pod OOMKilled: reliability-lab/memory-leak-demo-...` should appear. Expected conclusion: the container exceeded its 64Mi limit because the app keeps allocating memory.

## Troubleshooting

| Symptom | Check |
|---|---|
| Operator CrashLoop: "DEVOPS_AGENT_WEBHOOK_URL is required" | Secret missing; rerun `./scripts/configure-webhook.sh` |
| Operator logs `AccessDenied` for SSM | Confirm the Operator Pod Identity association, Operator IAM policy, node SSM managed-instance status, and region/account scope |
| `NoCredentialProviders` in Operator | Pod Identity agent not running, or pod started before the association existed: `kubectl rollout restart` |
| Webhook returns 401/403 | Wrong secret or auth type is not HMAC; rotate in console |
| Webhook 200 but no investigation | Duplicate `incidentId`, or monthly quota reached |
| No SSM node logs | Nodes not SSM-managed: `aws ssm describe-instance-information` |
| Agent cannot open the S3 files | `devops_agent_role_arn` not set / policy not attached |
| `kubectl` times out | Your IP changed; update `admin_cidr` and `terraform apply` |
