################################################################################
# General EKS Cluster Info
################################################################################

variable "cluster_name" {
  type        = string
  description = "The name of the EKS cluster."

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must not be empty."
  }
}

variable "cluster_endpoint" {
  type        = string
  description = "The endpoint URL for the EKS cluster API server."

  validation {
    condition     = can(regex("^https://", var.cluster_endpoint))
    error_message = "cluster_endpoint must start with 'https://'."
  }
}

variable "tags" {
  type        = map(string)
  description = "(Optional) A map of tags to assign to the resources."
  default     = {}
}


################################################################################
# Karpenter Controller Configuration
################################################################################

variable "karpenter_version" {
  type        = string
  description = "The version of Karpenter to deploy via Helm."
  default     = "1.14.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+(-[a-zA-Z0-9.]+)?$", var.karpenter_version))
    error_message = "karpenter_version must be a valid semver version string (e.g., 1.14.0)."
  }
}

variable "karpenter_namespace" {
  type        = string
  description = "The namespace where Karpenter will be installed."
  default     = "karpenter"

  validation {
    condition     = length(var.karpenter_namespace) > 0
    error_message = "karpenter_namespace must not be empty."
  }
}

variable "karpenter_service_account" {
  type        = string
  description = "The name of the service account for Karpenter controller."
  default     = "karpenter"
}


################################################################################
# IAM / Authentication Configurations (IRSA & Pod Identity)
################################################################################

variable "enable_irsa" {
  type        = bool
  description = "Whether to create/configure IAM Roles for Service Accounts (IRSA)."
  default     = true
}

variable "oidc_provider_arn" {
  type        = string
  description = "OIDC provider ARN for the EKS cluster (Required if enable_irsa is true)."
  default     = null
}

variable "oidc_provider_url" {
  type        = string
  description = "OIDC provider URL for the EKS cluster (Required if enable_irsa is true)."
  default     = null
}

variable "enable_pod_identity" {
  type        = bool
  description = "Whether to configure EKS Pod Identity association for the controller."
  default     = false
}

variable "pod_identity_association_role_arn" {
  type        = string
  description = "An existing IAM role ARN to use for Pod Identity. If null, a new role will be created."
  default     = null
}


################################################################################
# Spot Interruption / Event Handling Configuration
################################################################################

variable "enable_spot_interruption_handler" {
  type        = bool
  description = "Whether to enable the SQS queue and EventBridge rules for Karpenter Spot interruption/rebalance handling."
  default     = true
}

variable "sqs_queue_name" {
  type        = string
  description = "(Optional) Custom name for the SQS interruption queue. Defaults to the cluster name."
  default     = null
}


################################################################################
# Node IAM Role and Instance Profile Configuration
################################################################################

variable "create_node_iam_role" {
  type        = bool
  description = "Whether to create the IAM role for the Karpenter worker nodes."
  default     = true
}

variable "node_iam_role_name" {
  type        = string
  description = "The name of the Karpenter node IAM role. Defaults to KarpenterNodeRole-<cluster_name>."
  default     = null
}

variable "node_iam_role_arn" {
  type        = string
  description = "Existing IAM role ARN for nodes (must be provided if create_node_iam_role is false)."
  default     = null
}

variable "create_instance_profile" {
  type        = bool
  description = "Whether to create an IAM Instance Profile for nodes (for older Karpenter configurations)."
  default     = true
}

variable "node_iam_role_additional_policies" {
  type        = map(string)
  description = "A map of additional policy ARNs to attach to the Karpenter node IAM role."
  default     = {}
}


################################################################################
# Helm Configuration
################################################################################

variable "helm_release_name" {
  type        = string
  description = "The Helm release name for Karpenter."
  default     = "karpenter"
}

variable "helm_release_timeout" {
  type        = number
  description = "Helm release timeout in seconds."
  default     = 600
}

variable "helm_release_values" {
  type        = any
  description = "(Optional) Additional values to pass to the Karpenter Helm chart."
  default     = {}
}
