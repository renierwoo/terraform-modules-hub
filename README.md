# Terraform Modules Hub
Multi-Cloud Terraform Module Hub: Simplifying infrastructure deployment across multiple cloud providers.

<p align="center">
  <img src="./terraform-agnostic-white-copy.png" alt="Terraform Modules Hub">
</p>

## Usage

```hcl
module "eks" {
  source  = "git@github.com:renierwoo/terraform-modules-hub.git//aws/eks"
  version = "1.0.0"

  cluster_name    = "my-cluster"
  cluster_version = "1.27"

  cluster_endpoint_public_access = true

  vpc_id                   = "vpc-1234556abcdef"
  subnet_ids               = ["subnet-abcde012", "subnet-bcde012a", "subnet-fghi345a"]
  control_plane_subnet_ids = ["subnet-xyzde987", "subnet-slkjf456", "subnet-qeiru789"]

  # EKS Managed Node Group(s)
  eks_managed_node_group_defaults = {
    instance_types = ["m6i.large", "m5.large", "m5n.large", "m5zn.large"]
  }

  eks_managed_node_groups = {
    blue = {}
    green = {
      min_size     = 1
      max_size     = 10
      desired_size = 1

      instance_types = ["t3.large"]
      capacity_type  = "SPOT"
    }
  }

  # aws-auth configmap
  manage_aws_auth_configmap = true

  aws_auth_roles = [
    {
      rolearn  = "arn:aws:iam::66666666666:role/role1"
      username = "role1"
      groups   = ["system:masters"]
    },
  ]

  aws_auth_users = [
    {
      userarn  = "arn:aws:iam::66666666666:user/user1"
      username = "user1"
      groups   = ["system:masters"]
    },
    {
      userarn  = "arn:aws:iam::66666666666:user/user2"
      username = "user2"
      groups   = ["system:masters"]
    },
  ]

  aws_auth_accounts = [
    "777777777777",
    "888888888888",
  ]

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}
```

## Authors
This repository, maintained by [Renier Collazo Woo](https://github.com/renierwoo), builds upon the ideas and concepts introduced in [Terraform AWS modules](https://github.com/terraform-aws-modules)

## License
Apache 2 Licensed. See [LICENSE](./LICENSE) for full details.
