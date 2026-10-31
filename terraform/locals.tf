data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"

  # Skip Local Zones / Wavelength zones, which cannot host EKS nodes.
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  azs        = slice(data.aws_availability_zones.available.names, 0, 2)

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # Deterministic and globally unique without a random suffix:
  # account ID + region are already unique per bucket.
  incident_bucket_name = "ai-k8s-incident-evidence-${local.account_id}-${var.region}"

  # Inventory tag placed on the managed node group / worker resources.
  # V1 does not use this tag as an SSM authorization boundary.
  node_cluster_tag_key = "EksCluster"

  # DevOps Agent availability, per AWS docs at the time of writing.
  devops_agent_regions = [
    "us-east-1", "us-west-2", "ap-southeast-2",
    "ap-northeast-1", "eu-central-1", "eu-west-1",
  ]

  devops_agent_role_name = var.devops_agent_role_arn == "" ? "" : element(split("/", var.devops_agent_role_arn), length(split("/", var.devops_agent_role_arn)) - 1)
}

# A warning (not an error) so the lab still works if AWS adds regions or you
# create the Agent Space in a different region than the cluster.
check "devops_agent_region" {
  assert {
    condition     = contains(local.devops_agent_regions, var.region)
    error_message = "Region ${var.region} is not in the known AWS DevOps Agent region list. The cluster can live anywhere, but create your Agent Space in a supported region."
  }
}
