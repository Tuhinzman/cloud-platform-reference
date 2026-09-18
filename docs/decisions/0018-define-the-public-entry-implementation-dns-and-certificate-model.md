# ADR-0018: Define the public entry implementation, DNS and certificate model

## Status

Accepted (2026-09-18)

Supersedes nothing. This record is additive and edits no Accepted
decision. It settles decisions ADR-0007 explicitly deferred and decides
nothing ADR-0007 already decided.

## Context

ADR-0007 fixed the traffic model and deferred its implementation. It
decided that public application traffic enters through one managed
internet-facing load-balancing boundary, that TLS is required there, that
plain HTTP is redirected to HTTPS, that TLS terminates at the managed
ingress layer, that public subnets exist only for that boundary and the
NAT egress point, that nodes and workloads are never directly reachable,
that public DNS and managed certificates are required for the final
browser-accessible validation path, and that internal Kubernetes service
discovery stays separate from public DNS. It then deferred, in its own
words, "the ingress controller, the Gateway API implementation, the
load-balancer integration, the DNS domain and hosted zone, certificate
resources", and the naming structure.

Those deferrals were correct while no requirement needed the public path.
ADR-0017 now makes a real external request the centre of the programme's
objective, which makes every deferred item a blocker rather than an open
option. Nothing in the repository implements ingress today: no controller,
no hosted zone, no certificate, no record.

Two constraints from existing records shape the answer rather than being
reopened here. ADR-0013 already decided the certificate model: "the
platform uses a non-exportable public certificate with an integrated AWS
service, which carries no certificate charge", and it already places the
DNS hosted zone on the list of resources retained across windows and
domain registration through an external registrar outside the AWS budget.
Its public IPv4 model already assumes an internet-facing Application Load
Balancer taking one billed address per enabled Availability Zone, which is
two of the three addresses in its two-AZ baseline. This record therefore
adds no address to that model.

## Decision

**Ingress implementation.** The platform uses the AWS Load Balancer
Controller with the Kubernetes `Ingress` API. The Gateway API is not
adopted. The controller is a platform-managed runtime component and is
therefore governed by ADR-0015 for security admission, pinned and upgraded
under ADR-0006, and given AWS permissions through a dedicated Pod Identity
role under ADR-0008.

**Load-balancer integration.** One internet-facing Application Load
Balancer serves an environment, provisioned by the controller from
`Ingress` resources grouped into a single ingress group so that the
environment does not accumulate one balancer per route. Targets are
registered by pod IP rather than by node port, because ADR-0007 places
nodes in private subnets and node-port registration would require exposing
them. The balancer is placed in the environment's public subnets; every
pod it targets stays private.

**The controller owns the balancer's lifecycle, and that is a teardown
obligation rather than a convenience.** The Application Load Balancer, its
listeners, its target groups, the security groups the controller creates
and the public IPv4 addresses the balancer holds are created by an
in-cluster controller and are therefore outside Terraform state. A
`terraform destroy` does not remove them. Teardown order is fixed: the
`Ingress` resources are deleted and the balancer's removal is confirmed
before the cluster is destroyed. A cluster destroyed while an `Ingress`
still exists leaves a billing load balancer with no owner, which is the
exact failure the ADR-0013 ceiling is calibrated against.

**Named orphan-scan classes.** The orphan-resource scan ADR-0013 requires
after every teardown gains the classes below. This enumeration is the
single authoritative one in this record; everywhere else this record
refers to the named orphan-scan classes rather than restating them or
counting them.

Environment-scoped runtime residue, expected to be absent once a teardown
has completed:

1. Application Load Balancers created by the controller.
2. Target groups created by the controller.
3. Listeners and listener rules belonging to those balancers.
4. Security groups created by the controller.
5. Public IPv4 addresses those balancers held and that were not released.
6. Hosted-zone record sets created by the record controller, together
   with their ownership markers.

