# ---------------------------------------------------------------------------
# General
# ---------------------------------------------------------------------------
variable "region" {
  description = "AWS region for the lab. AWS DevOps Agent must be available here (or in the region where you create your Agent Space)."
  type        = string
  default     = "us-west-2"
}

variable "aws_profile" {
  description = "Optional named AWS CLI profile. Leave null to use the default credential chain."
  type        = string
  default     = null
}

variable "project_name" {
  description = "Project identifier used for the Project tag and resource naming."
  type        = string
  default     = "ai-k8s-reliability-security-ops"
}

variable "environment" {
  description = "Environment tag value."
  type        = string
  default     = "lab"
}

# ---------------------------------------------------------------------------
# Access control
# ---------------------------------------------------------------------------
variable "admin_cidr" {
  description = "Your public IP in CIDR form (for example 203.0.113.10/32). Only this range can reach the public EKS API endpoint. No default on purpose."
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0))
    error_message = "admin_cidr must be a valid CIDR block, for example 203.0.113.10/32."
  }

  validation {
    condition     = var.admin_cidr != "0.0.0.0/0" && var.admin_cidr != "::/0"
    error_message = "admin_cidr must not be open to the whole internet."
  }
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block of the dedicated VPC."
  type        = string
  default     = "10.50.0.0/16"
}

variable "single_nat_gateway" {
  description = "true = one shared NAT gateway (cheapest, lab default). false = one NAT gateway per AZ (resilient, ~2x NAT cost)."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# EKS
# ---------------------------------------------------------------------------
variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
  default     = "ai-k8s-ops-lab"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version. Check the EKS version calendar; pick a version in standard support."
  type        = string
  default     = "1.36"
}

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_min_size" {
  description = "Minimum nodes."
  type        = number
  default     = 1
}

variable "node_desired_size" {
  description = "Desired nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum nodes."
  type        = number
  default     = 3
}

variable "control_plane_log_retention_days" {
  description = "Retention for EKS control-plane logs in CloudWatch."
  type        = number
  default     = 14
}

variable "enable_enhanced_container_insights" {
  description = "Enable enhanced Container Insights in the CloudWatch Observability add-on (extra per-observation metric cost)."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Incident evidence
# ---------------------------------------------------------------------------
variable "incident_log_group_name" {
  description = "CloudWatch log group the Operator writes incident events to."
  type        = string
  default     = "/ai-k8s-ops/devops-agent/incidents"
}

variable "incident_log_retention_days" {
  description = "Retention for the incident log group."
  type        = number
  default     = 14
}

variable "incident_evidence_retention_days" {
  description = "Days before incident evidence objects in S3 expire."
  type        = number
  default     = 14
}

variable "operator_namespace" {
  description = "Namespace the DevOps Agent Operator runs in."
  type        = string
  default     = "devops-agent-operator-system"
}

variable "operator_service_account" {
  description = "Service account the Operator runs as (bound to the Pod Identity role)."
  type        = string
  default     = "devops-agent-operator"
}

# ---------------------------------------------------------------------------
# ECR
# ---------------------------------------------------------------------------
variable "operator_ecr_repository_name" {
  description = "ECR repository for the DevOps Agent Operator image."
  type        = string
  default     = "ai-k8s-ops/devops-agent-operator"
}

variable "demo_ecr_repository_name" {
  description = "ECR repository for the memory-leak-demo image."
  type        = string
  default     = "ai-k8s-ops/memory-leak-demo"
}

# ---------------------------------------------------------------------------
# Optional: connect the AWS DevOps Agent to this cluster (second apply)
# ---------------------------------------------------------------------------
variable "devops_agent_role_arn" {
  description = <<-EOT
    Optional. ARN of the IAM role of your AWS DevOps Agent Agent Space (primary cloud source).
    The role only exists after you create the Agent Space, so leave this empty on the first apply
    and set it afterwards. When set, Terraform (a) creates a READ-ONLY EKS access entry for it
    (AmazonAIOpsAssistantPolicy) and (b) attaches a read-only policy for the incident evidence.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.devops_agent_role_arn == "" || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+", var.devops_agent_role_arn))
    error_message = "devops_agent_role_arn must be empty or a valid IAM role ARN."
  }
}
