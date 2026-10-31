# Security decisions

V1 is read/investigate first. The AWS DevOps Agent is not given an Actions role, and the Operator has no general-purpose Kubernetes administration capability.

| Area | Decision | Why |
|---|---|---|
| EKS API | Public endpoint restricted to `admin_cidr` (`0.0.0.0/0` is rejected by Terraform validation); private endpoint also enabled | Administrator access from the configured CIDR; nodes can reach the API privately |
| Nodes | Private subnets only; IMDSv2 required with hop limit 1 | Reduces direct node exposure and prevents pods from using node-role credentials through IMDS |
| VPC CNI identity | `aws-node` uses a dedicated EKS Pod Identity role with `AmazonEKS_CNI_Policy` | CNI permissions are not placed on the EC2 node role |
| Node role | EKS worker permissions, ECR pull, and SSM managed-instance core only | Keeps node permissions separate from pod permissions |
| CloudWatch identity | CloudWatch Observability add-on uses a dedicated Pod Identity role | Workload-specific credentials rather than node credentials |
| Operator identity | Operator uses a dedicated EKS Pod Identity role | Isolates evidence/SSM permissions from nodes and other pods |
| Operator SSM | `ssm:SendCommand` on EC2 instances in this account/region plus the AWS-owned `AWS-RunShellScript` document | Deliberately broad enough for a disposable lab and avoids dependence on a node tag condition |
| Documented wildcard | `ssm:GetCommandInvocation` uses `Resource: "*"` | The action does not support resource-level scoping |
| Accepted SSM risk | `AWS-RunShellScript` allows shell commands on eligible managed EC2 instances; the upstream Operator uses fixed evidence-collection commands | Required for kubelet/containerd/dmesg/node evidence. Production should restrict targets more aggressively |
| S3 evidence | `s3:PutObject`/`ListBucket` scoped to the incident evidence bucket | Limits evidence writes to the lab bucket |
| CloudWatch incident logs | `logs:CreateLogStream`/`PutLogEvents` scoped to the incident log group | Limits log writes to the lab incident group |
| Kubernetes RBAC | Cluster-wide read-only for watch/list needs; `patch pods` and `pods/log` only in `reliability-lab`; leader-election writes only in the Operator namespace | Narrow Kubernetes blast radius |
| Namespace scope | Operator processes only `reliability-lab` | Limits what evidence is intentionally collected |
| Evidence storage | Private S3 bucket, Block Public Access, SSE-S3, versioning, TLS-only policy, ACLs disabled, 14-day expiry; log group 14-day retention | Short-lived, private evidence |
| Evidence content | Pod specs/logs can contain sensitive runtime data | Review before pointing the Operator at real workloads |
| Webhook secret | Supplied at deploy time and written only to a Kubernetes Secret; not stored in Git, tfvars, or Terraform state | AWS displays the HMAC secret once; state files are not an appropriate secret store |
| Kubernetes Secrets | Cluster encryption is provided by the EKS module configuration | Defense in depth for the webhook Secret |
| DevOps Agent access | Optional read-only EKS access with `AmazonAIOpsAssistantPolicy` plus evidence-read policy | Diagnosis before remediation |
| Agent Actions | Not configured in V1 | Prevents autonomous remediation while the investigation workflow is being proven |
| Images | ECR scan-on-push, immutable tags, pinned Operator commit, non-root containers, read-only root filesystem, capabilities dropped | Reproducible, hardened lab images |
| Supply chain | Operator is AWS sample code fetched at a pinned commit | Reproducibility; still review before production use |
| Temporary EC2 builder | Optional build-time helper only; terminate after push | Avoids making the build server part of the runtime trust boundary |

## Lab tradeoff: broad SSM target scope

For V1, the Operator role can send the fixed upstream SSM collection commands to EC2 instances in the same account and region. This is intentionally broader than a production policy because the lab is disposable and the goal is to make the investigation path easy to reproduce without depending on a particular node-tag propagation model.

A production implementation should reduce this scope with one or more of:

- a dedicated node instance profile/role condition;
- explicit instance tags applied directly to EC2 instances and used in SSM authorization;
- separate accounts/VPCs for the workload;
- stricter SSM documents or automation runbooks;
- additional approval/audit controls.

Not in V1: NetworkPolicies, VPC interface endpoints for every AWS service, GuardDuty/Security Hub, Agent Actions, approval workflow, GitOps remediation, or automated post-mortems.

Report issues through GitHub issues and never include webhook secrets, credentials, or private account details.
