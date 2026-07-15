# Karpenter AWS EKS Terraform Module

This module automates the complete provisioning of Karpenter resources on AWS and deploys Karpenter to your EKS cluster via Helm, **without using third-party modules**.

It handles:
1. **Karpenter Controller IAM Role**: Consolidates the full, latest least-privilege policies (Node Lifecycle, IAM Integration, EKS Integration, Interruption handling, Zonal Shift, Resource Discovery) and connects it using either **IRSA (OIDC)** or **EKS Pod Identity**.
2. **Karpenter Node IAM Role & Instance Profile**: Provisions the standard IAM role for EC2 instances launched by Karpenter to join EKS and establishes the modern **EKS Access Entry** (`EC2_LINUX`).
3. **Spot Interruption Event Management**: Sets up an SQS queue and EventBridge rules for Spot interruptions, rebalancing recommendations, instance state changes, and scheduled health events.
4. **Helm Release**: Deploys Karpenter from the official AWS OCI registry (`oci://public.ecr.aws/karpenter/karpenter`) with configurable values.

---

## Usage

### Example 1: Standard IRSA (OIDC Trust) Configuration

```hcl
module "karpenter" {
  source = "./modules/karpenter"

  cluster_name      = "my-eks-cluster"
  cluster_endpoint  = "https://1234567890ABCDEF1234567890.gr7.us-east-2.eks.amazonaws.com"
  
  # OIDC Configuration (IRSA)
  enable_irsa       = true
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-2.amazonaws.com/id/1234567890ABCDEF1234567890"
  oidc_provider_url = "https://oidc.eks.us-east-2.amazonaws.com/id/1234567890ABCDEF1234567890"
  
  # Optional SQS Spot Interruption Handling (Enabled by default)
  enable_spot_interruption_handler = true

  tags = {
    Environment = "production"
  }
}
```

### Example 2: EKS Pod Identity Configuration

```hcl
module "karpenter" {
  source = "./modules/karpenter"

  cluster_name      = "my-eks-cluster"
  cluster_endpoint  = "https://1234567890ABCDEF1234567890.gr7.us-east-2.eks.amazonaws.com"

  # EKS Pod Identity Configuration (requires Pod Identity agent addon on EKS)
  enable_irsa         = false
  enable_pod_identity = true

  tags = {
    Environment = "staging"
  }
}
```

---

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.4.6 |
| aws | >= 5.29.0 |
| kubernetes | >= 2.21.0 |
| helm | >= 2.10.0 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 5.29.0 |
| kubernetes | >= 2.21.0 |
| helm | >= 2.10.0 |

---

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cluster\_name | The name of the EKS cluster. | `string` | n/a | yes |
| cluster\_endpoint | The endpoint URL for the EKS cluster API server. | `string` | n/a | yes |
| karpenter\_version | The version of Karpenter to deploy via Helm. | `string` | `"1.14.0"` | no |
| karpenter\_namespace | The namespace where Karpenter will be installed. | `string` | `"karpenter"` | no |
| karpenter\_service\_account | The name of the service account for Karpenter controller. | `string` | `"karpenter"` | no |
| enable\_irsa | Whether to create/configure IAM Roles for Service Accounts (IRSA). | `bool` | `true` | no |
| oidc\_provider\_arn | OIDC provider ARN for the EKS cluster (Required if enable_irsa is true). | `string` | `null` | no |
| oidc\_provider\_url | OIDC provider URL for the EKS cluster (Required if enable_irsa is true). | `string` | `null` | no |
| enable\_pod\_identity | Whether to configure EKS Pod Identity association for the controller. | `bool` | `false` | no |
| pod\_identity\_association\_role\_arn | An existing IAM role ARN to use for Pod Identity. If null, a new role will be created. | `string` | `null` | no |
| enable\_spot\_interruption\_handler | Whether to enable the SQS queue and EventBridge rules for Karpenter Spot interruption/rebalance handling. | `bool` | `true` | no |
| sqs\_queue\_name | Custom name for the SQS interruption queue. Defaults to the cluster name. | `string` | `null` | no |
| create\_node\_iam\_role | Whether to create the IAM role for the Karpenter worker nodes. | `bool` | `true` | no |
| node\_iam\_role\_name | The name of the Karpenter node IAM role. Defaults to KarpenterNodeRole-\<cluster_name\>. | `string` | `null` | no |
| node\_iam\_role\_arn | Existing IAM role ARN for nodes (must be provided if create_node_iam_role is false). | `string` | `null` | no |
| create\_instance\_profile | Whether to create an IAM Instance Profile for nodes (for older Karpenter configurations). | `bool` | `true` | no |
| node\_iam\_role\_additional\_policies | A map of additional policy ARNs to attach to the Karpenter node IAM role. | `map(string)` | `{}` | no |
| helm\_release\_name | The Helm release name for Karpenter. | `string` | `"karpenter"` | no |
| helm\_release\_timeout | Helm release timeout in seconds. | `number` | `600` | no |
| helm\_release\_values | Additional values to pass to the Karpenter Helm chart. | `any` | `{}` | no |
| tags | A map of tags to assign to the resources. | `map(string)` | `{}` | no |

---

## Outputs

| Name | Description |
|------|-------------|
| controller\_iam\_role\_arn | The ARN of the Karpenter Controller IAM Role. |
| controller\_iam\_role\_name | The name of the Karpenter Controller IAM Role. |
| controller\_iam\_policy\_arn | The ARN of the Karpenter Controller IAM Policy. |
| node\_iam\_role\_arn | The ARN of the Karpenter Node IAM Role. |
| node\_iam\_role\_name | The name of the Karpenter Node IAM Role. |
| node\_instance\_profile\_name | The name of the Karpenter Node IAM Instance Profile. |
| node\_instance\_profile\_arn | The ARN of the Karpenter Node IAM Instance Profile. |
| sqs\_queue\_arn | The ARN of the SQS queue used for interruption/rebalance handling. |
| sqs\_queue\_name | The name of the SQS queue used for interruption/rebalance handling. |
| helm\_release\_metadata | Status metadata of the Karpenter Helm release. |
