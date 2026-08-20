###############################################################################
# Outputs. `terraform output` after apply; use the update-kubeconfig command
# to start talking to the cluster.
###############################################################################

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes control-plane version."
  value       = module.eks.cluster_version
}

output "cluster_certificate_authority_data" {
  description = "Base64 CA cert for the cluster (used inside kubeconfig)."
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the control plane."
  value       = module.eks.cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN — needed when creating IRSA roles for your apps."
  value       = module.eks.oidc_provider_arn
}

output "vpc_id" {
  description = "VPC ID the cluster lives in."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (where nodes/pods run)."
  value       = module.vpc.private_subnets
}

# The exact command to configure kubectl for this cluster.
output "configure_kubectl" {
  description = "Run this to point kubectl at the new cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
