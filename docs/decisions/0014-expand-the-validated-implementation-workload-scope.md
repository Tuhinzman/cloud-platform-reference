# ADR-0014: Expand the validated implementation workload scope

## Status

Proposed (2026-08-01)

Supersedes one rule in ADR-0012: the limit of approximately four to six
owner-built services. Everything else ADR-0012 decided stands, and it
keeps its Accepted status. No other accepted record is affected.

## Context

ADR-0012 formalized the reference workload and set its scope at roughly
four to six owner-built services, chosen so that each one proved a
platform capability the others did not. That rule was correct for the
question it answered. It bounded a workload that had not been built yet,
against a platform that had not been implemented yet, using the only
evidence available at the time.

Two things have changed since.

The first is evidence. A prior bare-metal platform project built and
exercised most of this application on Kubernetes, and that record has
now been read rather than remembered. It shows which images build, which
service paths run, which telemetry arrives, and which components carry
security debt. It also shows something the earlier scope rule could not
have known: the cost of adding a service to a delivery pipeline is not
what it appears. The per-service pipeline artifact in that project is
under eighty lines of declarative configuration with no pipeline logic
in it. The expensive units are language tiers and security exceptions,
not services.

The second is the implementation objective. The platform is now fully
decided, thirteen records deep, and what remains is proving it operates.
Several of the properties worth proving are properties of breadth rather
than depth: whether one delivery pipeline genuinely serves many services
instead of a few hand-tuned ones, whether reconciliation holds across a
fleet, whether telemetry attribution survives when many services emit at
once, and whether teardown is clean when there is more to clean up.

Those are platform questions. A four to six service workload can answer
them in principle and cannot demonstrate them.

This record widens the implemented workload for that reason. It does not
claim ADR-0012 was wrong, and it does not add a platform requirement.
The requirements baseline is unchanged.

## Decision

**Two scopes, not one.** The workload now has a minimum evidence set and
an implemented fleet, and conflating them is what this record exists to
prevent.

The **minimum evidence set** is unchanged in spirit from ADR-0012. It is
the representative subset whose properties the platform's requirements
actually depend on: a browser-reachable entry, a genuine multi-service
request path, durable managed data, more than one runtime, a reversible
fault path, and observable health, metrics, logs, traces, and artifact
version. Requirement satisfaction is judged against this set. Nothing in
this record moves that bar.

The **implemented fleet** is the complete justified AstroShop
application fleet. It exists to exercise operational breadth, and its
components are not individually load-bearing for any requirement.

**Default deployment excludes the load generator.** It runs as root, its
image carries a large volume of unfixed operating-system findings, and
it proves no platform capability the rest of the fleet does not. It may
be enabled for a bounded, owner-approved validation window and is
otherwise absent.

**Fleet size is not the objective.** No component is included because
the upstream project ships it. Each is included because it belongs to a
justified application path, and the inventory is provisional until
Repository Phase A confirms it against pinned source.

## Component Classification

Five classes. Every deployed component belongs to exactly one, and the
class decides what evidence it owes.

**Project-built application services.** Derived from upstream
application source and built in the project's own repository through the
project's pipeline. The provisional inventory is frontend,
product-catalog, checkout, cart, payment, shipping, recommendation, ad,
currency, accounting, fraud-detection, email, quote, product-reviews,
flagd-ui, and image-provider. The application source is upstream work.
What the project owns here is the container definition, the hardening,
the pipeline, and the evidence, and the record must not blur those.
Within this class the container definitions divide further: some are
modified from upstream, others are used as upstream wrote them, and the
derivation record states which is which per component.

**Project-built configured components.** A component with a container
definition in the project's repository but no upstream application
source behind it. The proxy that fronts the application is the clear
case: it packages an upstream binary with configuration the project
wrote. It is built here, so it carries a build record, an SBOM, and its
own validation, and the project owns that configuration and that
validation. It is not an application service, and no application
provenance is claimed for it. The word dependency is avoided for this
class on purpose, because these components sit on the application's own
request path rather than supporting it from outside, and the class below
already carries that meaning. Whether this stays a separate class or
folds into upstream exceptions is confirmed in Phase A against pinned
source.

**Justified upstream exceptions.** Deployed but not built here, each
with a written justification and a revisit condition. The feature-flag
service is the current case, and it has no container definition upstream
to build from. Under ADR-0012 these are pinned by digest, mirrored into
the platform registry so no pod start depends on an external service,
and scanned there under the same threshold that gates built services.
They carry no build provenance, and that limit is stated rather than
implied.

**Infrastructure dependencies.** Components the application requires
that are not application services: the message broker for the
asynchronous path, the cache behind the cart, and the durable datastore.
Their final form stays open on purpose. ADR-0011 requires data that must
outlive its environment to sit in a managed service with native backup,
which points the datastore at a managed product. The broker and the
cache may remain in-cluster or move to managed services, and that is an
implementation decision with its own cost gate, not a decision this
record makes.

