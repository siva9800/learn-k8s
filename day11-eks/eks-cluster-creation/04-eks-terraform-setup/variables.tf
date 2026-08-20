###############################################################################
# Inputs. Sensible production-ish defaults; override in terraform.tfvars.
###############################################################################

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster (also used as a resource/tag prefix)."
  type        = string
  default     = "demo-eks"
}

variable "cluster_version" {
  description = "Kubernetes minor version for the control plane."
  type        = string
  default     = "1.30"
}

variable "environment" {
  description = "Environment tag (dev/staging/prod)."
  type        = string
  default     = "dev"
}

# --- Networking -------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Must NOT overlap peered/on-prem networks."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "How many Availability Zones to spread across (2 min, 3 recommended)."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "az_count must be between 2 and 4 (use >=2 for HA)."
  }
}

variable "single_nat_gateway" {
  description = "true = one shared NAT (cheap, non-HA). false = one NAT per AZ (HA, costlier). Use false for prod."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. LOCK THIS DOWN to your office/VPN. Default is open — override it."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# --- Node group -------------------------------------------------------------

variable "node_instance_types" {
  description = "Instance types for the managed node group. Multiple types improve spot availability."
  type        = list(string)
  default     = ["t3.medium", "t3a.medium"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND (stable) or SPOT (cheap, interruptible). Use SPOT only for fault-tolerant workloads."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "node_min_size" {
  description = "Minimum nodes in the group."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum nodes the group can scale to."
  type        = number
  default     = 5
}

variable "node_desired_size" {
  description = "Initial desired node count."
  type        = number
  default     = 2
}

# --- Tags -------------------------------------------------------------------

variable "tags" {
  description = "Extra tags applied to all resources."
  type        = map(string)
  default     = {}
}