A provisioning failure class, which is not teardown residue and is not
read as one:

7. Certificates left in `PENDING_VALIDATION`. A certificate in that state
   means a validation path that never completed, in a resource this
   record deliberately persists. Finding one says the foundation is
   incomplete, not that a teardown failed to remove something.

**Controller-created resources carry the six mandatory tags.** ADR-0013
makes six tags mandatory on every resource and makes creating a resource
without them a stop condition. A resource created by a controller rather
than by Terraform is not exempt from that, and this record does not
weaken it. Every controller-created AWS resource that supports tagging
carries all six through the controller's supported default-tagging or
per-resource tagging mechanism. At minimum that covers the load balancer,
its target groups and the security groups the controller creates, and it
covers any other taggable resource the controller creates.

Two consequences follow, and both are binding. The tags are verified on
the **actual created AWS resources**, read back from AWS rather than
inferred from the controller's configuration or from a rendered manifest,
and that verification is a precondition of runtime admission rather than a
check performed afterwards. And if a controller-created taggable resource
cannot carry all six tags through the selected mechanism, that is a HOLD
reported before the runtime window opens. It is never a silent waiver, a
partial tag set accepted in passing, or a reason to narrow what ADR-0013
requires. Tagging is what makes Lifecycle-based orphan detection possible
at all, so a resource created outside Terraform state is the one that
needs its tags most.

**Public hostname strategy.** One registered apex domain, owned by the
owner and registered through an external registrar. Each environment is
reached at its own subdomain label beneath that apex, so an environment's
public name appears and disappears with the environment and no name is
shared across environment roles. The apex itself carries no application
record. The concrete domain string is an owner-private execution input
supplied as a Terraform variable; it is never hardcoded into public
definitions, and whether the live hostname appears in public documentation
is an owner decision rather than an implementation default.

**Route 53 hosted-zone strategy.** One public hosted zone for the apex,
created by Terraform in the existing persistent foundation configuration
root. It is a persistent shared foundation under ADR-0004 and ADR-0013 and
carries the full set of obligations those records require of one: stated
purpose, owner, expected monthly cost, recovery path, decommission path,
retention rule, access boundary, and evidence that it is still needed. It
survives environment teardown. It joins the Terraform state backend, the
registry and the evidence destination as a documented exception in every
zero-resource claim under REQ-019. No new Terraform configuration root is
created for it.

**DNS records follow the ingress lifecycle, and the deletion semantics
are required rather than assumed.** Environment records are created and
removed by an in-cluster record controller reading the `Ingress`
resources, not authored by hand and not created by Terraform. The reason
is teardown provability. That property does not follow from merely using a
record controller: it follows from running one in an ownership mode that
is capable of deletion, and several such controllers default to a mode
that never deletes. The behaviour is therefore fixed here.

The selected implementation must satisfy all of the following, and an
implementation that cannot is not eligible under this record:

1. It creates only records it owns, and never adopts, overwrites or
   modifies a record it did not create.
2. It attaches a durable ownership marker to every record it creates, so
   that ownership is readable from the hosted zone itself rather than
   inferred from naming.
3. It **deletes** the records it owns when the corresponding `Ingress` is
   deleted. An upsert-only or create-only policy, which would leave stale
   environment records behind after teardown, is not an acceptable
   configuration of this component.
4. Its ownership markers allow the orphan scan to identify a leftover
   record as belonging to a destroyed environment rather than to the
   persistent foundation, so that the two are never confused.
5. Its AWS permissions are scoped to the single hosted zone this record
   creates and to no other.

The record controller is a platform-managed runtime component under
ADR-0015 and is pinned and upgraded under ADR-0006, with a Pod Identity
role under ADR-0008 scoped as item 5 requires. **The product is not
selected here.** The behaviour contract above is the architectural
decision, and any implementation satisfying it in full is admissible;
naming a product would decide an implementation detail this record does
not need to own.

