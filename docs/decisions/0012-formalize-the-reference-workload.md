# ADR-0012: Formalize the reference workload

## Status

Accepted (2026-08-01)

## Context

Eleven decisions describe a platform. None of them state what the
platform will actually run, which means most of the requirements have
no subject to be validated against. Seven requirements can be proven
by the platform alone: the documented definition and clean
establishment, environment lifecycle, infrastructure from
version-controlled definitions, controlled change and teardown,
central human authentication, maintenance and upgrades, and cost
visibility. The other twelve cannot. There is no workload version to
route requests to, no instance to fail a health evaluation, no
distributed request path to trace, no fault to induce, and no
application data to restore.

The project charter left one implementation decision open, whether
the platform runs an existing workload or a smaller purpose-built
one, to be weighed on realism, cost, maintainability, delivery value,
observability value, and reproducibility. ADR-0009 deferred workload
selection along with its service scope and any upstream image
exceptions to a later record. This is that record, and those are its
boundaries.

The owner's prior bare-metal platform project ran this same
application and contributes evidence and lessons only. It proved
telemetry collection across a many-service call path, including
distributed traces. It did not prove per-service build and delivery
beyond a single service, and it lost telemetry attribution across
collection hops. Building four to six of these services through a
delivery pipeline is therefore the part that project did not do, and
the application repository this record publishes is derived from the
public upstream project rather than carried across from prior work.

This record sits between architecture and implementation. It decides
what gets built, what does not, what belongs to the platform, what
belongs to the workload, and where each artifact lives. It does not
reopen the runtime, the network boundary, the delivery model, the
observability model, or the recovery model.

## Decision

**The workload is an instrument, not the product.** The platform is
the product. The workload exists to give the twelve requirements a
subject, and every choice below is measured against that purpose. No
part of this record makes the workload a deliverable in its own
right.

**What the workload must provide.** The requirements and accepted
decisions imply a specification, stated independently of any
product. The workload must present more than one separately
deployable component with real calls between them, so a distributed
request path exists to trace and a dependency can be addressed by
stable name. It must serve requests through an entry point reachable
in a browser, since an internal-only entry cannot prove the final
validation path. It must be buildable from source the project
controls, so an artifact can carry provenance back to a commit. It
must be container-packaged and take environment-specific
configuration at runtime. It must expose a health signal that can be
driven to failure on purpose, and run as several interchangeable
instances so a capacity change has a countable result. It must emit
metrics, structured logs, and traces with context propagating across
service boundaries, sent to the platform's collector gateway as its
single telemetry endpoint under ADR-0010. Its services must span at
least two runtimes, because ADR-0009 and ADR-0010 both refuse to
claim uniform test or instrumentation depth, and a single-runtime
subset cannot exercise that honesty. It must offer a fault that can
be induced and reversed deliberately. It must need at least one
secret at runtime and at least one dependency it authenticates to,
and it must hold state that outlives the instances serving it, so a
restore has a subject.
It must be able to run in two visibly different versions, so a halted
rollout and a reversal are observable rather than asserted. It must
onboard through the platform's generic path without bespoke platform
work, and its outbound dependencies must be bounded, because all
private egress crosses one NAT gateway per environment.

**Selection.** The workload is the customized OpenTelemetry Demo
maintained by the owner, referred to in project material as
AstroShop. It is an existing multi-service application that is
already instrumented, already presents a browser-facing entry and a
distributed call path, and is already familiar enough to the owner
that its behavior is not itself the experiment. A purpose-built
workload would have required writing instrumentation, service
dependencies, and failure modes by hand, which is application work
rather than platform work and would have delayed every validation
that depends on it. On the charter's cost criterion the two options
do not separate, because what bounds cost here is subset size rather
than where the workload came from.

**Scope.** The platform runs a capability-derived subset of
approximately four to six owner-built services, not the full upstream
service set. The subset is chosen so that it collectively provides a
browser-reachable frontend, a genuine multi-service request path, one
service backed by durable managed data, at least two implementation
languages or runtimes, a reversible fault-injection path, and
observable health, metrics, logs, traces, and artifact version. No
service is added unless it proves a platform capability the rest of
the subset does not already prove. Scope is set by what must be
demonstrated, never by what the upstream project happens to ship.

