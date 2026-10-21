# ADR-0018: Public HTTPS entry, DNS and certificates

Status: Accepted (2026-09-18); revised 2026-10-21 with one policy change: the
tagging sequence for controller-created resources, which verifies tagging
support and configuration before the window, reads back actual AWS tags
after creation and allows public-path and workload validation only after
that read-back; unsupported or missing required tags remain HOLD.

Resolves implementation choices deferred by ADR-0007.
No Accepted decision is superseded.
The tagging sequence below clarifies ADR-0013's tag rule for
controller-created resources.

## Public entry

Use AWS Load Balancer Controller with the Kubernetes Ingress API.

Each environment has one internet-facing Application Load Balancer.
Group its Ingress resources into one ingress group to share that balancer.
Place the ALB in public subnets and register private pod IPs as targets.
Nodes and workloads remain private.

Terminate TLS at the ALB. Its HTTP listener redirects to HTTPS instead
of forwarding the HTTP request to the application.

The Ingress API was chosen over the Gateway API for scope, not preference:
one hostname, one certificate and a redirect need none of the Gateway API's
route-ownership or traffic-management features, and ADR-0009 already defers
traffic splitting with its own trigger. Letting the controller create
billable resources outside Terraform state is accepted deliberately and paid
for with the fixed teardown order below, rather than splitting one balancer
between two owners that reconcile on different clocks.

Gateway API, WAF, CDN, service mesh, traffic splitting and a second public
entry are outside this decision. Observability interfaces remain accessible
through the operator access path, not this public entry.

## DNS and certificates

Use one owner-registered apex domain and one public Route 53 hosted zone.
Give each environment a separate subdomain. The apex has no application
record, and environment roles do not share a hostname.

Supply the domain through a private Terraform variable. Do not hardcode
it in public definitions. Publishing a live hostname is an owner decision.

Terraform manages one non-exportable public ACM certificate covering
the apex and one wildcard beneath it, plus its DNS validation records.
The Ingress references the certificate by ARN.

Keep the zone, certificate and validation records in the existing
persistent foundation root. They survive runtime teardown because they
are cheap, slow to create and validated once, while the balancer and its
addresses are the hourly charge and belong to the window that needs them.
Domain registration remains with the external registrar and outside the
AWS budget.

An in-cluster DNS controller manages environment records from Ingress
resources. Its required behavior is:

- Create and manage only its own records; never adopt or modify others.
- Attach durable ownership markers readable from the hosted zone,
  identifying the owning environment.
- Delete its records and ownership markers when the Ingress is deleted.
  Create-only and upsert-only operation are insufficient.
- Restrict AWS permissions to the selected hosted zone.

The DNS product is an implementation choice. Both controllers follow
ADR-0015 security admission, ADR-0006 version controls and ADR-0008
dedicated Pod Identity roles.

## Ownership and tags

| Owner | Resources |
|---|---|
| Terraform | Hosted zone, ACM certificate, certificate validation records, controller IAM roles and Pod Identity associations. |
| Controllers | ALB, listeners and rules, target groups, controller-created security groups, environment DNS records and ownership markers. |

Every controller-created AWS resource that supports tags must carry:
Project, Environment, Component, Lifecycle, Owner and ManagedBy.

Tagging sequence:

1. Before the window, verify that the selected controller mechanisms
   support all six tags and that their configuration supplies them.
2. After resource creation, read the actual tags from AWS. Configuration
   or rendered manifests alone are insufficient evidence.
3. Proceed with public-path and workload validation only after read-back
   passes. Unsupported or missing tags mean HOLD.

## Teardown

Delete Ingress resources while both controllers are still running.
Confirm removal of the ALB and environment DNS records before destroying
the cluster. Terraform does not manage these controller-created resources.

After teardown, check for:

- Controller-created ALBs.
- Controller-created target groups.
- Their listeners and listener rules.
- Controller-created security groups.
- Unreleased public IPv4 addresses held by those ALBs.
- Environment DNS records and their ownership markers.

Check certificates left in PENDING_VALIDATION separately. They indicate
incomplete foundation provisioning, not runtime teardown residue.

Retain the domain, hosted zone, certificate and certificate validation
records. Document retained AWS foundations under ADR-0013 and declare them
in any zero-resource claim.

## Limits and future decisions

Runtime approval and cost controls follow ADR-0013. This design does not
establish implementation, successful public access or high availability.

Concrete names, controller versions, health checks, edge security-group
rules, timeouts, access logging, NetworkPolicy enforcement and registrar
renewal procedures remain implementation decisions under the relevant ADRs.

Revisit when richer routing or multiple route owners are needed, an ALB
is orphaned after teardown, another public entry or edge service becomes
necessary, DNS costs become material, or the shared zone and certificate
model no longer fits. An orphaned ALB requires reviewing whether Terraform
should own its lifecycle.
