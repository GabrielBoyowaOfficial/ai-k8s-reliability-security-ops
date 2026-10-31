# ---------------------------------------------------------------------------
# Glue between this lab and the AWS DevOps Agent Agent Space.
#
# The Agent Space and its generic webhook are created manually (see
# docs/AWS_DEVOPS_AGENT_SETUP.md) because the webhook secret is shown only once
# and must never enter Terraform state. What CAN be declared safely is
# "what the Agent Space role is allowed to read in this lab", so that is here.
# ---------------------------------------------------------------------------

# The webhook payload only carries a title/description with the S3 location
# (the `data` object is not forwarded to the agent). For the agent to read the
# evidence it needs read access to the bucket and the incident log group.
data "aws_iam_policy_document" "devops_agent_evidence_read" {
  statement {
    sid       = "ReadIncidentEvidenceObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["${aws_s3_bucket.incident_evidence.arn}/*"]
  }

  statement {
    sid       = "ListIncidentEvidence"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.incident_evidence.arn]
  }

  statement {
    sid       = "ReadIncidentLogs"
    effect    = "Allow"
    actions   = ["logs:GetLogEvents", "logs:FilterLogEvents", "logs:DescribeLogStreams"]
    resources = [aws_cloudwatch_log_group.incidents.arn, "${aws_cloudwatch_log_group.incidents.arn}:*"]
  }
}

resource "aws_iam_policy" "devops_agent_evidence_read" {
  name        = "${var.project_name}-devops-agent-evidence-read"
  description = "Read-only access to the incident evidence bucket and incident log group. Attach to the Agent Space role."
  policy      = data.aws_iam_policy_document.devops_agent_evidence_read.json
}

# ----- Optional, enabled by setting var.devops_agent_role_arn ---------------

resource "aws_iam_role_policy_attachment" "devops_agent_evidence_read" {
  count = var.devops_agent_role_arn == "" ? 0 : 1

  role       = local.devops_agent_role_name
  policy_arn = aws_iam_policy.devops_agent_evidence_read.arn
}

# Lets the Agent run read-only kubectl against the cluster during investigations.
# AmazonAIOpsAssistantPolicy is the access policy AWS documents for DevOps Agent.
resource "aws_eks_access_entry" "devops_agent" {
  count = var.devops_agent_role_arn == "" ? 0 : 1

  cluster_name  = module.eks.cluster_name
  principal_arn = var.devops_agent_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "devops_agent" {
  count = var.devops_agent_role_arn == "" ? 0 : 1

  cluster_name  = module.eks.cluster_name
  principal_arn = var.devops_agent_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonAIOpsAssistantPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.devops_agent]
}
