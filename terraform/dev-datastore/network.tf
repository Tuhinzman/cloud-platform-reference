# The Dev network is owned by the dev root; it is looked up by name so this root never
# reads that root's state. A missing or duplicated match fails the plan.
data "aws_vpc" "dev" {
  tags = {
    Name = "cloud-platform-reference-dev-vpc"
  }
}

data "aws_subnet" "private" {
  for_each = toset(["a", "b"])

  vpc_id = data.aws_vpc.dev.id
  tags = {
    Name = "cloud-platform-reference-dev-private-${each.key}"
  }
}

resource "aws_db_subnet_group" "datastore" {
  name       = "cloud-platform-reference-dev-datastore"
  subnet_ids = [for subnet in data.aws_subnet.private : subnet.id]
}

# No egress rule: the provider removes the default allow-all egress.
resource "aws_security_group" "datastore" {
  name        = "cloud-platform-reference-dev-datastore"
  description = "PostgreSQL from the Dev private subnets only"
  vpc_id      = data.aws_vpc.dev.id

  tags = {
    Name = "cloud-platform-reference-dev-datastore"
  }
}

# A network-position boundary, not least privilege: every node and pod in these
# subnets can connect. The EKS cluster security group is recreated each window, so
# referencing it here would block its deletion at teardown.
resource "aws_vpc_security_group_ingress_rule" "postgres" {
  for_each = data.aws_subnet.private

  security_group_id = aws_security_group.datastore.id
  cidr_ipv4         = each.value.cidr_block
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
  description       = "PostgreSQL from private subnet ${each.key}"
}