**Certificate ownership and validation.** One public AWS Certificate
Manager certificate covering the apex and a single wildcard beneath it,
validated by DNS records in the hosted zone, created by Terraform in the
same persistent foundation root as the zone and retained across
environment teardown. The balancer references it by ARN through an
`Ingress` annotation. Persisting the certificate with the zone is what
keeps validation a one-time event rather than a step inside every runtime
window. A certificate that never completes validation is one of the named
orphan-scan classes above.

**HTTP to HTTPS.** ADR-0007 already decided this and it is not reopened.
This record records only the mechanism: the balancer carries an HTTP
listener whose only action is a redirect to HTTPS, expressed as a
controller annotation on the ingress group rather than as an application
concern. No application receives plain HTTP.

**Lifecycle split.** Persistent: the registered domain, the hosted zone,
the certificate and its validation records. Environment-scoped: the
controllers, the `Ingress` objects, the load balancer with its listeners,
target groups and security groups, the environment's DNS records and their
ownership markers, and the public IPv4 addresses the balancer holds.

**Terraform ownership.** Terraform owns the hosted zone, the certificate,
the certificate validation records and the IAM roles and Pod Identity
associations for both controllers. Terraform does not own the load
balancer, its listeners, its target groups, the controller-created
security groups or the environment DNS records; those are controller-owned
and are governed by the teardown obligation above instead of by state.
This split is recorded because a reader who assumes Terraform owns
everything will draw the wrong conclusion about what `destroy` removes.

**What this record does not decide.** No WAF, no CDN, no service mesh, no
second public entry, no traffic-splitting or version-directed routing, and
no change to the single-NAT egress decision or the two-AZ baseline. The
observability views continue to be reached through the operator's access
path under ADR-0010 and never through this public entry.

## Considered Options

| Option | Assessment | Outcome |
|---|---|---|
| AWS Load Balancer Controller with the `Ingress` API | Satisfies ADR-0007's managed boundary, TLS termination and redirect with the smallest new operational surface, and integrates ACM and pod-IP targets natively | Selected |
| Gateway API with the same controller | Where the ecosystem is heading and a stronger routing model, at the cost of a second API to learn, pin, operate and explain for a single hostname with no traffic-splitting requirement | Rejected, with a revisit trigger |
| An in-cluster ingress proxy behind a network load balancer | Portable across clouds, and moves TLS termination into the cluster, which contradicts ADR-0007's decision that TLS terminates at the managed ingress layer | Rejected |
| Terraform-owned load balancer with target-group binding | Keeps every billable resource in state and removes the teardown ordering risk, at the cost of two owners for one resource and a registration path that still belongs to the controller | Rejected, obligation written down instead |
| DNS records created by Terraform | One owner for DNS, and it must resolve a balancer the controller has not created yet at plan time, which makes ordering fragile inside a timed window | Rejected |
| DNS records updated manually inside each window | Simplest to reason about, and it makes a leftover record a matter of memory rather than of reconciliation | Rejected |
| Record controller bound to the ingress lifecycle, in a deletion-capable ownership mode | One more component to admit under ADR-0015, and it makes record removal provable and leftover records detectable, provided the deletion policy is required rather than left at a default | Selected |
| Certificate created per environment window | Avoids a persistent resource, and pays a DNS validation wait inside every window for a resource that carries no charge when retained | Rejected |
| Wildcard-only certificate without the apex | Slightly narrower, and leaves the apex unusable for any future redirect | Rejected |

## Rationale

ADR-0007 narrowed this choice more than it looks. Mandatory TLS at a
managed boundary, termination at that boundary, a redirect, and private
nodes together select an Application Load Balancer fronting pod IPs. What
was genuinely open was which Kubernetes API expresses it, who owns each
resource, and how the name and the certificate survive an environment that
is destroyed on purpose.

