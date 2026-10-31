# ---------------------------------------------------------------------------
# CloudWatch Observability add-on identity (Pod Identity)
# The add-on itself is declared in eks.tf; its association to this role is
# created by the add-on resource (pod_identity_association block).
# ---------------------------------------------------------------------------
resource "aws_iam_role" "cloudwatch_agent" {
  name               = "${var.project_name}-cloudwatch-agent"
  description        = "Assumed by the cloudwatch-agent service account (amazon-cloudwatch namespace) through EKS Pod Identity."
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.cloudwatch_agent.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# ---------------------------------------------------------------------------
# Incident log group written by the DevOps Agent Operator.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "incidents" {
  name              = var.incident_log_group_name
  retention_in_days = var.incident_log_retention_days
}
