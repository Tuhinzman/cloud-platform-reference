# Dev environment network

Everything the Dev environment will later run needs somewhere to run. This root
creates that: one VPC, two Availability Zones, private subnets for the nodes and
public subnets for managed ingress, and the routing that separates them.

It stops before anything that bills by the hour. There is no NAT gateway, no
Elastic IP, no cluster and no load balancer here, so the network can be created,
reviewed and destroyed without starting a standing charge.
[ADR-0007](../../docs/decisions/0007-define-networking-and-traffic-boundaries.md)
fixes the traffic boundaries this implements, and
[ADR-0004](../../docs/decisions/0004-define-the-environment-and-account-topology.md)
fixes the single account, the region and the two-AZ baseline.

## Why it is a separate root

The two existing roots hold persistent shared foundations: the Terraform state
backend and the durable evidence destination. Both outlive every environment and
are decommissioned at project end.

This root holds environment-lifecycle resources rather than persistent shared
foundations.
[ADR-0013](../../docs/decisions/0013-define-operations-and-cost-guardrails.md)
does not guarantee that the Dev network survives between work windows, and it
does not promise the reverse either. Each phase decides whether to retain or
destroy it on rebuild time, drift risk, dependency cleanup, CIDR reuse,
teardown-proof obligations and operational simplicity. Nothing here is retained
merely because the environment role is called Dev.

State is isolated per root under ADR-0003, so `backend.tf` here uses the key
`dev/terraform.tfstate` and a mistake against this environment cannot reach the
state of either foundation.

## What it creates

| Resource | Purpose |
|---|---|
| `aws_vpc` | `10.20.0.0/16`, DNS support and DNS hostnames both on |
| `aws_subnet` × 2 | Private, `10.20.0.0/20` in us-east-1a and `10.20.16.0/20` in us-east-1b |
| `aws_subnet` × 2 | Public, `10.20.240.0/24` in us-east-1a and `10.20.241.0/24` in us-east-1b |
| `aws_internet_gateway` | The only internet attachment in the VPC |
| `aws_route_table` | Public table |
| `aws_route` | `0.0.0.0/0` from the public table to the internet gateway |
| `aws_route_table` | Private table, with no default route |
| `aws_route_table_association` × 4 | One per subnet, all explicit |
| `aws_vpc_endpoint` | S3 gateway endpoint, attached to the private table only |

None of these carries an hourly charge.

## Address plan

```
VPC        10.20.0.0/16
private-a  10.20.0.0/20      us-east-1a
private-b  10.20.16.0/20     us-east-1b
public-a   10.20.240.0/24    us-east-1a
public-b   10.20.241.0/24    us-east-1b
```

The private blocks start at the bottom of the VPC range and the public blocks
sit at the top, which leaves everything from `10.20.32.0` to `10.20.239.255`
unused and available. Private subnets are the ones that grow, because pods and
nodes consume addresses from them, so the room was left on that side
deliberately.

Every range is written out in `main.tf` as a literal. Deriving them with
`cidrsubnet()` would mean a reviewer has to evaluate the expression before
knowing what the plan will create, and an address plan is worth reading
directly.

Availability Zone names are account-specific. `us-east-1a` in this account does
not necessarily map to the same physical zone as `us-east-1a` in another one.
The two names here are a deliberate selection rather than a default, and before
Phase 4B selects a node instance type, that type has to be checked read-only for
availability in both of these zones.

## Input

One required variable, no default, supplied at execution time and never
committed. `terraform.tfvars.example` shows its shape.

`allowed_account_id` is the dedicated project account. The provider checks the
caller's account against it before doing anything, so running with a credential
for another account fails immediately.

`backend.hcl` is a separate value. It carries the state bucket the bootstrap
root created, which is where this root's own state object goes. This root
creates no bucket, and both filled copies stay untracked.

## Routing

The public table has one default route, to the internet gateway. The private
table has none.

That absence is the design, not an unfinished step. Private egress needs a NAT
gateway, a NAT gateway needs an Elastic IP, and both bill by the hour from the
moment they exist. Adding them is a separate cost decision under ADR-0013 and
belongs to the window that also creates the cluster. Until then, a private
subnet in this VPC has no route off the VPC except the S3 endpoint below.

