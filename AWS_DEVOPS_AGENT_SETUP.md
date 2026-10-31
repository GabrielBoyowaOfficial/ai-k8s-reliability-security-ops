# AWS DevOps Agent setup (manual prerequisites)

The Agent Space and its generic webhook are created in the AWS console. They are deliberately **not** in Terraform:

- AWS shows the webhook signing secret **once**, at creation or rotation, and does not return it later. Putting it through Terraform would store it in state.
- The webhook URL and secret must never be committed to Git.

Official reference: [Invoking DevOps Agent through Webhook](https://docs.aws.amazon.com/devopsagent/latest/userguide/configuring-integrations-and-knowledge-invoking-devops-agent-through-webhook.html) and [AWS EKS access setup](https://docs.aws.amazon.com/devopsagent/latest/userguide/configuring-integrations-and-knowledge-aws-eks-access-setup.html). If the console wording differs from this page, trust the AWS docs.

## 1. Create the Agent Space

1. Open the AWS DevOps Agent console in a [supported region](https://docs.aws.amazon.com/devopsagent/latest/userguide/about-aws-devops-agent.html) (us-west-2 is supported at the time of writing).
2. Create an Agent Space (for example `ai-k8s-reliability-lab`) and let the console create its IAM role. Use the same AWS account as the lab as the primary cloud source.
3. Note the **Primary Cloud Source IAM role ARN** (Capabilities > Cloud > Primary Source > Edit). Do not use the similarly named WebAppAdmin/operator-access role, and do not configure an Actions role for V1.

## 2. Create the generic webhook (HMAC)

1. Agent Space > **Capabilities** tab > **Agent Space Webhook** table > **Add webhook**.
2. Authentication type: **HMAC**. (The Operator signs with HMAC-SHA256 and sends `x-amzn-event-signature` and `x-amzn-event-timestamp`. The API-key type will not work with this Operator.)
3. Copy the **webhook URL** and the **signing secret** immediately. If you lose the secret, use *Actions > Edit > Rotate webhook* (the URL stays the same).
4. Export them in your shell only:

```bash
export DEVOPS_AGENT_WEBHOOK_URL="https://...copied-from-console..."
export DEVOPS_AGENT_WEBHOOK_SECRET="...copied-from-console..."
```

`scripts/configure-webhook.sh` (called by `deploy.sh`) turns these into the Kubernetes Secret `devops-agent-operator-webhook` after the cluster exists. Nothing is written to disk, Git, or Terraform state.

Limits worth knowing: one HMAC webhook per Agent Space; duplicate `incidentId`s are de-duplicated; a monthly investigation quota applies.

## 3. Let the Agent read the evidence and the cluster

The webhook payload sent to the agent carries only the title, description, priority, and incident reference. The `data` object is not forwarded. The Operator therefore puts the S3 location of the evidence in the description, and the Agent must be able to read it.

After the Agent Space exists, set its role ARN in `terraform/terraform.tfvars` and re-apply:

```hcl
devops_agent_role_arn = "arn:aws:iam::<account-id>:role/<agent-space-role>"
```

This creates, all read-only:

- an attachment of `ai-k8s-reliability-security-ops-devops-agent-evidence-read` (S3 `GetObject`/`ListBucket` on the evidence bucket, `logs:GetLogEvents`/`FilterLogEvents`/`DescribeLogStreams` on the incident log group) to that role;
- an EKS access entry for the role with the AWS-managed `AmazonAIOpsAssistantPolicy` at cluster scope, so the Agent can run read-only kubectl during investigations.

Prefer to do it by hand? Attach the policy ARN from `terraform output devops_agent_evidence_read_policy_arn` and create the access entry in the EKS console (Access tab), as described in the AWS EKS access setup page. The cluster authentication mode here is `API_AND_CONFIG_MAP`, which supports access entries.

## 4. CloudWatch

The Agent Space's primary cloud source role already gives the agent AWS read access (including CloudWatch metrics and logs) in this account. Container Insights data from the CloudWatch Observability add-on is then queryable by the agent. If you see access errors for CloudWatch, check the role and the console's Cloud capability page.

## 5. Optional: GitHub

Connect this repository (Capabilities > Pipeline / source code, per the console) so the agent can correlate the incident with `apps/memory-leak-demo/app.py`, the Dockerfile, the Kubernetes manifests, the Terraform, and recent commits. Not required for V1 to work.

## 6. Optional: Slack

Connect Slack from the Capabilities tab if you want investigation notifications in a channel. Not required for V1. (Integration webhooks created this way are separate from the generic webhook.)

## Quick manual webhook test

Before deploying, confirm the URL and secret work (a `200` means authentication passed). This creates a real test investigation and may consume quota:

```bash
TS=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
BODY="{\"eventType\":\"incident\",\"incidentId\":\"manual-test-$(date +%s)\",\"action\":\"created\",\"priority\":\"LOW\",\"title\":\"Webhook connectivity test\",\"description\":\"Manual test from setup guide\",\"service\":\"EKS\",\"timestamp\":\"$TS\"}"
SIG=$(printf '%s' "$TS:$BODY" | openssl dgst -sha256 -hmac "$DEVOPS_AGENT_WEBHOOK_SECRET" -binary | base64)
curl -sS -o /dev/null -w '%{http_code}\n' -X POST "$DEVOPS_AGENT_WEBHOOK_URL" \
  -H "Content-Type: application/json" -H "x-amzn-event-timestamp: $TS" \
  -H "x-amzn-event-signature: $SIG" -d "$BODY"
```


## 7. Find the investigation in the Web App

The management console configures the Agent Space, but completed webhook investigations appear in the Agent Space **Web App**. Open the Agent Space **Access** tab and choose **Launch via IAM** (or your configured user-access path), then open **Incidents**.

A successful V1 incident is titled similar to:

```text
Pod OOMKilled: reliability-lab/memory-leak-demo-...
```

The investigation should show the summary, timeline, root cause, and a proposed mitigation plan. V1 intentionally leaves the mitigation unexecuted because no Agent Actions role is configured.
