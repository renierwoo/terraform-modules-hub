################################################################################
# General Data Sources and Locals
################################################################################

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  sqs_queue_name = coalesce(var.sqs_queue_name, var.cluster_name)

  node_role_arn  = var.create_node_iam_role ? aws_iam_role.node[0].arn : var.node_iam_role_arn
  node_role_name = var.create_node_iam_role ? aws_iam_role.node[0].name : split("/", var.node_iam_role_arn)[length(split("/", var.node_iam_role_arn)) - 1]

  controller_role_arn = var.enable_irsa || (var.enable_pod_identity && var.pod_identity_association_role_arn == null) ? aws_iam_role.controller[0].arn : var.pod_identity_association_role_arn

  helm_values = {
    serviceAccount = {
      create = true
      name   = var.karpenter_service_account
      annotations = var.enable_irsa ? {
        "eks.amazonaws.com/role-arn" = local.controller_role_arn
      } : {}
    }
    settings = {
      clusterName       = var.cluster_name
      clusterEndpoint   = var.cluster_endpoint
      interruptionQueue = var.enable_spot_interruption_handler ? aws_sqs_queue.karpenter[0].name : null
    }
  }
}


################################################################################
# Karpenter Controller IAM Role
################################################################################

data "aws_iam_policy_document" "controller_assume" {
  count = (var.enable_irsa || (var.enable_pod_identity && var.pod_identity_association_role_arn == null)) ? 1 : 0

  # OIDC / IRSA Trust Relationship
  dynamic "statement" {
    for_each = var.enable_irsa ? [1] : []
    content {
      actions = ["sts:AssumeRoleWithWebIdentity"]
      effect  = "Allow"

      condition {
        test     = "StringEquals"
        variable = "${replace(var.oidc_provider_url, "https://", "")}:sub"
        values   = ["system:serviceaccount:${var.karpenter_namespace}:${var.karpenter_service_account}"]
      }

      condition {
        test     = "StringEquals"
        variable = "${replace(var.oidc_provider_url, "https://", "")}:aud"
        values   = ["sts.amazonaws.com"]
      }

      principals {
        identifiers = [var.oidc_provider_arn]
        type        = "Federated"
      }
    }
  }

  # EKS Pod Identity Trust Relationship
  dynamic "statement" {
    for_each = (var.enable_pod_identity && var.pod_identity_association_role_arn == null) ? [1] : []
    content {
      actions = ["sts:AssumeRole", "sts:TagSession"]
      effect  = "Allow"

      principals {
        identifiers = ["pods.eks.amazonaws.com"]
        type        = "Service"
      }
    }
  }
}

resource "aws_iam_role" "controller" {
  count = (var.enable_irsa || (var.enable_pod_identity && var.pod_identity_association_role_arn == null)) ? 1 : 0

  name               = "KarpenterControllerRole-${var.cluster_name}"
  description        = "IAM Role for Karpenter Controller on cluster ${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.controller_assume[0].json

  tags = var.tags
}

