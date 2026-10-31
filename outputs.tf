# No secrets are exposed here. The DevOps Agent webhook URL/secret never touch Terraform.

output "region" {
  description = "AWS region."
  value       = var.region
}

output "aws_account_id" {
  description = "AWS account ID (read dynamically, used by the Operator metadata)."
  value       = local.account_id
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (worker nodes live here)."
  value       = module.vpc.private_subnets
}

output "eks_cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "operator_ecr_repository_url" {
  description = "ECR repository URL for the DevOps Agent Operator image."
  value       = aws_ecr_repository.this["operator"].repository_url
}

output "demo_ecr_repository_url" {
  description = "ECR repository URL for the memory-leak-demo image."
  value       = aws_ecr_repository.this["demo"].repository_url
}

output "incident_bucket_name" {
  description = "S3 bucket holding incident evidence."
  value       = aws_s3_bucket.incident_evidence.id
}

output "incident_log_group_name" {
  description = "CloudWatch log group holding incident events."
  value       = aws_cloudwatch_log_group.incidents.name
}

output "operator_role_arn" {
  description = "IAM role assumed by the Operator through EKS Pod Identity."
  value       = aws_iam_role.operator.arn
}

output "devops_agent_evidence_read_policy_arn" {
  description = "Attach this to your Agent Space role (or set devops_agent_role_arn and re-apply)."
  value       = aws_iam_policy.devops_agent_evidence_read.arn
}
