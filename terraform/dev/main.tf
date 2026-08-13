provider "aws" {
  region = "us-east-1"

  # Any account other than the dedicated project account is a hard stop, so the
  # provider verifies the caller's account before it does anything. A wrong
  # credential then fails at the first API call instead of creating an
  # environment network somewhere it does not belong.
  allowed_account_ids = [var.allowed_account_id]

  # The six mandatory tags of ADR-0013. Unlike the two foundation roots, most of
  # what this root declares is taggable. The routes and the four associations
  # expose no AWS tags of their own and are left that way rather than given a
  # tagging workaround.
  #
  # Environment is "dev" and Lifecycle is "ephemeral" because these resources
  # belong to an environment role rather than to a persistent shared foundation.
  # Component is "network" as the root default, and the cluster, the node group
  # and the two IAM roles override it to "runtime" on themselves, because cost
  # attribution reads this tag and they are not networking.
  default_tags {
    tags = {
      Project     = "cloud-platform-reference"
      Environment = "dev"
      Component   = "network"
      Lifecycle   = "ephemeral"
      Owner       = "platform-engineer"
      ManagedBy   = "terraform"
    }
  }
}

resource "aws_vpc" "dev" {
  cidr_block = "10.20.0.0/16"

  # enable_dns_support is on by default and enable_dns_hostnames is off. Both
  # are stated here so the resolved behaviour is readable in the configuration
  # rather than inherited, and because private DNS on any interface endpoint
  # added later needs hostnames on.
  enable_dns_support   = true
  enable_dns_hostnames = true

  # Name is not one of the six mandatory tags of ADR-0013. It is here because
  # the console and the CLI list these resources by Name, and an operator
  # inspecting, troubleshooting or tearing this environment down has to
  # identify the right resource without cross-referencing IDs. It identifies,
  # it does not classify, so it replaces none of the six.
  tags = {
    Name = "cloud-platform-reference-dev-vpc"
  }
}

# The address plan is written out rather than derived, so a reviewer reads it
# instead of evaluating it. The two private /20 blocks sit at the bottom of the
# VPC range and the two public /24 blocks at the top, which leaves the space
# between them free for later private growth.
#
# map_public_ip_on_launch is false on every subnet here, public included. It
# already defaults to false on a subnet created this way, but leaving it
# implicit would let a public subnet read as though it hands out public
# addresses on its own. Anything that needs one gets it explicitly.
#
# The kubernetes.io/role tags are what an AWS load balancer controller reads
# later to pick subnets. No kubernetes.io/cluster tag is set, because no cluster
# name is selected and no cluster exists.
resource "aws_subnet" "private_a" {
  vpc_id                  = aws_vpc.dev.id
  cidr_block              = "10.20.0.0/20"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    Name                              = "cloud-platform-reference-dev-private-a"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id                  = aws_vpc.dev.id
  cidr_block              = "10.20.16.0/20"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false

  tags = {
    Name                              = "cloud-platform-reference-dev-private-b"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.dev.id
  cidr_block              = "10.20.240.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    Name                     = "cloud-platform-reference-dev-public-a"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.dev.id
  cidr_block              = "10.20.241.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false

  tags = {
    Name                     = "cloud-platform-reference-dev-public-b"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_internet_gateway" "dev" {
  vpc_id = aws_vpc.dev.id

  tags = {
    Name = "cloud-platform-reference-dev-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.dev.id

  tags = {
    Name = "cloud-platform-reference-dev-public-rt"
  }
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.dev.id
}

# Three routes reach this table and none of them is declared inside it: the VPC
# local route AWS maintains itself, the S3 prefix-list route the gateway
# endpoint installs, and the default route to the NAT gateway declared further
# down as its own resource.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.dev.id

  tags = {
    Name = "cloud-platform-reference-dev-private-rt"
  }
}

# Every subnet in this root is associated explicitly. A subnet with no
# association falls back to the VPC main route table, which this root does not
# manage, so the explicit association is what keeps routing a property of this
# configuration instead of an unmanaged default.
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

# A gateway endpoint installs a prefix-list route into the route tables it is
# associated with, so S3 traffic from the private subnets can reach S3 without
# requiring the future NAT path.
#
# This slice associates the endpoint only with the private route table because
# its purpose here is to give the private side a direct S3 path without adding
# internet egress. Public-route-table association is outside this slice.
#
# This covers S3 and nothing else. ECR registry and API traffic uses separate
# service endpoints and is not covered by this S3 gateway endpoint.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.dev.id
  service_name      = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "cloud-platform-reference-dev-s3-endpoint"
  }
}