data "aws_iam_policy_document" "controller" {
  count = (var.enable_irsa || (var.enable_pod_identity && var.pod_identity_association_role_arn == null)) ? 1 : 0

  # Node Lifecycle: Allow access to generic image, snapshot, subnets, etc.
  statement {
    sid    = "AllowScopedEC2InstanceAccessActions"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet"
    ]
    resources = [
      "arn:${local.partition}:ec2:${local.region}::image/*",
      "arn:${local.partition}:ec2:${local.region}::snapshot/*",
      "arn:${local.partition}:ec2:${local.region}:*:security-group/*",
      "arn:${local.partition}:ec2:${local.region}:*:subnet/*",
      "arn:${local.partition}:ec2:${local.region}:*:capacity-reservation/*",
      "arn:${local.partition}:ec2:${local.region}:*:placement-group/*"
    ]
  }

  # Node Lifecycle: Allow RunInstances/CreateFleet on Launch Templates owned by EKS cluster
  statement {
    sid    = "AllowScopedEC2LaunchTemplateAccessActions"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet"
    ]
    resources = ["arn:${local.partition}:ec2:${local.region}:*:launch-template/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  # Node Lifecycle: Allow creating fleet, instance, volumes with cluster tags
  statement {
    sid    = "AllowScopedEC2InstanceActionsWithTags"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate"
    ]
    resources = [
      "arn:${local.partition}:ec2:${local.region}:*:fleet/*",
      "arn:${local.partition}:ec2:${local.region}:*:instance/*",
      "arn:${local.partition}:ec2:${local.region}:*:volume/*",
      "arn:${local.partition}:ec2:${local.region}:*:network-interface/*",
      "arn:${local.partition}:ec2:${local.region}:*:launch-template/*",
      "arn:${local.partition}:ec2:${local.region}:*:spot-instances-request/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [var.cluster_name]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  # Node Lifecycle: Allow tagging resources upon creation
  statement {
    sid    = "AllowScopedResourceCreationTagging"
    effect = "Allow"
    actions = [
      "ec2:CreateTags"
    ]
    resources = [
      "arn:${local.partition}:ec2:${local.region}:*:fleet/*",
      "arn:${local.partition}:ec2:${local.region}:*:instance/*",
      "arn:${local.partition}:ec2:${local.region}:*:volume/*",
      "arn:${local.partition}:ec2:${local.region}:*:network-interface/*",
      "arn:${local.partition}:ec2:${local.region}:*:launch-template/*",
      "arn:${local.partition}:ec2:${local.region}:*:spot-instances-request/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [var.cluster_name]
    }

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  # Node Lifecycle: Allow tagging existing instances managed by Karpenter
  statement {
    sid    = "AllowScopedResourceTagging"
    effect = "Allow"
    actions = [
      "ec2:CreateTags"
    ]
    resources = ["arn:${local.partition}:ec2:${local.region}:*:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }

    condition {
      test     = "StringEqualsIfExists"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [var.cluster_name]
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["eks:eks-cluster-name", "karpenter.sh/nodeclaim", "Name"]
    }
  }

  # Node Lifecycle: Allow deleting instances and launch templates
  statement {
    sid    = "AllowScopedDeletion"
    effect = "Allow"
    actions = [
      "ec2:TerminateInstances",
      "ec2:DeleteLaunchTemplate"
    ]
    resources = [
      "arn:${local.partition}:ec2:${local.region}:*:instance/*",
      "arn:${local.partition}:ec2:${local.region}:*:launch-template/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  # IAM Integration: Allow passing Node role
  statement {
    sid    = "AllowPassingInstanceRole"
    effect = "Allow"
    actions = [
      "iam:PassRole"
    ]
    resources = [local.node_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com", "ec2.amazonaws.com.cn"]
    }
  }

  # IAM Integration: Allow Karpenter to manage instance profiles dynamically
  statement {
    sid    = "AllowScopedInstanceProfileCreationActions"
    effect = "Allow"
    actions = [
      "iam:CreateInstanceProfile"
    ]
    resources = ["arn:${local.partition}:iam::${local.account_id}:instance-profile/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [var.cluster_name]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/topology.kubernetes.io/region"
      values   = [local.region]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }

  statement {
    sid    = "AllowScopedInstanceProfileTagActions"
    effect = "Allow"
    actions = [
      "iam:TagInstanceProfile"
    ]
    resources = ["arn:${local.partition}:iam::${local.account_id}:instance-profile/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/topology.kubernetes.io/region"
      values   = [local.region]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [var.cluster_name]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/topology.kubernetes.io/region"
      values   = [local.region]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }

  statement {
    sid    = "AllowScopedInstanceProfileActions"
    effect = "Allow"
    actions = [
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:DeleteInstanceProfile"
    ]
    resources = ["arn:${local.partition}:iam::${local.account_id}:instance-profile/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/topology.kubernetes.io/region"
      values   = [local.region]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }

  # EKS Integration: Describe cluster endpoint and certificate authority
  statement {
    sid    = "AllowAPIServerEndpointDiscovery"
    effect = "Allow"
    actions = [
      "eks:DescribeCluster"
    ]
    resources = ["arn:${local.partition}:eks:${local.region}:${local.account_id}:cluster/${var.cluster_name}"]
  }

  # SQS Interruption Queue Actions
  dynamic "statement" {
    for_each = var.enable_spot_interruption_handler ? [1] : []
    content {
      sid    = "AllowInterruptionQueueActions"
      effect = "Allow"
      actions = [
        "sqs:DeleteMessage",
        "sqs:GetQueueUrl",
        "sqs:ReceiveMessage"
      ]
      resources = [aws_sqs_queue.karpenter[0].arn]
    }
  }

  # Zonal Shift Integration
  statement {
    sid    = "AllowZonalShiftStatusReadOnly"
    effect = "Allow"
    actions = [
      "arc-zonal-shift:GetManagedResource"
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "arc-zonal-shift:ResourceIdentifier"
      values   = ["arn:${local.partition}:eks:${local.region}:${local.account_id}:cluster/${var.cluster_name}"]
    }
  }

  # Resource Discovery: Read-only regional access
  statement {
    sid    = "AllowRegionalReadActions"
    effect = "Allow"
    actions = [
      "ec2:DescribeCapacityReservations",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribePlacementGroups",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets"
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region]
    }
  }

  # SSM Read Actions: Query EKS optimized AMI parameter paths
  statement {
    sid    = "AllowSSMReadActions"
    effect = "Allow"
    actions = [
      "ssm:GetParameter"
    ]
    resources = ["arn:${local.partition}:ssm:${local.region}::parameter/aws/service/*"]
  }

  # Pricing Actions
  statement {
    sid    = "AllowPricingReadActions"
    effect = "Allow"
    actions = [
      "pricing:GetProducts"
    ]
    resources = ["*"]
  }

  # Unscoped read-only actions for instance profile mapping
  statement {
    sid    = "AllowUnscopedInstanceProfileListAction"
    effect = "Allow"
    actions = [
      "iam:ListInstanceProfiles"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowInstanceProfileReadActions"
    effect = "Allow"
    actions = [
      "iam:GetInstanceProfile"
    ]
    resources = ["arn:${local.partition}:iam::${local.account_id}:instance-profile/*"]
  }
}

resource "aws_iam_policy" "controller" {
  count = (var.enable_irsa || (var.enable_pod_identity && var.pod_identity_association_role_arn == null)) ? 1 : 0

  name        = "KarpenterControllerPolicy-${var.cluster_name}"
  description = "IAM Policy for Karpenter Controller on cluster ${var.cluster_name}"
  policy      = data.aws_iam_policy_document.controller[0].json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "controller" {
  count = (var.enable_irsa || (var.enable_pod_identity && var.pod_identity_association_role_arn == null)) ? 1 : 0

  role       = aws_iam_role.controller[0].name
  policy_arn = aws_iam_policy.controller[0].arn
}


################################################################################
# EKS Pod Identity Association (Optional)
################################################################################

resource "aws_eks_pod_identity_association" "karpenter" {
  count = var.enable_pod_identity ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.karpenter_namespace
  service_account = var.karpenter_service_account
  role_arn        = local.controller_role_arn
}


################################################################################
# Karpenter Node IAM Role & Instance Profile
################################################################################

resource "aws_iam_role" "node" {
  count = var.create_node_iam_role ? 1 : 0

  name        = coalesce(var.node_iam_role_name, "KarpenterNodeRole-${var.cluster_name}")
  description = "IAM Role for Karpenter Node on cluster ${var.cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

locals {
  standard_node_policies = {
    AmazonEKSWorkerNodePolicy          = "arn:${local.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
    AmazonEKS_CNI_Policy               = "arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
    AmazonEC2ContainerRegistryPullOnly = "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
    AmazonSSMManagedInstanceCore       = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  node_policies = merge(
    local.standard_node_policies,
    var.node_iam_role_additional_policies
  )
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = var.create_node_iam_role ? local.node_policies : {}

  role       = aws_iam_role.node[0].name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "node" {
  count = var.create_instance_profile && var.create_node_iam_role ? 1 : 0

  name = aws_iam_role.node[0].name
  role = aws_iam_role.node[0].name

  tags = var.tags
}


################################################################################
# EKS Access Entry for Karpenter Nodes
################################################################################

resource "aws_eks_access_entry" "karpenter_node" {
  count = var.create_node_iam_role ? 1 : 0

  cluster_name  = var.cluster_name
  principal_arn = local.node_role_arn
  type          = "EC2_LINUX"
}


################################################################################
# SQS Interruption Queue & EventBridge Rules (Optional)
################################################################################

resource "aws_sqs_queue" "karpenter" {
  count = var.enable_spot_interruption_handler ? 1 : 0

  name                      = local.sqs_queue_name
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = var.tags
}

data "aws_iam_policy_document" "sqs_policy" {
  count = var.enable_spot_interruption_handler ? 1 : 0

  statement {
    sid       = "AllowEventBridgeToSendMessage"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.karpenter[0].arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }
  }

  statement {
    sid       = "DenyHTTP"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.karpenter[0].arn]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "karpenter" {
  count = var.enable_spot_interruption_handler ? 1 : 0

  queue_url = aws_sqs_queue.karpenter[0].id
  policy    = data.aws_iam_policy_document.sqs_policy[0].json
}

locals {
  interruption_events = {
    scheduled_change = {
      description = "Karpenter interruption rule for AWS Health Scheduled Change Events"
      event_pattern = jsonencode({
        source      = ["aws.health"]
        detail-type = ["AWS Health Event"]
      })
    }
    spot_interruption = {
      description = "Karpenter interruption rule for Spot Instance Interruption Warnings"
      event_pattern = jsonencode({
        source      = ["aws.ec2"]
        detail-type = ["EC2 Spot Instance Interruption Warning"]
      })
    }
    rebalance = {
      description = "Karpenter interruption rule for EC2 Instance Rebalance Recommendations"
      event_pattern = jsonencode({
        source      = ["aws.ec2"]
        detail-type = ["EC2 Instance Rebalance Recommendation"]
      })
    }
    instance_state_change = {
      description = "Karpenter interruption rule for EC2 Instance State-change Notifications"
      event_pattern = jsonencode({
        source      = ["aws.ec2"]
        detail-type = ["EC2 Instance State-change Notification"]
      })
    }
    capacity_reservation_interruption = {
      description = "Karpenter interruption rule for EC2 Capacity Reservation Instance Interruption Warnings"
      event_pattern = jsonencode({
        source      = ["aws.ec2"]
        detail-type = ["EC2 Capacity Reservation Instance Interruption Warning"]
      })
    }
  }
}

resource "aws_cloudwatch_event_rule" "karpenter" {
  for_each = var.enable_spot_interruption_handler ? local.interruption_events : {}

  name          = "${var.cluster_name}-${each.key}"
  description   = each.value.description
  event_pattern = each.value.event_pattern

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "karpenter" {
  for_each = var.enable_spot_interruption_handler ? local.interruption_events : {}

  rule      = aws_cloudwatch_event_rule.karpenter[each.key].name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.karpenter[0].arn
}


################################################################################
# Helm Release
################################################################################

resource "helm_release" "karpenter" {
  name             = var.helm_release_name
  namespace        = var.karpenter_namespace
  create_namespace = true

  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_version

  timeout = var.helm_release_timeout

  values = [
    yamlencode(local.helm_values),
    yamlencode(var.helm_release_values)
  ]
}
