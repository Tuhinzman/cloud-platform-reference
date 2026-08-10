# Dev environment network

Everything the Dev environment will later run needs somewhere to run. This root
creates that: one VPC, two Availability Zones, private subnets for the nodes and
public subnets for managed ingress, and the routing that separates them.

It also carries the Dev runtime: one NAT gateway for private egress, an EKS
control plane, and a managed node group on the private subnets. Those bill by
the hour from the moment they exist, which is the reason this environment is
created for an approved window and destroyed afterwards.
[ADR-0007](../../docs/decisions/0007-define-networking-and-traffic-boundaries.md)
fixes the traffic boundaries,
[ADR-0006](../../docs/decisions/0006-adopt-amazon-eks-as-the-workload-runtime.md)
fixes EKS with managed node groups as the runtime, and
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

None of those carries an hourly charge. The runtime below does.

| Resource | Purpose |
|---|---|
| `aws_eip` | Elastic IP for the NAT gateway |
| `aws_nat_gateway` | One gateway in public-a, the only private egress path |
| `aws_route` | `0.0.0.0/0` from the private table to the NAT gateway |
| `aws_iam_role` × 2 | Control plane role and node role, AWS managed policies only |
| `aws_iam_role_policy_attachment` × 4 | One on the cluster role, three on the node role |
| `aws_eks_cluster` | Kubernetes 1.36 control plane |
| `aws_launch_template` | Tags the worker instances and their root volumes, and sets the 20 GiB gp3 root disk |
| `aws_eks_node_group` | Two `m6a.large` on-demand nodes on the private subnets |
| `aws_eks_addon` × 4 | `vpc-cni`, `coredns`, `kube-proxy`, `eks-pod-identity-agent`, each pinned |

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

Two required variables, neither with a default, both supplied at execution time
and neither committed. `terraform.tfvars.example` shows their shape.

`allowed_account_id` is the dedicated project account. The provider checks the
caller's account against it before doing anything, so running with a credential
for another account fails immediately.

`operator_cidr` is the one public IPv4 CIDR allowed to reach the EKS public API
endpoint. Use your own address as a `/32`. It changes whenever you work from a
different network, so expect to update it and re-apply, and a validation rule
rejects a `/0` so the restriction cannot be removed by supplying a wide value.

`backend.hcl` is a separate value. It carries the state bucket the bootstrap
root created, which is where this root's own state object goes. This root
creates no bucket, and both filled copies stay untracked.

## Routing

The public table has one default route, to the internet gateway. The private
table has one to the NAT gateway.

There is a single NAT gateway, in public-a, and both private subnets route
through it. ADR-0007 chose that over one gateway per Availability Zone: a
single gateway halves both the hourly charge and the per-gigabyte processing
charge, and the price is two things worth stating plainly. Losing us-east-1a
takes private egress away from both zones, not one. And every byte leaving
private-b crosses an AZ boundary to reach the gateway, which is slower and
carries cross-AZ transfer cost. A tenant with an availability target would pay
for the second gateway; this environment does not have one.

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

`Component = network` is the provider-level default and no longer fits every
resource, so four of them override it to `runtime` on themselves: the cluster,
the node group and the two IAM roles. The NAT gateway and its Elastic IP stay
`network`, because that is what they are. Cost attribution and orphan scans read
this tag, so the value has to describe the resource rather than the directory it
happens to live in.

A seventh tag, `Name`, is on every taggable resource that does not already carry
a service-level name. It is not one of the six and classifies nothing; it exists
because the console and the CLI list resources by `Name`, and an operator
inspecting or tearing down this environment needs to identify the right one
without cross-referencing IDs. IAM roles, the cluster and the node group have
their own names, so they do not carry it.

The two `kubernetes.io/role` tags are per-resource subnet tags that sit
alongside the six. They are what an AWS load balancer controller reads to decide
which subnets to place internet-facing and internal load balancers in. No
`kubernetes.io/cluster` tag is set, because no cluster name has been selected
and no cluster exists.

## The cluster and the nodes

Kubernetes is pinned to `1.36`. It is not tracking a moving default: an upgrade
is a reviewed code change, which is what makes the version an inspectable fact
rather than whatever AWS happened to offer on the day of the apply.