# Private egress. This is the first hourly resource the root creates, and it is
# one gateway rather than one per Availability Zone. ADR-0007 took that
# trade-off deliberately: a single NAT halves both the hourly charge and the
# per-gigabyte processing charge, and in exchange losing us-east-1a takes
# private egress away from both zones, while traffic leaving private-b crosses
# an AZ boundary to reach it. A tenant with an availability target would pay for
# the second gateway.
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "cloud-platform-reference-dev-nat-eip"
  }
}

resource "aws_nat_gateway" "dev" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id

  tags = {
    Name = "cloud-platform-reference-dev-nat"
  }

  # The arguments above name the address and the subnet, and neither of them
  # names the internet gateway, so Terraform sees no reason to order the two.
  # A NAT gateway is only reachable onward through an attached internet
  # gateway, and this root has to behave the same way on a rebuild into an
  # empty account as it does today, where the gateway happens to exist already.
  depends_on = [aws_internet_gateway.dev]
}

# The default route arrives as its own resource rather than as an inline block
# on aws_route_table.private, so the live route table is not modified and the
# plan shows one route added instead of a change to an existing resource.
resource "aws_route" "private_default" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.dev.id
}

# Two service roles. Each trusts exactly one AWS service and carries only AWS
# managed policies, so nothing declared here grants a workload anything.
resource "aws_iam_role" "eks_cluster" {
  name = "cloud-platform-reference-dev-eks-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Component = "runtime"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "eks_node" {
  name = "cloud-platform-reference-dev-eks-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Component = "runtime"
  }
}

resource "aws_iam_role_policy_attachment" "eks_node_worker" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# The CNI permissions sit on the node role, which means every pod that can reach
# the instance metadata service inherits them. That is a bootstrap choice for
# this phase, not the end state: AWS supports it while the VPC CNI is not yet
# running under its own identity, and recommends EKS Pod Identity for add-on
# IAM. The identity phase revisits it, and the README records the limitation.
resource "aws_iam_role_policy_attachment" "eks_node_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# PullOnly rather than ReadOnly. A managed node has to pull images; it has no
# reason to describe repositories or read registry metadata beyond that, and
# PullOnly is the narrower of the two policies that satisfy the requirement.
resource "aws_iam_role_policy_attachment" "eks_node_ecr_pull" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}

resource "aws_eks_cluster" "dev" {
  name     = "cloud-platform-reference-dev"
  version  = "1.36"
  role_arn = aws_iam_role.eks_cluster.arn

  # This environment is created for an approved window and destroyed afterwards,
  # so whether a destroy can reach the control plane is stated here rather than
  # left to a provider or AWS default.
  deletion_protection = false

  vpc_config {
    # ADR-0007: control-plane ENIs stay in private subnets
    subnet_ids = [
      aws_subnet.private_a.id,
      aws_subnet.private_b.id,
    ]

    # Both endpoints are enabled. The private one keeps node and in-cluster API
    # traffic inside the VPC; the public one is what lets the operator reach the
    # API without a bastion or a VPN. The public side is narrowed to a single
    # operator CIDR, because the AWS default of 0.0.0.0/0 would put the API
    # server on the internet with authentication as the only barrier.
    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = [var.operator_cidr]
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = {
    Component = "runtime"
  }

  # The cluster references the role but not the policy attached to it, so
  # without this Terraform can create the cluster before AmazonEKSClusterPolicy
  # is on the role and the control plane cannot manage its own interfaces.
  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

# A managed node group tags itself. Those tags do not reach the EC2 instances it
# launches or their root volumes, and neither does the provider's default_tags,
# so without this template the workers would run untagged and the ADR-0013 cost
# attribution and orphan scans would not see them.
#
# That is the only reason it exists. It carries no AMI, no user data, no
# security group, no network interface, no instance type and no subnet: EKS
# supplies all of those for a managed node group, and taking any of them over
# here would mean owning the node bootstrap contract too.
resource "aws_launch_template" "eks_node" {
  name_prefix = "cloud-platform-reference-dev-node-"

  # A node group cannot set disk_size while a launch template is attached, so
  # the root volume is configured here instead.
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  # ADR-0008 closes the path from a pod to the node's credentials, and leaving
  # this to the AMI or account default would leave that closure unstated.
  #
  # The endpoint stays enabled because the node itself needs it. Requiring
  # tokens turns off IMDSv1, whose unauthenticated GET is what makes a
  # server-side request forgery in a pod enough to read credentials. The hop
  # limit is the part that does the work here: a pod in its own network
  # namespace is one hop further away than the host, so a limit of 1 answers the
  # host and drops the pod. AWS often suggests 2 so that containers can reach
  # IMDS, which is exactly what this project does not want, because workload AWS
  # access belongs to EKS Pod Identity rather than to the node role.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Project     = "cloud-platform-reference"
      Environment = "dev"
      Component   = "runtime"
      Lifecycle   = "ephemeral"
      Owner       = "platform-engineer"
      ManagedBy   = "terraform"
      Name        = "cloud-platform-reference-dev-node"
    }
  }

  # The volume carries the six mandatory tags and no Name. An orphaned volume is
  # found through the mandatory tags, and it answers no operational question a
  # Name would answer that its instance does not answer already.
  tag_specifications {
    resource_type = "volume"

    tags = {
      Project     = "cloud-platform-reference"
      Environment = "dev"
      Component   = "runtime"
      Lifecycle   = "ephemeral"
      Owner       = "platform-engineer"
      ManagedBy   = "terraform"
    }
  }

  tags = {
    Component = "runtime"
  }
}

