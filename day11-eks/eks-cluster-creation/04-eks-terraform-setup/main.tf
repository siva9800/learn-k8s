###############################################################################
# EKS via terraform-aws-modules — production-shaped, commented for teaching.
#
# What this builds:
#   - A multi-AZ VPC (public + private subnets, single NAT for cost)
#   - An EKS control plane (public+private endpoint, CIDR-locked)
#   - A managed node group in PRIVATE subnets (spot-capable)
#   - IRSA (OIDC) enabled + core EKS add-ons (CNI, CoreDNS, kube-proxy, EBS CSI)
#   - EKS Access Entries (modern auth; grants the applier admin)
#
# Module docs:
#   VPC : https://github.com/terraform-aws-modules/terraform-aws-vpc
#   EKS : https://github.com/terraform-aws-modules/terraform-aws-eks
###############################################################################

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Recommended for real projects — store state in S3 with locking.
  # Uncomment and set your own bucket/table, then `terraform init -migrate-state`.
  # backend "s3" {
  #   bucket       = "my-tfstate-bucket"
  #   key          = "eks/terraform.tfstate"
  #   region       = "ap-south-1"
  #   use_lockfile = true          # S3-native state locking (no DynamoDB needed)
  #   encrypt      = true
  # }
}

provider "aws" {
  region = var.region
}

# Look up AZs so we spread subnets across the first N automatically.
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  # Take the first `az_count` AZs in the region (default 3).
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  tags = merge(var.tags, {
    Project     = var.cluster_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

###############################################################################
# VPC
#   - Private subnets host nodes+pods; public subnets host NAT + load balancers.
#   - Subnet tags let EKS/LB-controller auto-discover subnets for ELBs.
#   - Big private subnets (/20 each) because the VPC CNI gives every POD a VPC IP.
###############################################################################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]      # /20s
  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 48)] # /24s

  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway # true = 1 NAT (cheap); false = 1/AZ (HA)
  enable_dns_hostnames = true

  # Required so the AWS Load Balancer Controller can place ELBs correctly.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = local.tags
}

###############################################################################
# EKS CLUSTER
###############################################################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # --- API endpoint: public+private, but public locked to known CIDRs. ---
  cluster_endpoint_public_access       = true
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access_cidrs = var.public_access_cidrs # e.g. ["203.0.113.10/32"]

  # IRSA: give pods their own IAM roles via the cluster OIDC provider.
  enable_irsa = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets # nodes run in PRIVATE subnets

  # Core managed add-ons — kept in step with the control plane version.
  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni = {
      most_recent = true
      # Prefix delegation → many more pod IPs per node (delays IP exhaustion).
      configuration_values = jsonencode({
        env = { ENABLE_PREFIX_DELEGATION = "true" }
      })
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  # Turn on control-plane logs (auth/audit are the ones you'll actually need).
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Encrypt Kubernetes Secrets at rest with a KMS key (module creates one).
  cluster_encryption_config = {
    resources = ["secrets"]
  }

  # --- Modern auth: Access Entries instead of the fragile aws-auth ConfigMap. ---
  authentication_mode                      = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions = true # whoever applies gets admin
  # For least privilege, set this to false and grant admin to a dedicated role via
  # an `access_entries` block instead - see 05-connecting-to-the-cluster.md
  # ("What if the creator was NOT granted admin?"). You are not locked out: access
  # entries are governed by AWS IAM, not kubectl.

  # --- Managed node group in private subnets. ---
  eks_managed_node_group_defaults = {
    ami_type = "AL2023_x86_64_STANDARD"
    # Enforce IMDSv2 + hop limit 1 so pods can't steal the node role creds.
    metadata_options = {
      http_endpoint               = "enabled"
      http_tokens                 = "required"
      http_put_response_hop_limit = 1
    }
  }

  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      capacity_type  = var.node_capacity_type # "ON_DEMAND" or "SPOT"

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      labels = { role = "general" }
    }
  }

  tags = local.tags
}

###############################################################################
# IRSA role for the EBS CSI driver (least-privilege example of IRSA).
###############################################################################
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name             = "${var.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}