The node group is two `m6a.large` on-demand instances with 20 GiB disks, on the
private subnets only, with `desired`, `min` and `max` all set to two. There is no
cluster autoscaler in this slice, so capacity changes by code review rather than
by load. Two `m6a.large` provide 4 vCPU and 16 GiB in total before the kubelet,
the CNI and system daemons take their share. That is a hardware statement, not a
workload-capacity claim: nothing has been scheduled on this cluster, so how much
of the AstroShop fleet fits here is unmeasured.

### Why there is a launch template

A managed node group carries tags of its own, and those tags stop at the node
group. They do not reach the EC2 instances it launches or the root volumes
attached to them, and the provider's `default_tags` does not reach them either.
Left alone, the two workers and their disks would run untagged, which breaks the
ADR-0013 tagging contract and hides them from the orphan scans that read those
tags after a teardown.

`aws_launch_template.eks_node` exists for that reason and does nothing else. It
sets no AMI, no user data, no security group, no network interface, no instance
type and no subnet, because EKS supplies all of those for a managed node group
and taking any of them over would mean owning the node bootstrap contract as
well. The 20 GiB gp3 encrypted root volume lives there only because a node group
cannot set `disk_size` while a launch template is attached.

The instances carry the six mandatory tags plus `Name`. The volumes carry the
six; an orphaned volume is found through those, and a `Name` on it would answer
nothing its instance does not already answer.

### Node instance metadata

The template also sets `metadata_options` rather than inheriting whatever the
AMI or the account defaults to. IMDS stays enabled, because the node needs it.
`http_tokens = "required"` turns off IMDSv1, so metadata cannot be read without
first obtaining a token. `http_put_response_hop_limit = 1` is what keeps pods
out: a pod sits one network hop further from IMDS than the host does, so a limit
of one answers the node and drops the pod.

Together those stop an ordinary pod from picking up the node IAM role through
IMDS, which is what ADR-0008 requires. Workload AWS access is meant to come from
EKS Pod Identity instead, and nothing is bound to it yet.

### API endpoint access

Both endpoints are on. The private endpoint keeps node and in-cluster API
traffic inside the VPC. The public endpoint is what lets the operator reach the
API server without a bastion or a VPN, which is why it is on at all.

`public_access_cidrs` is `[var.operator_cidr]`, a single operator address. The
AWS default is `0.0.0.0/0`, which puts the API server on the internet with
authentication as the only barrier, and this root refuses to inherit that. The
variable has no default and no committed value, and its validation rejects a
`/0` so the restriction cannot be silently undone.

The operational cost of that is worth knowing before it bites. The operator's
public address changes with the network they work from, and a stale
`operator_cidr` produces a `kubectl` that times out or is refused against a
cluster that is perfectly healthy. The symptom looks like a broken cluster and
is not one. The fix is to update the ignored `terraform.tfvars` and re-apply,
which changes the endpoint's allow list and nothing else.

### Cluster access, as it currently stands

`authentication_mode` is `API`, and `bootstrap_cluster_creator_admin_permissions`
is true. The identity that creates the cluster becomes a cluster administrator
through EKS bootstrap behaviour, and that grant exists in AWS rather than in
this configuration. No `aws_eks_access_entry` resource represents it here, so
the administrator list is not readable from the repository and is not managed by
Terraform. Expressing access entries explicitly belongs to the identity phase.

### IAM, and one temporary choice

Two roles, each trusting exactly one AWS service and carrying only AWS managed
policies. The cluster role has `AmazonEKSClusterPolicy`. The node role has
`AmazonEKSWorkerNodePolicy`, `AmazonEC2ContainerRegistryPullOnly` and
`AmazonEKS_CNI_Policy`.

`PullOnly` rather than `ReadOnly` on the registry policy. A managed node needs
to pull images and has no reason to describe repositories or read registry
metadata beyond that, and where two policies satisfy the same requirement the
narrower one wins.

`AmazonEKS_CNI_Policy` is a deliberate temporary choice and worth being precise
about. It is infrastructure permission, not workload application permission, and
no application is granted anything by it. It is what the VPC CNI needs in order
to manage pod network interfaces, and placing it on the node role means every
pod that can reach the instance metadata service inherits it. AWS supports this
pattern while the CNI is not yet running under its own identity, and recommends
EKS Pod Identity for add-on IAM instead. This is not the final workload-identity
model; the identity phase revisits it. Until then it is a known widening of the
node's permission surface, recorded rather than hidden.