resource "aws_eks_node_group" "dev" {
  cluster_name    = aws_eks_cluster.dev.name
  node_group_name = "cloud-platform-reference-dev-nodes"
  node_role_arn   = aws_iam_role.eks_node.arn

  # Private subnets only, the same two the control plane uses. ADR-0007 puts no
  # node in a public subnet.
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id,
  ]

  instance_types = ["m6a.large"]
  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND"

  # Tracking latest_version means an edit to the template is a node group
  # update, so a tag or root-volume change reaches the running nodes through a
  # rolling replacement rather than only the next ones to launch.
  launch_template {
    id      = aws_launch_template.eks_node.id
    version = aws_launch_template.eks_node.latest_version
  }

  # Fixed at two. No autoscaler exists in this slice, so min and max match
  # desired and a capacity change is a reviewed code change rather than a
  # runtime event.
  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 2
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    Component = "runtime"
  }

  # Terraform cannot infer either of these prerequisites from the arguments
  # above. The node role is referenced but its policy attachments are not, and
  # a node needs those permissions in place before it boots or it never
  # registers with the cluster. The private route is referenced by nothing here
  # at all, yet node registration, image pulls and AWS service calls all leave
  # through the NAT path this root selected, so that route has to exist before
  # the first node comes up. Relative AWS creation times are not a guarantee.
  depends_on = [
    aws_iam_role_policy_attachment.eks_node_worker,
    aws_iam_role_policy_attachment.eks_node_cni,
    aws_iam_role_policy_attachment.eks_node_ecr_pull,
    aws_route.private_default,
  ]
}

# The four managed add-ons of ADR-0006, each pinned to an exact version. AWS
# publishes new add-on revisions continuously, and an unpinned resource would
# let one arrive during an unrelated apply. Pinned, an upgrade is a reviewed
# code change with a diff, which is what ADR-0006 asks for.
#
# EKS installs its own self-managed copies of vpc-cni, coredns and kube-proxy
# when a cluster comes up. The three resources below deliberately take those
# over as Terraform-managed add-ons, and OVERWRITE is what settles the field
# conflicts that transition produces at create time. The Pod Identity agent is
# not part of that bootstrap set, so it needs no conflict resolution.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.dev.name
  addon_name                  = "vpc-cni"
  addon_version               = "v1.22.3-eksbuild.1"
  resolve_conflicts_on_create = "OVERWRITE"

  tags = {
    Component = "runtime"
  }
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.dev.name
  addon_name                  = "coredns"
  addon_version               = "v1.14.3-eksbuild.3"
  resolve_conflicts_on_create = "OVERWRITE"

  tags = {
    Component = "runtime"
  }

  # CoreDNS is scheduled onto nodes rather than run as a per-node DaemonSet, so
  # it needs schedulable capacity before it can become healthy. The add-on
  # references the cluster and nothing else, so Terraform has no way to see
  # that the node group is a prerequisite for the health it will wait on.
  depends_on = [aws_eks_node_group.dev]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.dev.name
  addon_name                  = "kube-proxy"
  addon_version               = "v1.36.0-eksbuild.13"
  resolve_conflicts_on_create = "OVERWRITE"

  tags = {
    Component = "runtime"
  }
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name  = aws_eks_cluster.dev.name
  addon_name    = "eks-pod-identity-agent"
  addon_version = "v1.3.10-eksbuild.3"

  tags = {
    Component = "runtime"
  }
}

