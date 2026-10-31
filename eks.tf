module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.29"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Public endpoint is limited to the administrator's IP. The private endpoint
  # is also enabled so worker nodes (in private subnets) reach the API server
  # inside the VPC instead of hairpinning through the NAT gateway.
  endpoint_public_access       = true
  endpoint_public_access_cidrs = [var.admin_cidr]
  endpoint_private_access      = true

  # Everything useful for reliability + security investigations.
  enabled_log_types                      = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  create_cloudwatch_log_group            = true
  cloudwatch_log_group_retention_in_days = var.control_plane_log_retention_days

  # Short deletion window so repeated lab create/destroy cycles do not leave
  # KMS keys lingering for 30 days.
  kms_key_deletion_window_in_days = 7

  # Gives the identity running `terraform apply` kubectl admin access through
  # an EKS access entry (no aws-auth ConfigMap editing).
  enable_cluster_creator_admin_permissions = true

  addons = {
    # Pod Identity agent must exist before any workload asks for credentials.
    eks-pod-identity-agent = {
      before_compute = true
    }
    vpc-cni = {
      before_compute = true
    }
    kube-proxy = {}
    coredns    = {}

    amazon-cloudwatch-observability = {
      # Credentials come from EKS Pod Identity, not from the node role.
      pod_identity_association = [{
        role_arn        = aws_iam_role.cloudwatch_agent.arn
        service_account = "cloudwatch-agent"
      }]

      configuration_values = var.enable_enhanced_container_insights ? jsonencode({
        agent = {
          config = {
            logs = {
              metrics_collected = {
                kubernetes = {
                  enhanced_container_insights = true
                }
              }
            }
          }
        }
      }) : null
    }
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.node_min_size
      desired_size = var.node_desired_size
      max_size     = var.node_max_size

      # The Operator collects kernel / kubelet / containerd evidence through
      # SSM Run Command, so nodes must be SSM managed instances.
      iam_role_additional_policies = {
        ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }

      # Useful inventory metadata. V1 does not depend on this tag for SSM authorization.
      tags = {
        (local.node_cluster_tag_key) = var.cluster_name
      }

      # IMDSv2 required with hop limit 1 (module default): pods cannot reach
      # the node role credentials. Pods get credentials from Pod Identity only.
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }
    }
  }
}