**Not deployed.** The workload's bundled observability stack and its own
collector are absent from every environment, because ADR-0010 assigns
observability to the platform and telemetry reaches only the platform
gateway. A component excluded from the fleet is not an upstream
exception. It simply does not run.

## Evidence Depth

Uniform deep validation across a fleet is not achievable and claiming it
would be dishonest. Evidence therefore has two tiers.

**Fleet-wide minimum, owed by every deployed component.** Its exact
upstream origin or external image origin, its classification, its
modification record, its container definition or image source, its
reusable pipeline configuration where project-built, its build result
where project-built, its current scan result, an SBOM where
project-built, its registry digest, the desired-state digest that
deploys it, its runtime health, its dependency purpose, telemetry
presence where the component technically supports it, its known
limitations, any active security exception, and its teardown result.

**Representative deep validation, owed by paths rather than
components.** The browser entry path, the synchronous multi-service
checkout path, the asynchronous producer to broker to consumer path, the
durable-data path, the feature-control path, the rollback path, the
induced-fault investigation path, the recovery path, and fleet teardown
with orphan verification.

Signal and test depth vary across a polyglot fleet. This record does not
claim otherwise, and the variation is recorded rather than smoothed.

That fleet-wide minimum is carried in a service inventory published in
the application repository, where it sits beside the source and
artifacts whose state it reports. The reference repository links to it
and does not hold a second copy, because two copies of a per-service
status table drift apart. Its status columns stay empty until there is
an implementation to report, since a filled-in inventory ahead of
implementation would be a claim rather than a record.

**Prior evidence is not this platform's evidence.** The bare-metal
project shows that these artifacts and service paths were previously
built and exercised on a different Kubernetes substrate. It lowers
uncertainty about what is likely to work and it is not a prerequisite,
not a dependency, and not proof about this platform. Every item in the
fleet-wide minimum is produced fresh on AWS: the pipeline build, the
tests that actually exist today, today's scan result, the SBOM, the
registry publication, the immutable digest, the desired-state pin and
the promotion that carries it between environments, the cluster runtime
health, the network behaviour, today's telemetry attribution,
functional behaviour, captured evidence, and teardown with orphan
verification. Nothing in this repository may cite the prior project as
evidence that the AWS implementation works.

## Reusable Delivery Model

ADR-0009 already requires each service to have its own pipeline composed
from shared definitions. A wider fleet turns that from a preference into
a constraint, because per-service pipeline logic does not survive
sixteen services.

Delivery uses shared stage templates and language-tier templates, with
each service contributing declarative configuration only. Service-local
pipeline logic requires a written justification. The stages are static
validation where the language offers it, build, whatever tests the
service actually has, container health validation, a scanning evidence
pass, a scanning enforcement pass, SBOM generation, artifact
publication, digest recording, and promotion handoff.

The two-pass scanning order is deliberate and carried forward from prior
experience. The first pass always writes its findings as an artifact
even when the second pass blocks the pipeline, so a blocked build still
leaves triage evidence behind.

Four capabilities have no prior implementation to draw on and are built
here: SBOM generation, federated pipeline credentials to AWS, publication
to the platform registry, and immutable digest recording wired into
GitOps promotion.

One identical job implementation across every language is not promised.
The control structure is shared. Language-tier variation is expected and
justified where it occurs.

## Upstream Attribution Boundary

The application originates in the OpenTelemetry Demo project, licensed
Apache-2.0, and this project derives from a pinned upstream release
verified during Phase A.

Upstream provides the application source, the service architecture, the
protobuf contracts, the existing OpenTelemetry instrumentation, the
upstream chart, and the project structure. The instrumentation in
particular is upstream work, and its presence is part of why this
workload was selected rather than something the project built.

This project provides the container definitions and their
modifications, container hardening, the infrastructure definitions, the
AWS platform architecture, the delivery pipeline design, scanning and
exception governance, SBOM integration, registry publication, the GitOps
structure and promotion model, the platform observability architecture,
the recovery architecture, the validation, the evidence, and the
engineering documentation.

Neither side is overstated. The project did not write this application,
and it is not merely deploying an unchanged one.

Publication is gated on Apache-2.0 compliance. The upstream licence
travels with the code. A NOTICE file is included only if the pinned
upstream release contains one, and none is invented. Modified files
carry a notice that they were changed, which a verified review found
missing on most modified container definitions, so closing that gap is a
mandatory Phase A publication gate. Upstream copyright and licence
notices are retained. A derivation record states the exact upstream
repository and pinned point, the included and excluded components, the
upstream exceptions, the project's modifications, the ownership
boundary, and how to reproduce the result. This record states compliance
obligations and the evidence for them. It offers no legal guarantee.

## Security Exception Policy

Admission is risk-based. Counting findings is not a decision procedure,
and no numeric exception budget is set.

Every active exception records the identifier, the affected package, the
severity, whether a fixed version exists, exploitability in this
context, the runtime exposure of the component, the validation value the
component provides, any compensating control, the justification, the
owner, an expiry, and the condition that removes it.

