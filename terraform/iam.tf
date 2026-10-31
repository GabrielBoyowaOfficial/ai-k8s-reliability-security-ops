# ---------------------------------------------------------------------------
# Shared trust policy: EKS Pod Identity.
# sts:TagSession is required by Pod Identity in addition to sts:AssumeRole.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    sid     = "AllowEksPodIdentity"
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------------------
# DevOps Agent Operator role (workload identity, NOT the node role)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "operator" {
  name               = "${var.project_name}-devops-agent-operator"
  description        = "Assumed by the devops-agent-operator service account through EKS Pod Identity."
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

data "aws_iam_policy_document" "operator" {
  # V1 lab scope: Run Command is allowed against EC2 instances in this
  # account/region. Production deployments should narrow this further.
  statement {
    sid       = "SsmSendCommandToRegionalInstances"
    effect    = "Allow"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ec2:${var.region}:${local.account_id}:instance/*"]
  }

  # SendCommand is authorised against the document as well. Only the AWS-owned
  # AWS-RunShellScript document is allowed (AWS-owned ARNs have no account ID).
  statement {
    sid       = "SsmSendCommandDocument"
    effect    = "Allow"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ssm:${var.region}::document/AWS-RunShellScript"]
  }

  # WILDCARD REQUIRED: ssm:GetCommandInvocation does not support resource-level
  # permissions (Service Authorization Reference lists no resource types), so a
  # scoped ARN would never match. Exposure is limited to reading the output of
  # commands this role is already allowed to send.
  statement {
    sid       = "SsmReadCommandResults"
    effect    = "Allow"
    actions   = ["ssm:GetCommandInvocation"]
    resources = ["*"]
  }

  statement {
    sid       = "EvidenceBucketWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.incident_evidence.arn}/*"]
  }

  statement {
    sid       = "EvidenceBucketList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.incident_evidence.arn]
  }

  # Only this one log group. The log group is pre-created by Terraform so
  # logs:CreateLogGroup is intentionally NOT granted.
  statement {
    sid       = "IncidentLogGroupWrite"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.incidents.arn}:*"]
  }
}

resource "aws_iam_role_policy" "operator" {
  name   = "devops-agent-operator"
  role   = aws_iam_role.operator.id
  policy = data.aws_iam_policy_document.operator.json
}

resource "aws_eks_pod_identity_association" "operator" {
  cluster_name    = module.eks.cluster_name
  namespace       = var.operator_namespace
  service_account = var.operator_service_account
  role_arn        = aws_iam_role.operator.arn

  # Needs the agent add-on (and therefore the cluster) to be in place.
  depends_on = [module.eks]
}