## Managed add-ons

Four, each pinned to an exact version verified against AWS for Kubernetes 1.36
on 2026-08-09.

| Add-on | Version |
|---|---|
| `vpc-cni` | `v1.22.3-eksbuild.1` |
| `coredns` | `v1.14.3-eksbuild.3` |
| `kube-proxy` | `v1.36.0-eksbuild.13` |
| `eks-pod-identity-agent` | `v1.3.10-eksbuild.3` |

The pins are the point. AWS publishes new add-on revisions continuously, and an
unpinned resource would let one arrive during an apply that was meant to change
something else entirely. ADR-0006 makes add-on upgrades a controlled project
responsibility, so a version change here is a reviewed code change with a diff
rather than a decision AWS makes on the project's behalf.

EKS installs its own self-managed copies of `vpc-cni`, `coredns` and
`kube-proxy` when a cluster is created. The three resources here deliberately
take those over as Terraform-managed add-ons, and
`resolve_conflicts_on_create = "OVERWRITE"` is what settles the field conflicts
that transition produces. The Pod Identity agent is not part of that bootstrap
set and needs no conflict resolution.

`aws-ebs-csi-driver` is out of scope for this slice, so this cluster has no
dynamic block storage provisioner.

## What this root does not create

No security group, no network ACL, no VPC flow logs, no load balancer, no
ingress, no interface endpoints, no EBS CSI driver, no cluster autoscaler, no
OIDC provider, no Pod Identity association, no workload IAM role, no Terraform
module, and no Kubernetes object of any kind. No workload, GitOps, observability
or secret delivery exists on this cluster.

AWS creates a default security group with every VPC, and this root does not
manage it. That group allows traffic between resources that are members of it
and allows all outbound traffic; it is not open to the internet. EKS creates and
manages its own cluster security group, which is what the control plane and the
nodes actually use. Authoring project security groups belongs with the first
workload that needs a boundary narrower than that.

The absence of flow logs and network ACLs is the same kind of boundary. Both are
real controls, and both are decisions about traffic patterns this cluster has
not produced yet.

## Estimated planning baseline

**These are planning figures, not measured runtime cost.** They come from the
pricing verified for ADR-0013 on 2026-08-01 and have not been refreshed here.
ADR-0013 requires a pricing recheck before the runtime is created.

| Component | Verified hourly rate |
|---|---|
| EKS control plane | $0.10 per cluster |
| NAT gateway | $0.045, plus $0.045 per GB processed |
| Public IPv4 address (the NAT Elastic IP) | $0.005 |

That is $0.15 per hour before any node runs. Two `m6a.large` and their EBS
volumes are on top of it, and neither rate is in the verified set, so no total
is stated here. Data processing and cross-AZ transfer are usage-driven and
unknown until the cluster carries traffic.

The figures matter mainly for one reason: this environment is priced by the hour
it exists, so the teardown discipline in ADR-0013 is the cost control, not the
instance size.

## Status

The network exists. The runtime is configuration in this repository and nothing
more.

**Applied and verified against AWS:** the VPC, the four subnets, the internet
gateway, both route tables, the four associations and the S3 gateway endpoint.
Read back from AWS after apply, with a following plan reporting no changes.

**Authored only:** the Elastic IP, the NAT gateway, the private default route,
both IAM roles and their four policy attachments, the EKS cluster, the launch
template, the node group and the four managed add-ons. None of them has been
planned or applied, so no cluster, no node, no NAT gateway and no Elastic IP
exists.

- `terraform fmt`, `terraform validate` and TFLint have not been run against
  this revision, so no static-validation result is claimed for it
- No plan has been produced for the runtime resources
- Nothing has been scheduled on this cluster, so no capacity, reachability or
  workload claim is made
- No workload Pod Identity association exists. The Pod Identity agent add-on is
  the mechanism only; nothing is bound to it

TFLint here runs the bundled Terraform ruleset only. It checks Terraform
language and style, it carries no AWS-specific rules, and it is not a security
scan.