**Component classification.** Every workload component falls into
exactly one of three classes. Owner-built components are built from
source in the project's application repository through the delivery
pipeline. Justified upstream exceptions are deployed but not built by
the project, and each carries a recorded engineering justification
and a condition under which it is revisited. Because an exception
image passes through none of the build gates, it does not arrive
unexamined: it is pinned by digest, mirrored into the platform's
registry so no pod start depends on an external service, and scanned
there under the same severity threshold that gates owned services.
What it cannot carry is a build record of its own, so the provenance
chain from running artifact back to a source commit covers
owner-built services only, and that limit is stated rather than
implied. Not-deployed components are absent from every environment,
which includes the workload's bundled observability stack and its
own collector, since telemetry reaches only the platform gateway. A
component excluded from the subset is not an upstream-image
exception, it simply does not run, and the exception register covers
only what actually runs without being owner-built.

**Data durability.** Data that must survive its environment uses a
durable AWS-managed service with native backup and recovery, as
ADR-0011 requires. In-cluster persistence is permitted only for
regenerable or disposable data unless a later record justifies
otherwise and carries its own recovery obligation. The datastore
product, its sizing, and its backup configuration are implementation
decisions and are not chosen here. This record establishes that the
workload holds durable data, which is what puts the workload-data
restore exercise ADR-0011 describes on the platform's list of
standing proofs. That exercise becomes actionable once the datastore
and data model are settled in implementation planning, and the same
step brings its managed backup in as a persistent shared foundation
with its own cost approval.

**Public reproducibility.** The application repository,
cloud-platform-workload on GitLab, is public, and it is the
authoritative reproducibility bridge. It holds the selected workload
source, the project's own modifications, the container build
definitions, whatever tests each service actually has, build scripts,
and the delivery pipeline definitions. The standard it must meet is
concrete: another engineer can clone it and reproduce the workload
without access to any private environment, private repository,
private filesystem path, undocumented patch, or hidden build input.
Nothing in it may depend on the owner's prior bare-metal project,
which contributes lessons and evidence only.

Alongside the source, the derivation is documented: the upstream
project and version it derives from, the selected service subset, the
project's own changes, the excluded services, the justified upstream
exceptions, and licensing and provenance. Documented derivation
supplements the public source. It does not replace it. License and
attribution artifacts travel with the code in the
application repository, since that is where redistribution happens.
The reasoning about why this workload and this subset stays in the
public reference repository, which is where the platform's
engineering argument lives.

Because a second repository is now public, the project's existing
public-artifact discipline applies to it in full: the author identity
requirement, the prohibition on secrets and internal identifiers, and
the pre-publication review of any adapted third-party material.

**Repository boundary.** The application repository holds workload
source, container build definitions, per-service tests, the delivery
pipeline definitions, and the upstream exception register. It never
holds environment values, image digests, desired state, or secret
values. The GitOps repository holds the chart reference, the values
layers, and the per-service digests for each environment, and never
holds application source or secret values. This public reference
repository holds the architecture, the decisions, the Terraform
infrastructure definitions ADR-0003 places in it, the implementation
documentation, the derivation reasoning, and sanitized evidence, and
never holds workload source or cluster desired state. The visibility of the
GitOps repository is not settled here, because it depends on whether
environment definitions expose operational detail that should stay
closed. Secret values stay out of it regardless of that outcome.

## Considered Options

