# ADR-0007: Define networking and traffic boundaries

## Status

Proposed

## Context

The environment topology is fixed: one dedicated account in us-east-1 with a
persistent Dev environment and ephemeral Validation and Production Validation
environments (ADR-0004), and each active environment runs its own EKS cluster
(ADR-0006). Networking has to preserve those boundaries. An ephemeral
environment needs a network that appears and disappears with it.

REQ-008 sets the functional bar. Traffic must enter and leave the platform
only through defined, restrictable points, components must reach their
dependencies through stable names, and requests must be routable to a chosen
workload version. The project also intends its final validation to reach a
running workload from the public internet in a real browser, without
exposing nodes or workloads directly.

Network components are among the platform's few standing costs, so the design
must keep that cost deliberate. This is a production-inspired reference, and
this record states plainly where it accepts less than production-grade
availability.

## Decision

Each environment gets its own VPC. The Dev VPC persists while implementation
is active. The Validation and Production Validation VPCs are ephemeral and
are created and destroyed with their environments. Application environments
do not share a VPC. These boundaries are owned by Network and Traffic Control
in the logical architecture.

The two Availability Zone conceptual baseline of ADR-0004 applies to the
network. Public subnets exist only for managed platform components that need
public placement: the internet-facing ingress boundary and the NAT egress
point. EKS worker nodes and workloads run in private subnets and are never
directly reachable from the internet. Exact CIDRs, subnet counts, and route
tables are implementation details.

Public application traffic enters through one managed internet-facing
load-balancing boundary. TLS is required at that boundary, plain HTTP is
redirected to HTTPS, and TLS terminates at the managed ingress layer. The
exact ingress controller, Gateway API implementation, and load-balancer
integration are deferred, and the TLS and redirect requirements already
narrow that choice. Public DNS and managed certificates are required for the
final browser-accessible validation path, and the exact domain, hosted zone,
certificate resources, and naming structure are deferred with them. Internal
Kubernetes service discovery stays separate from public DNS.

Private workloads reach the internet through one NAT Gateway per environment
initially. This is a deliberate cost optimization for the non-production
reference scope, not the zone-independent production pattern. The NAT Gateway
resides in one Availability Zone, so failure of that zone may temporarily
remove internet egress for private resources in the other zone. Egress from
that other zone also crosses zones to reach it, adding transfer cost under
load. That reduced egress resilience is accepted. One NAT Gateway per
Availability Zone is the revisit path when production, availability, or
workload requirements justify it. Ephemeral environments destroy their NAT
Gateway with the VPC. NAT instances are rejected.

AWS service access uses gateway endpoints where they are supported and
materially useful, with object storage as the primary expected case.
Interface endpoints are added only when security, reliability, traffic
volume, or measured NAT-cost benefits justify their recurring cost. There is
no broad default endpoint set.

Network security is layered. VPC boundaries separate environments. Security
Groups protect AWS-level and infrastructure boundaries. Load-balancer rules
protect the public edge. Kubernetes NetworkPolicy protects
workload-to-workload traffic, a layer that takes effect only once an
enforcing network implementation is chosen and enabled. Public exposure is
minimized and workload traffic follows least privilege. Exact rules and
policy manifests are implementation details.

## Considered Options

| Option | Assessment | Outcome |
|---|---|---|
| One VPC per environment | Network lifecycle matches environment lifecycle, isolation and teardown stay provable | Selected |
| Shared VPC across environments | Pays for NAT and endpoints once, but blurs environment isolation and turns teardown into partial cleanup | Rejected |
| Public worker nodes | Simpler and cheaper, but exposes nodes directly and contradicts private placement | Rejected |
| NAT Gateway per Availability Zone | Zone-independent egress at roughly double the standing cost, unjustified at this scope | Revisit path |
| NAT instance | Cheaper but self-managed, against the managed-operations direction | Rejected |
| Broad default interface endpoint set | Recurring hourly cost without evidence of need | Rejected |
| Internal-only application entry | Avoids public exposure but cannot prove the public validation path | Rejected |
| Service mesh, WAF, or CDN now | Capability without a current requirement | Deferred |

## Rationale

Per-environment state (ADR-0003), per-environment lifecycle (ADR-0004), and
per-environment clusters (ADR-0006) all draw the same line, and a
per-environment VPC keeps the network on it. The cost of duplication is
bounded by lifecycle: ephemeral environments pay for their network only while
they exist, and their destruction is part of the project's teardown proof.

Trust follows ADR-0005. It attaches to verified identity and explicit rules,
not to network position. One managed public entry with mandatory TLS keeps
the list of reachable entry points short enough to test, the evidence
REQ-008 asks for.

The single NAT Gateway is the one place where this design knowingly sits
below the production pattern. Writing that weakness down, with its trigger
for change, is worth more in a reference than paying for zone-independent
egress that no requirement asks for yet.

## Consequences

Gained: environment isolation carried through to the network, teardown that
removes the network with the environment, private workload placement behind
one controlled public entry, layered security with distinct owners, a lower
initial standing cost, and a named upgrade path to stronger availability.

Paid for: every active environment duplicates VPC structure. The single NAT
Gateway is an accepted egress availability weakness. NAT Gateways, load
balancers, public IPv4 addresses, interface endpoints, cross-zone traffic,
and data processing all create recurring or usage cost.
Each interface endpoint needs its own justification. The ingress product and
the exact DNS implementation remain unresolved, and this design does not by
itself create production-grade networking.

## Deferred Decisions

This record leaves open, for later decision records or approved
implementation planning: exact CIDRs, subnet counts, route tables, Security
Group rules, NetworkPolicy manifests and their enforcement mechanism, the
endpoint list, the ingress controller, the Gateway API implementation, the
load-balancer integration, the DNS domain and hosted zone, certificate
resources, any WAF, any CDN, any service mesh, and implementation sequencing.

## Revisit Triggers

Revisit this decision if traffic or workload requirements grow beyond the
single-entry model, if NAT data-processing or cross-zone transfer cost rises
beyond its expected level, if availability requirements come to justify a NAT
Gateway per Availability Zone, if a workload needs WAF, CDN, or mesh
capability, or if the DNS and certificate decision changes the public entry
assumptions made here.