# The four resources below are environment-scoped, not cluster-scoped. They
# survive a runtime teardown and are removed with the Dev environment, which is
# the boundary docs/architecture-baseline.md records for workload IAM roles and
# for an environment's secret entries. That is why they sit in this root beside
# the network rather than in a foundation root, and why the targeted runtime
# destroy does not name them. Component is "identity" rather than the root
# default, because cost attribution and orphan scans read that tag and these are
# neither networking nor runtime.

# The secret container only. No aws_secretsmanager_secret_version is declared,
# because a version resource writes the value into Terraform state, where marking
# an input sensitive hides console output and changes nothing about what is
# stored. The value is placed out of band, and the later rotation exercise works
# the same path.
#
# The recovery window is what answers an accidental delete, so it is stated
# rather than inherited. Seven days is the owner-approved figure.
#
# No kms_key_id, so the AWS-managed key encrypts this secret. A customer-managed
# key would add a resource with its own lifecycle and charge, and nothing in this
# slice needs one.
resource "aws_secretsmanager_secret" "workload" {
  name                    = "cloud-platform-reference-dev-workload-secret"
  recovery_window_in_days = 7

  tags = {
    Component = "identity"
  }
}

# Non-secret configuration. String rather than SecureString on purpose: ADR-0008
# puts sensitive values in the secret above and non-secret configuration here,
# and a SecureString would blur that split and add a KMS dependency to a value
# that does not need one. The tier is stated because it decides both the size
# limit and whether the parameter carries a charge.
resource "aws_ssm_parameter" "workload" {
  name  = "cloud-platform-reference-dev-workload-environment"
  type  = "String"
  tier  = "Standard"
  value = "dev"

  tags = {
    Component = "identity"
  }
}

# The workload identity for EKS Pod Identity. The trust names one service
# principal and nothing else: no account principal, no OIDC provider, no IRSA
# condition and no wildcard. That is what keeps the role cluster-independent,
# because pods.eks.amazonaws.com is generic where an IRSA trust names a specific
# cluster's OIDC issuer and would have to be rewritten on every cluster
# recreation. ADR-0008 selected Pod Identity for that property.
#
# sts:TagSession sits beside sts:AssumeRole because the Pod Identity flow tags
# the session it creates, and the assume call fails without it.
#
# Nothing is associated with this role yet. aws_eks_pod_identity_association
# needs a live cluster and belongs to the later runtime slice; the role is
# authored here so the identity outlives the cluster rather than following it.
resource "aws_iam_role" "workload" {
  name = "cloud-platform-reference-dev-workload"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole",
          "sts:TagSession",
        ]
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Component = "identity"
  }
}

# Inline rather than a managed policy. One role consumes it, so a standalone
# aws_iam_policy plus an attachment would be two resources and a reusable object
# for a permission set with no second consumer.
#
# Both statements take the ARN Terraform computed for the resource above, so no
# account ID is written here and the grant cannot widen if a name changes. The
# Secrets Manager ARN also carries a suffix AWS generates at creation, which no
# hand-assembled ARN could reproduce.
#
# An inline role policy is not a taggable AWS object, so it carries no tags of
# its own. The routes and the route table associations in this root are left the
# same way rather than given a tagging workaround.
resource "aws_iam_role_policy" "workload" {
  name = "cloud-platform-reference-dev-workload-read"
  role = aws_iam_role.workload.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = aws_secretsmanager_secret.workload.arn
      },
      {
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = aws_ssm_parameter.workload.arn
      },
    ]
  })
}

# The synchronisation controller's own identity, kept separate from the workload
# role above because the two read the secret for different reasons and one shared
# role would widen whichever of them needs less. The trust names only the generic
# Pod Identity service principal, so the role outlives any cluster that happens to
# run the controller.
#
# No aws_eks_pod_identity_association is declared here. An association binds a
# role to an exact namespace and ServiceAccount, and those names come from the
# pinned chart and its values, which are not selected yet. Authoring it now would
# encode a guess.
resource "aws_iam_role" "external_secrets" {
  name = "cloud-platform-reference-dev-external-secrets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole",
          "sts:TagSession",
        ]
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Component = "identity"
  }
}

# Two actions on one secret: read the value, and read the metadata that tells the
# controller whether the value has changed. That pair is a starting hypothesis
# rather than a measured runtime minimum. The first runtime window either confirms
# it or returns an AccessDenied naming what is missing, and any widening comes
# from that evidence and owner review rather than from anticipating it here.
resource "aws_iam_role_policy" "external_secrets" {
  name = "cloud-platform-reference-dev-external-secrets-read"
  role = aws_iam_role.external_secrets.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = aws_secretsmanager_secret.workload.arn
      },
    ]
  })
}