The `Ingress` API is chosen against the direction of the ecosystem, and
the reason is scope rather than preference. This platform needs one
hostname, one certificate and a redirect. The Gateway API's advantages,
role separation across route owners and richer traffic management, answer
problems this platform does not have, and ADR-0009 already deferred
traffic-splitting with its own trigger. Adopting it here would add an API
surface to pin, upgrade and explain in exchange for capability nothing
requires. That is a deferral with a trigger, not a judgement that the
Gateway API is wrong.

The ownership split is the part of this record that matters most, and it
is deliberately uncomfortable. Letting an in-cluster controller create
billable AWS resources outside Terraform state contradicts the instinct
every other record in this project follows, where Terraform is the
authoritative description of intended infrastructure. The alternative,
Terraform-owned balancers with binding objects, keeps that instinct intact
and splits ownership of one resource across two systems that reconcile on
different clocks. Between a clean model with a hidden failure and an
honest model with a written obligation, this record takes the second and
pays for it with a fixed teardown order and the named orphan-scan classes
above. REQ-004 asks for proof that billable resources are absent
afterward, and that proof is stronger when the project has written down
exactly which resources `destroy` will not remove.

Persisting the zone and the certificate while keeping records and the
balancer environment-scoped puts the lifecycle boundary where the cost and
the risk actually sit. The zone and the certificate are cheap, slow to
create and validated once. The balancer and its addresses are the hourly
charge, and they belong to the window that needs them.

In a production organization this would differ in stated ways. DNS would
be delegated from a zone the platform team does not own, certificates
would be issued under an organizational policy, the edge would carry a WAF
and a CDN, and an ingress left behind would be caught by a policy engine
rather than by an orphan scan run by the person who created it. Those are
recorded assumptions, not claims about this platform.

## Consequences

Gained: a browser-reachable path that satisfies ADR-0007's deferred
requirements, a name and a certificate that survive environment teardown,
DNS and balancer lifecycles bound to the object that creates them, an
explicit statement of which billable resources Terraform does not own, and
the named orphan-scan classes, which make teardown proof stronger rather
than assumed.

Paid for: two new platform-managed runtime components to admit under
ADR-0015, scan per window and upgrade under ADR-0006, and two more IAM
roles and Pod Identity associations. A persistent hosted zone with its own
small standing charge and the full persistent-foundation obligation set. A
registered domain with an annual fee outside the AWS budget and a renewal
that is nobody's automated responsibility. A fixed teardown order that, if
violated, leaves a load balancer billing with no owner. And a reference
that demonstrates the `Ingress` API rather than the Gateway API, which a
reviewer may reasonably read as dated.

Not claimed: that the public path is highly available, that it is
protected by a WAF or a CDN, that traffic can be directed to a chosen
workload version, or that anything in this record has been implemented.
None of it has.

## Deferred Decisions

This record leaves open, for later decision records or approved
implementation planning: the exact domain and subdomain labels, the
controller chart versions and pins, listener rules beyond the redirect,
target-group health-check parameters, load-balancer attributes including
idle timeout and access logging, whether access logs are retained and
where, security-group rule detail at the public edge, the
NetworkPolicy enforcement mechanism ADR-0007 still defers, the registrar
and renewal procedure, and the record-controller product, which is
deferred to implementation against the behaviour contract in the Decision
rather than chosen here.

## Revisit Triggers

Revisit if a requirement appears for traffic-splitting, version-directed
routing or multiple route owners, which is where the Gateway API stops
being capability without a requirement. Revisit if the controller-owned
load balancer is found orphaned after any teardown, because that would
mean the written obligation is not a sufficient control and ownership
should move to Terraform. Revisit if a WAF, a CDN or a second public entry
becomes necessary. Revisit if hosted-zone or DNS query cost stops being
negligible. Revisit if the certificate or zone cannot be shared across
environment roles for a reason not anticipated here. Revisit if ADR-0007's
single-entry model is itself reopened.
