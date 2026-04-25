output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_oidc_issuer_url" {
  value = module.eks.cluster_oidc_issuer_url
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "kubeconfig_command" {
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
  description = "kubeconfig 등록 명령"
}

output "karpenter_iam_role_arn" {
  value = module.karpenter.iam_role_arn
}

output "lb_controller_iam_role_arn" {
  value = module.lb_controller_irsa.iam_role_arn
}

output "keda_iam_role_arn" {
  value = module.keda_irsa.iam_role_arn
}
