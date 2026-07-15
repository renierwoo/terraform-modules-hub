################################################################################
# Controller IAM Outputs
################################################################################

output "controller_iam_role_arn" {
  description = "The ARN of the Karpenter Controller IAM Role."
  value       = try(aws_iam_role.controller[0].arn, var.pod_identity_association_role_arn)
}

output "controller_iam_role_name" {
  description = "The name of the Karpenter Controller IAM Role."
  value       = try(aws_iam_role.controller[0].name, null)
}

output "controller_iam_policy_arn" {
  description = "The ARN of the Karpenter Controller IAM Policy."
  value       = try(aws_iam_policy.controller[0].arn, null)
}


################################################################################
# Node IAM Outputs
################################################################################

output "node_iam_role_arn" {
  description = "The ARN of the Karpenter Node IAM Role."
  value       = local.node_role_arn
}

output "node_iam_role_name" {
  description = "The name of the Karpenter Node IAM Role."
  value       = local.node_role_name
}

output "node_instance_profile_name" {
  description = "The name of the Karpenter Node IAM Instance Profile."
  value       = try(aws_iam_instance_profile.node[0].name, null)
}

output "node_instance_profile_arn" {
  description = "The ARN of the Karpenter Node IAM Instance Profile."
  value       = try(aws_iam_instance_profile.node[0].arn, null)
}


################################################################################
# SQS Interruption Queue Outputs
################################################################################

output "sqs_queue_arn" {
  description = "The ARN of the SQS queue used for interruption/rebalance handling."
  value       = try(aws_sqs_queue.karpenter[0].arn, null)
}

output "sqs_queue_name" {
  description = "The name of the SQS queue used for interruption/rebalance handling."
  value       = try(aws_sqs_queue.karpenter[0].name, null)
}


################################################################################
# Helm Release Outputs
################################################################################

output "helm_release_metadata" {
  description = "Status metadata of the Karpenter Helm release."
  value       = helm_release.karpenter.metadata
}