A component is excluded or held when an exploitable critical finding has
no acceptable mitigation, when a safe fixed version exists and is not
adopted without justification, when the component's value does not
justify its security debt, when the exception cannot be made
time-bound, or when its runtime exposure contradicts the accepted
security model.

The gate is never weakened to make the fleet pass. Prior experience has
one directly relevant lesson: when an upstream base image was itself
vulnerable, the correct answer was to hold the component rather than
suppress the finding or move to a base with a wider attack surface. A
held component is an honest state and this record treats it as one.

## Considered Options

| Option | Assessment | Outcome |
|---|---|---|
| Keep the four to six service limit | Sufficient for every requirement, and unable to demonstrate that one pipeline, one reconciliation model, and one teardown hold across a fleet | Rejected as the implementation scope, retained as the minimum evidence set |
| Expand by language tier to roughly nine services | Cheaper, covers most runtimes, but leaves the asynchronous path and the broader operational surface unexercised | Rejected |
| Implement the complete justified application fleet | Exercises breadth directly, at the cost of a wider exception surface and more tiers to template | Selected |
| Include the load generator by default | Adds synthetic traffic, but the component runs as root with substantial unfixed findings and proves nothing new | Rejected as a default, allowed in a bounded approved window |
| Deploy the upstream bundled observability stack | Would come with the fleet, but ADR-0010 assigns observability to the platform and duplicate collection is waste | Rejected |
| Supersede ADR-0012 entirely | Simpler to read, but discards reasoning that remains correct and overstates what changed | Rejected |

## Rationale

The scope rule in ADR-0012 asked whether a service proves a capability
the others do not. That question is the right one for a minimum evidence
set and the wrong one for an implementation scope, because it measures
components against requirements and the properties now worth proving are
properties of the fleet rather than of any component in it. A sixteenth
service proves nothing on its own. Sixteen services running through one
pipeline prove something no subset can.

The cost of the change is not where it first appears. Adding a service
inside a language tier that the pipeline already supports is declarative
configuration. What costs real effort is a new language tier and, more
seriously, the security exceptions a component brings with it over time.
That is why this record spends its governance on a risk-based exception
policy rather than on a service count, and why held components are
treated as a normal outcome rather than a failure.

Cost is not the constraint. The fleet's resource requests are modest
relative to the environment-hour model in ADR-0013, and the standing
charge is dominated by cluster and network components that exist
regardless of how many services run on them. Deciding scope on runtime
price would have been the wrong axis.

Keeping ADR-0012 accepted matters. Its philosophy holds: the workload is
an instrument, the platform is the product, ownership classes stay
distinct, durable data sits in a managed service, and public
reproducibility and attribution are mandatory. Only its service-count
limit is superseded, and saying so precisely is worth more than a
cleaner-looking replacement.

In a production organization this would differ in stated ways. Workload
scope would follow product need rather than validation value, the
security exception process would involve people other than the person
who opened the exception, and no team would carry sixteen services to
prove a platform. Those are recorded assumptions, not claims about this
platform.

## Consequences

Gained: a delivery model whose reusability can be checked rather than
asserted, an asynchronous path that the earlier scope could not
exercise, telemetry attribution tested under fleet conditions, teardown
proof with something substantial to tear down, and a security policy
that reasons about risk instead of counting.

Paid for: a materially wider vulnerability surface across more language
ecosystems, more language-tier templates to build and maintain, more
registry repositories and digest pins to carry through every
environment, and a derivation and attribution record that must stay
accurate across a larger inventory. Some components will be held or
dropped on security grounds, and the fleet is expected to be incomplete
in stated ways rather than uniformly green.

Not claimed: that every component is secure, that every image is
production-ready, that every service carries equivalent evidence, that
the upstream application is the project's own work, or that any AWS
validation has happened. None of it has. Nothing in this record is
implemented.

## Deferred Decisions

The exact project-built inventory is confirmed in Repository Phase A
against pinned upstream source, and the counts here are provisional. The
language-tier grouping follows from that inventory. Whether the message
broker remains in-cluster for the asynchronous path or moves to a
managed service is an implementation decision with its own cost gate, as
is whether the cache stays in-cluster. The durable datastore product
remains deferred under ADR-0012 and constrained by ADR-0011. Which
components fail the risk-based admission gate cannot be known before
current scans run. Pipeline job layout, template boundaries, registry
repository names, and the exact columns of the service inventory are
implementation decisions.

## Revisit Triggers

Revisit if maintaining the fleet begins to compete with the platform
work it exists to validate, which is the failure ADR-0012 warned about
and this record accepts more exposure to. Revisit if the exception
ledger grows faster than it is retired. Revisit if a language tier
cannot be brought into the shared pipeline without service-local logic
that cannot be justified. Revisit if fleet runtime pushes the monthly
cost model toward the review threshold in ADR-0013. Revisit if upstream
restructures the application in a way that makes the derivation
expensive to maintain, or if upstream licensing changes in a way that
affects redistribution.
