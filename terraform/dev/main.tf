provider "aws" {
  region = "us-east-1"

  # Any account other than the dedicated project account is a hard stop, so the
  # provider verifies the caller's account before it does anything. A wrong
  # credential then fails at the first API call instead of creating an
  # environment network somewhere it does not belong.
  allowed_account_ids = [var.allowed_account_id]

  # The six mandatory tags of ADR-0013. Unlike the two foundation roots, most of
  # what this root declares is taggable, so these reach the VPC, the four
  # subnets, the internet gateway, both route tables and the endpoint. The route
  # and the four associations expose no AWS tags of their own and are left that
  # way rather than given a tagging workaround.
  #
  # Environment is "dev" and Lifecycle is "ephemeral" because these resources
  # belong to an environment role rather than to a persistent shared foundation.
  # Component is "network" for the whole root, which stays accurate only while
  # this root holds networking alone.
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
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id                  = aws_vpc.dev.id
  cidr_block              = "10.20.16.0/20"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false

  tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.dev.id
  cidr_block              = "10.20.240.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.dev.id
  cidr_block              = "10.20.241.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false

  tags = {
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_internet_gateway" "dev" {
  vpc_id = aws_vpc.dev.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.dev.id
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.dev.id
}

# No default route is declared for the private side. This slice creates no NAT
# gateway, so private egress does not exist yet and starting it is a separate
# cost decision. A private table that looks empty is the intended state rather
# than an omission: it still carries the VPC local route AWS maintains itself,
# and the endpoint below adds the S3 prefix-list route to it.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.dev.id
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
}