| Option | Assessment | Outcome |
|---|---|---|
| Capability-derived subset of owner-built services | Scope follows the properties that must be demonstrated, and each service earns its place | Selected |
| The full upstream service set | Every per-service obligation, pipeline, registry repository, digest pin, policy rule, instrumentation check and evidence capture, multiplies across three environments while proving no additional property | Rejected |
| A smaller purpose-built workload | Full control, but instrumentation, service dependencies and failure modes would have to be written before any platform validation could begin | Rejected |
| Maximizing owner-built components | Looks rigorous, but rebuilding third-party infrastructure proves nothing about the platform and adds maintenance | Rejected |
| In-cluster durable datastore | Fewer managed services, but ADR-0011 already places durable data in a managed service with native backup | Rejected |
| Private application repository with documented derivation only | Cheaper to publish, but the reproducibility claim would rest on a description rather than something an outsider can clone and check | Rejected |
| Vendoring workload source into this reference repository | One public repository to read, but it mixes the platform's engineering argument with application delivery and breaks the repository boundary ADR-0009 sets | Rejected |

## Rationale

The count is what justifies a workload at all. Twelve requirements
have acceptance criteria that describe something running, and seven
do not. That split is also the honest limit of the workload's role:
it is needed for exactly those twelve, and it is not evidence of
anything else.

Scope is the real decision here, and completeness is the wrong
target. Each owned service carries its own pipeline, container build,
test inventory, health gate, vulnerability gate and any expiring
exception, registry repository with lifecycle and standing cost,
digest pin in every environment, policy rules along its call edges,
instrumentation, telemetry attribute checks, signal-depth record, and
functional evidence at every promotion gate. Those obligations
multiply across three environments. Quadrupling that work by
deploying every upstream service would not prove one additional
property from the specification above. A smaller subset also leaves
room to demonstrate guided onboarding later by adding a service
through the documented path, which a maximal subset would consume in
advance.

Separating not-deployed from upstream exception matters because the
two are easy to conflate and mean opposite things. An excluded
service is a scope decision with no operational surface. A deployed
upstream image is an ownership decision with a running artifact the
project did not build, which is exactly the case that needs a
justification and a revisit condition.

Public source is a stronger reproducibility bridge than documented
derivation because it can be checked. A reader can clone it and fail,
which makes the claim falsifiable. A description of how to obtain and
rebuild the workload can only be believed. The documentation still
matters, because provenance, licensing, and the reasons behind each
modification are not visible from the code, but it supplements rather
than substitutes.

In a production organization this would differ in stated ways: the
workload would be chosen by product need rather than by what
validates a platform, its scope would be set by users rather than by
proof obligations, and the platform team would not own the
application source at all. Those are recorded assumptions, not
claims about this platform.

## Consequences

Gained: a defined subject for the twelve requirements that need one,
a scope rule that resists growth by defaulting to exclusion, an
ownership model that distinguishes absence from delegation, a data
boundary inherited rather than reinvented, a reproducibility claim an
outsider can test, and a clear place for every workload artifact.

Paid for: a second public repository under the same author identity,
secret-free and internal-identifier-free discipline as this one, a
redistribution obligation to carry upstream licensing and attribution
correctly with any adapted material, the sanitization of anything
carried over from prior work before it is published, the
workload-data restore exercise now standing against the platform,
and a managed backup that will arrive later as a billable persistent
foundation. The full source-to-build provenance chain covers
owner-built services. A justified upstream exception has no
project-owned build behind it and therefore no such chain, and a
not-deployed component has no runtime artifact and so no provenance
claim at all. The subset also means the platform demonstrates its
capabilities against part of an application rather than all of it,
which is stated rather than hidden. Accepting this record closes the
workload question the charter and the capability model both still
describe as open, so both need that wording amended.

## Deferred Decisions

This record leaves open, for later decision records or approved
implementation planning: the exact service list and each service's
language and toolchain, the chart version pin and values layout, the
datastore product with its sizing and backup configuration, registry
repository names, the per-service test inventory, the
fault-injection method, whether load generation is needed, resource
requests and limits, network policy rules, workload role names, the
GitOps repository visibility, and branch and access policies for
every repository.

## Revisit Triggers

Revisit this decision if a required property cannot be demonstrated
by the selected subset, if the workload's chart cannot deploy a
subset without modification, if the workload requires durable data
that cannot be placed in a managed service, if the upstream project
changes in a way that makes the derivation costly to maintain, if
upstream licensing changes in a way that affects redistribution, or
if the subset grows to a size where its own maintenance competes with
the platform work it exists to validate.
