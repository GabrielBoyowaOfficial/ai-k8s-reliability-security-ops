# Manual build walkthrough

This path is for learning the architecture before relying on Terraform. It follows the same V1 design as the IaC path and intentionally keeps remediation out of scope.

## Phase 1 — Network foundation

Create a VPC in `us-west-2`:

```text
VPC CIDR: 10.50.0.0/16
2 Availability Zones
2 public subnets
2 private subnets
1 Internet Gateway
1 shared NAT Gateway
```

Enable DNS hostnames and DNS resolution. Route public subnets to the Internet Gateway and private subnets to the NAT Gateway.

Tag public subnets:

```text
kubernetes.io/role/elb = 1
```

Tag private subnets:

```text
kubernetes.io/role/internal-elb = 1
```

## Phase 2 — EKS control plane

Create an EKS cluster IAM role trusted by `eks.amazonaws.com` with:

```text
AmazonEKSClusterPolicy
```

Create the cluster:

```text
Name: ai-k8s-ops-lab
Region: us-west-2
Kubernetes: 1.36 (or the configured supported version)
EKS Auto Mode: off
Private endpoint: enabled
Public endpoint: enabled
```

For a reusable environment, restrict the public endpoint to your `/32`. A temporary lab may use a broader CIDR at your own risk.

Enable all five EKS control-plane log types:

```text
api
audit
authenticator
controllerManager
scheduler
```

## Phase 3 — Managed EC2 worker nodes

Create a node IAM role trusted by `ec2.amazonaws.com` with:

```text
AmazonEKSWorkerNodePolicy
AmazonEC2ContainerRegistryPullOnly
AmazonSSMManagedInstanceCore
```

Create an EKS managed node group in the private subnets:

```text
Instance type: t3.medium
Capacity: On-Demand
Min: 1
Desired: 2
Max: 3
AMI: Amazon Linux 2023 EKS optimized
SSH: disabled
```

## Phase 4 — VPC CNI Pod Identity

Create a dedicated IAM role trusted by `pods.eks.amazonaws.com` with:

```text
sts:AssumeRole
sts:TagSession
```

Attach:

```text
AmazonEKS_CNI_Policy
```

Create the EKS Pod Identity association:

```text
Namespace: kube-system
Service account: aws-node
```

Verify:

```bash
kubectl get nodes
kubectl get pods -n kube-system
```

The `aws-node` pods should be healthy and all EC2 nodes should become `Ready`.

## Phase 5 — CloudWatch Observability

Create another Pod Identity role trusted by `pods.eks.amazonaws.com` and attach:

```text
CloudWatchAgentServerPolicy
```

Install the `amazon-cloudwatch-observability` EKS add-on and associate the role with:

```text
Namespace: amazon-cloudwatch
Service account: cloudwatch-agent
```

Verify:

```bash
kubectl get pods -n amazon-cloudwatch
```

Then check CloudWatch -> Container Insights for node/pod CPU and memory telemetry.

## Phase 6 — Incident evidence destinations

Create a private S3 bucket for incident evidence with:

```text
Block Public Access: on
Encryption: on
Versioning: on
Lifecycle expiration: 14 days
```

Create the CloudWatch log group:

```text
/ai-k8s-ops/devops-agent/incidents
Retention: 14 days
```

## Phase 7 — Operator IAM

Create a Pod Identity role for the Operator, trusted by `pods.eks.amazonaws.com`.

For this disposable lab, the role needs:

- `s3:PutObject` and `s3:ListBucket` on the evidence bucket;
- `logs:CreateLogStream` and `logs:PutLogEvents` on the incident log group;
- `ssm:SendCommand` on EC2 instances in the account/region plus the AWS-owned `AWS-RunShellScript` document;
- `ssm:GetCommandInvocation` with `Resource: "*"` because the action does not support resource-level scoping.

The lab intentionally does **not** require an `EksCluster=<name>` tag condition on `ssm:SendCommand`. Production environments should narrow node command execution further.

## Phase 8 — ECR and Operator image

Create a private ECR repository:

```text
ai-k8s-ops/devops-agent-operator
```

Use immutable tags and image scanning.

Build the pinned AWS sample Operator from:

```text
aws-samples/kr-tech-blog-sample-code
containers/devops-agent-operator
commit: 6bfdfbc0a5b3db43f6b554e03b4b26780c539fe3
```

You can build locally or use the optional temporary EC2 builder in [EC2_BUILD_SERVER.md](EC2_BUILD_SERVER.md).

## Phase 9 — AWS DevOps Agent

Create an Agent Space in `us-west-2`.

Use the **Primary Cloud Source role** (not the WebAppAdmin role and not an Actions role) for EKS investigation access.

Create an EKS access entry:

```text
Type: Standard
Policy: AmazonAIOpsAssistantPolicy
Scope: Cluster
```

Do not configure an Agent Actions role for V1; V1 is investigation-only.

Create a **Generic webhook** with **HMAC** authentication and save the generated URL/secret.

## Phase 10 — Deploy the Operator

Create:

```text
Namespace: devops-agent-operator-system
Service account: devops-agent-operator
```

Associate the Operator Pod Identity role with that service account.

Create the `reliability-lab` namespace and apply the Operator RBAC, ConfigMap, HMAC Kubernetes Secret, and Deployment from this repository.

Verify:

```bash
kubectl get pods -n devops-agent-operator-system
kubectl logs deployment/devops-agent-operator -n devops-agent-operator-system --tail=100
```

Look for initialization of SSM, S3, CloudWatch Logs, and the webhook client.

## Phase 11 — Trigger OOMKilled

Deploy the memory leak demo from `kubernetes/apps/memory-leak-demo.yaml.tpl` or build/push the included demo image first.

Watch:

```bash
kubectl get pods -n reliability-lab -w
```

Expected progression:

```text
Running -> OOMKilled -> Running -> OOMKilled -> CrashLoopBackOff
```

Confirm:

```text
Reason: OOMKilled
Exit Code: 137
```

## Phase 12 — Verify the incident pipeline

Operator logs should show:

```text
Failure detected
SSM commands sent/succeeded
CloudWatch upload completed
S3 upload completed
Webhook request successful (HTTP 200)
Pod failure processed successfully
```

S3 should contain files such as:

```text
collected-data.json
failure-info.json
pod-manifest.yaml
pod-describe.yaml
logs/*-previous.log
node-logs/kubelet.log
node-logs/containerd.log
node-logs/dmesg.log
node-logs/ipamd.log
node-logs/ipamd-introspection.log
node-logs/networking.txt
node-logs/disk-usage.txt
node-logs/inode-usage.txt
node-logs/mem-usage.txt
```

Open the DevOps Agent Web App -> **Incidents**. A successful V1 should show an investigation titled similar to:

```text
Pod OOMKilled: reliability-lab/memory-leak-demo-...
```

The investigation should distinguish an application memory leak from a cluster/node health problem and provide a mitigation recommendation.

When finished, scale the demo to zero or destroy the lab.