All four subnets are associated with their intended table explicitly. A subnet
that is left unassociated falls back to the VPC main route table, which AWS
creates on its own and which this root does not manage. The explicit
associations mean no project subnet depends on that unmanaged table, so its
contents cannot quietly become part of this design.

`map_public_ip_on_launch` is `false` on all four subnets, public ones included.
AWS already defaults it to false for subnets created this way, but stating it
keeps a public subnet from reading as though it assigns public addresses on its
own. Anything that needs a public address gets one explicitly.

## The S3 gateway endpoint

A gateway endpoint adds a prefix-list route to the route tables it is associated
with, so traffic bound for S3 leaves through the endpoint instead of the default
route. This slice associates it with the private route table only. The purpose
here is to give the private side a direct S3 path without introducing NAT or
internet egress, and associating it with the public route table is outside this
slice rather than something the endpoint could not do. There is no hourly charge
and no data processing charge for a gateway endpoint.

Its effect is worth stating precisely, because it is easy to overstate. When ECR
image pulls start in a later phase, an ECR pull is two different kinds of
traffic. Image layers are S3-backed, and that part may use this endpoint. The
registry and API calls to `api.ecr` and `dkr.ecr` are not S3 and are not covered
by an S3 gateway endpoint, so under the currently accepted single-NAT design
they would still take the NAT path unless ECR interface endpoints are introduced
later with their own justification and their own hourly cost. This root does not
create those, and nothing here lets ECR traffic bypass NAT as a whole.

The endpoint policy is left at the provider default. A restrictive endpoint
policy is a real control, but it needs to name the buckets and principals it is
protecting, and neither is known in a slice that creates no workload.

## Tagging

The six mandatory tags of ADR-0013 are applied through the provider's
`default_tags` and reach every taggable resource in this root. `aws_route` and
`aws_route_table_association` are not taggable AWS resource types, so they carry
no tags and no separate resource was invented to give them any.

`Lifecycle = ephemeral` means these resources belong to the environment
lifecycle rather than to the persistent shared foundations, which is the
distinction ADR-0013 draws between what is retained across windows and what is
recreated. It does not mean the VPC is destroyed at the end of each working
session. How long a particular approved window keeps this network is a separate
operational decision, and ADR-0013's networking retention rule decides it on
rebuild-time drift, dependency cleanup, CIDR reuse and teardown-proof grounds
rather than on the environment's name.

`Component = network` describes this root accurately today. If NAT and EKS land
in this same root later, a single provider-level component value stops
describing every resource in it, and the tagging approach has to be revisited
before those resources are added. That is a Phase 4B decision and nothing here
pre-empts it.

The two `kubernetes.io/role` tags are per-resource subnet tags that sit
alongside the six. They are what an AWS load balancer controller reads to decide
which subnets to place internet-facing and internal load balancers in. No
`kubernetes.io/cluster` tag is set, because no cluster name has been selected
and no cluster exists.

## What this root does not create

No NAT gateway, no Elastic IP, no EKS control plane, no node group, no IAM role,
no security group, no network ACL, no VPC flow logs, no load balancer, no
interface endpoints, and no Terraform module.

AWS creates a default security group with every VPC, and this root does not
manage it. That group allows traffic between resources that are members of it
and allows all outbound traffic; it is not open to the internet, and nothing
here is a member of it, because this root creates no network interface. Managing
or replacing it belongs with the first workload that actually attaches to the
network.

The absence of flow logs and network ACLs is the same kind of boundary. Both are
real controls, and both are decisions about a network that is carrying traffic.
This one is not carrying any yet.

## Status

**Authored only.** Nothing in this document describes a resource that exists.

- No Terraform command has been run against this root
- The backend has not been initialized and no state object exists at
  `dev/terraform.tfstate`
- No plan has been produced
- No AWS resource has been created by this root
- `terraform fmt`, `terraform validate` and TFLint have not yet been run by the
  owner against this revision, so no static-validation result is claimed
- Phase 4B, which adds the NAT gateway, the EKS control plane and the managed
  node group, is not authorized

TFLint here runs the bundled Terraform ruleset only. It checks Terraform
language and style, and it is not a security scan and carries no AWS-specific
rules.
