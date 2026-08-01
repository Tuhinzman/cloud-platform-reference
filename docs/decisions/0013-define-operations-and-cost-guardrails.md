# ADR-0013: Define operations and cost guardrails

## Status

Proposed (2026-08-01)

Supersedes the continuous Dev runtime portion of ADR-0004. The rest of
ADR-0004 stands unchanged. The same assumption is restated in ADR-0006
and ADR-0007, and the Decision below records exactly how far the
supersession reaches into those two records. No accepted record is
edited.

## Context

Every earlier decision assumed that whatever the architecture required
could be paid for. That assumption is now testable. Terraform manages
infrastructure with per-environment remote state (ADR-0003). One
dedicated account in us-east-1 holds a Dev environment plus ephemeral
Validation and Production Validation environments on a two-AZ baseline
(ADR-0004). Each active environment runs its own EKS cluster (ADR-0006)
with private nodes behind one NAT gateway and a managed TLS entry point
(ADR-0007). Secrets, registry, delivery, observability, recovery, and a
reference workload are all decided (ADR-0008 through ADR-0012), and the
implementation sequence that assembles them is planned.

What is missing is who operates the result, and what it costs to leave
running.

Three requirements drive this record. Any environment or set of billable
resources must be removable through a documented teardown procedure with
its billable resources absent afterward (REQ-004). Cost must be
attributable to the environment and component that created it (REQ-019).
And the platform must remain reproducible from the repository, which is
only true if the operating burden is small enough that one person can
actually carry it.

The owner sets a preferred AWS operating target of approximately 100 USD
per month, a review threshold at 150 USD, and an absolute approved
ceiling at 200 USD. The target is what a normal month should look like.
The ceiling is what the account may never quietly exceed. That spread is
deliberate: implementation months cost more than quiet ones, and a
budget that pretends otherwise gets ignored rather than followed.

## Decision

**Operating ownership.** One person operates this platform: the owner,
in a platform engineer role. Every responsibility below names that
owner, a cadence or triggering event, the evidence it produces, and the
condition that escalates it. Cost and billing are reviewed weekly and
after every environment window. Budget and anomaly review, registry and
retained-resource review, evidence-retention review, and reconciliation
of the environment-hour ledger run on the same weekly cadence. An
orphan-resource scan runs after every teardown. Public documentation is
realigned after any material change.

**Budget policy: a target, a review threshold, and a ceiling.** Three
levels, each with a different meaning.

Approximately 100 USD per month is the **preferred target**. A normal
month should sit near it or below, achieved through short environment
windows, disciplined teardown, and a small persistent foundation.
Approaching it triggers a review, not a stop: compare actual use against
the target, reconcile the environment-hour ledger, verify that the last
teardown completed, and identify retained resources no longer needed.

Approximately 150 USD is the **review threshold**. Reaching or
projecting past it is permitted when the work justifies it, but never
silently. It requires a written cost explanation, an environment-hour
reconciliation, an orphan-resource scan, confirmation that the remaining
work is necessary, and owner review before further billable work.
Optional new billable work stops and unnecessary environments are
destroyed. What continues is stated too, so the threshold is not read as
a shutdown: already-approved evidence capture runs to completion, safety
work continues, and controlled teardown continues, because halting any
of those costs more than it saves. Required additional validation does
not start without renewed owner approval. This is a review gate, not the
ceiling.

Two hundred USD is the **absolute approved ceiling**. At or projected
above it, no new billable resource is created, unnecessary ephemeral
resources are destroyed once the evidence they exist to produce has been
captured, an orphan scan runs, unexplained spend is investigated, and
work resumes only through a new explicit owner decision that changes the
ceiling. Projected or actual spend above it is a hold condition, not a
matter of judgement.

None of these levels is enforced automatically. AWS Budgets and billing
alerts notify. They do not prevent spend. Domain registration through
the external registrar sits outside them because it is not an AWS
charge. Route 53, load balancers, data transfer, storage, and every
other AWS service cost sits inside them.

**Persistent versus variable cost.** Costs divide by lifetime, not by
service. Persistent foundations, enumerated below, bill a small amount
whether or not anything runs. Everything else is driven almost entirely
by how many hours an environment exists: an EKS control plane, a NAT
gateway, a load balancer, and the public IPv4 addresses they require all
bill per hour regardless of whether any workload is deployed.

**Public IPv4 addresses are a first-class cost line.** Public IPv4
addresses bill hourly whether in use or idle. Two rules set the count. A
public NAT gateway must have an Elastic IP associated at creation, which
is one billed address. An internet-facing Application Load Balancer
takes one billed address per enabled Availability Zone. The two-AZ
baseline of ADR-0004 therefore puts three addresses per active
environment into the current cost model. Three is the assumption that
follows from that baseline and the present ingress shape, not a fixed
property of the architecture: change either and the number moves with
it. An Elastic IP that survives a failed teardown keeps billing, so the
orphan-resource scan treats unreleased addresses as a distinct class of
finding rather than a configuration leftover.

**Every environment follows one lifecycle.** Create, implement,
validate, capture evidence, destroy, verify cleanup. This is the normal
path for all three environment roles, including Dev, not an exception
reserved for the ephemeral ones. An environment exists to produce
something, and once that something is captured it has no reason to keep
billing.

**Dev is a reproducible environment role, not an always-running
cluster.** Dev keeps its role, its persistent foundations, and its
identity. What it does not keep is a cluster surviving between work
windows. Its runtime is created for an approved window from
authoritative Terraform and Git sources and destroyed when the window
closes, so each recreation produces evidence for the rebuild-first claim
in ADR-0011 instead of merely costing time.

**What is retained and what is recreated.** Retained across windows,
because their lifecycle and recovery responsibilities justify it:
Terraform state, registry artifacts, secret-store contents, raw evidence
and backup storage, selected durable workload data, and the DNS hosted
zone once the domain phase has created it. Destroyed at the end of an
approved window: the EKS control plane, managed node groups, the NAT
gateway and its Elastic IP, the load balancer, ephemeral volumes, the
in-cluster observability stack, and the workload runtime.
Environment-scoped networking is destroyed too whenever the approved
phase requires a full teardown proof. A VPC, its subnets, its route
tables, and the internet gateway carry no direct hourly charge, but an
uncharged resource is not a free one. Keeping or destroying them is
decided on rebuild time, drift risk, dependency cleanup, CIDR reuse,
whether the phase owes a teardown proof under REQ-004, and operational
simplicity. Direct AWS price is one input among those and never decides
the question on its own. Nothing is retained merely because the
environment role is named Dev.

**What this supersedes in ADR-0004.** Superseded: the assumption that
the Dev runtime stays continuously active. Retained without change: one
AWS account, us-east-1, the Dev, Validation, and Production Validation
environment roles, the two-AZ baseline while an environment is active,
one VPC per active environment, Validation and Production Validation
remaining ephemeral, and recorded owner approval remaining a
precondition for Production Validation.

**Where the same assumption is restated.** ADR-0004 is its origin, but
two later records repeat it in their own decision text: ADR-0006 states
that the Dev cluster is persistent while implementation is active, and
ADR-0007 states that the Dev VPC persists while implementation is
active. Both follow from the ADR-0004 assumption rather than deciding
anything separately, so both move with it. The Dev cluster is created
and destroyed per approved window. The Dev VPC is no longer guaranteed
to persist and is retained or destroyed under the retention rule above.
Nothing else in those two records changes, including one cluster per
active environment, one VPC per active environment, private node
placement, the single managed public entry, and the cluster version and
add-on rules. Neither record is edited, because accepted records are
immutable, so this clause is where a reader finds the full reach of the
supersession.

**Environment-hour forecasts.** Runtime is planned in environment-hours
rather than dollars, because hours are the variable under control. The
initial planning range is roughly 80 to 120 hours for Dev, 30 to 60 for
Validation, and 20 to 40 for Production Validation, or roughly 130 to
220 combined. These are forecasts used to estimate a month before it
starts, not allocations, entitlements, or amounts that should be
consumed because they were forecast. A month that uses far fewer hours
is a better month, not a wasted budget.

Every window records purpose, estimated runtime, estimated cost, owner
approval, and a scheduled teardown before it opens, then actual runtime,
captured evidence, teardown proof, orphan-resource verification, and a
variance explanation after it closes. A ledger carries the same fields
plus start and stop times and attributable actual cost where available.

**Concurrency.** Validation and Production Validation never run at the
same time. At most one ephemeral environment is active. Dev may overlap
with one approved ephemeral environment only when the validation
objective requires interaction or comparison between them, and every
such overlap is estimated and time-boxed separately. Sequential
execution is the normal case.

**Persistent foundation governance.** Every persistent foundation
carries a stated purpose, an owner, an expected monthly cost, a recovery
path, a decommission path, a retention rule, an access boundary, and
evidence that it is still needed. This applies to Terraform state, the
registry, the secret store, the evidence and backup destinations, the
hosted zone, the datastore, and any customer-managed key with a
recurring charge. A small monthly charge does not remove the lifecycle
obligation. Forgotten small resources are the ordinary form of waste.

**Tagging and attribution.** Six tags are mandatory on every resource:
Project, Environment, Component, Lifecycle, Owner, and ManagedBy.
Environment and Component answer where cost came from. Lifecycle
separates persistent from ephemeral and is the only reliable filter an
orphan scan has. ManagedBy separates Terraform-managed resources from
manual ones, which are the resources that usually become orphans.
Creating a resource without these tags is a stop condition. No further
tags are adopted without a stated question they answer.

**Maintenance and upgrade ownership.** Kubernetes version upgrades,
managed add-on upgrades, Argo CD upgrades, and chart or workload
dependency upgrades are validated in an ephemeral environment and carry
rollback evidence before they reach Production Validation. Node image
updates and base image updates are event-driven on security releases and
rely on rolling replacement and the delivery pipeline's existing gates.
Terraform provider and version changes are event-driven and verified by
plan. A failed upgrade validation, an unresolved fixable high or
critical finding, or missing rollback evidence blocks Production
Validation. No calendar dates are fixed, because nothing in the
architecture requires them.

**Cost response stays owner-controlled.** Budget and billing alerts
notify. The owner investigates and deliberately destroys what is not
needed, capturing required evidence before destructive cleanup.
Automated destructive cost response is deferred. It may be reconsidered
only after evidence capture is reliable, teardown ordering is proven,
false-trigger behavior is understood, recovery paths are validated, and
a separate decision approves it. An automated response that fires
incorrectly would destroy an environment before its evidence was
captured, which costs more than the spend it prevents.

**Stop conditions.** Work stops when projected or actual monthly cost
reaches the 200 USD ceiling, when the 150 USD review threshold is
crossed or projected without a written justification, on unexplained
spend, on an orphaned resource, on a resource created without required
tags, when an environment outlives its approved window, when a teardown
fails, when state recovery or secret rotation fails, when the evidence
destination is unavailable, when cost attribution cannot be
demonstrated, when a required budget alert is absent, or when a billable
resource is about to be created without owner approval. Each condition
names what halts, what may continue, who decides, and the evidence
required before resuming.

**Cost estimates are provisional.** Every figure in this record is an
estimate derived from published unit pricing for us-east-1, checked on
2026-08-01, excluding taxes and external fees, and subject to
measurement during implementation. Prices change. Some rates were not
resolvable from the regional pricing tables and are carried as
unresolved rather than assumed. Budget alerts are configured before the
first billable resource is created, and the estimate is re-checked
immediately before that resource exists. Once real cost data arrives,
estimate and actual are compared, material variance is explained, the
envelope is recalibrated, and any higher ceiling requires owner
approval.

## Considered Options

**Keep the Dev runtime continuously active.** The architecture stays
exactly as recorded and no decision has to be revisited.

**Reduce Dev capacity and retention while keeping it continuous.**
Smaller node, fewer nodes, scheduled node capacity, shorter retention,
lifecycle policies, and delayed optional components, with the cluster
itself still running.

**Retain the persistent foundations and schedule the runtime.** The
foundations that hold state stay. The billable runtime is created for
approved windows and destroyed afterward.

## Rationale

The decision follows from one piece of arithmetic that does not depend
on how large the compute is.

A continuously running Dev environment keeps four things billing for
every hour of the month: an EKS control plane, a NAT gateway, a load
balancer, and the three public IPv4 addresses those require under the
two-AZ baseline. At published us-east-1 rates over a 730-hour month that
is approximately 73, 33, 16, and 11 US dollars, or roughly 133 USD
before a single node, volume, registry byte, secret, or datastore is
added. A continuously running Dev environment therefore passes the
preferred target before it does any work at all.

That reframes the question. It is not how small the nodes can be. It is
how many hours anything runs.

| Option | Estimated Dev cost | Plus Validation and Production Validation |
|---|---|---|
| Continuous Dev, minimum credible two-node group | ~200 USD | ~223 USD, above the ceiling |
| Continuous Dev, every legitimate reduction applied | ~148 USD | ~171 USD, past review, near the ceiling |
| Retained foundations, runtime scheduled to ~120 hours | ~33 USD | ~56 USD, below the target |

The second row is what decides it. Applying every reduction that does
not weaken private-node architecture, security boundaries,
recoverability, required observability, required evidence, or the
validation obligations still leaves Dev alone at the review threshold,
because none of those levers touch the per-hour floor. Add the
Validation and Production Validation runtime the requirements demand and
the month passes the review threshold and closes on the ceiling, every
month, permanently. A threshold that is crossed every month is not a
control. The problem is lifecycle, not optimization, and no amount of
tuning reaches the target.

**What a month actually costs.** Monthly cost is driven almost entirely
by approved environment runtime and by whether teardown completes, not
by unit prices. Four shapes are worth naming.

| Month | Estimate | Shape |
|---|---|---|
| Normal target month | ~40 to ~64 USD | 130 to 220 environment-hours, single node, disciplined teardown |
| Active implementation month | ~99 to ~135 USD | Heavier hours and occasional second node, justified against the review threshold |
| Temporary validation burst | ~6 to ~25 USD added | A bounded window, sometimes overlapping Dev, estimated and time-boxed first |
| One forgotten environment | ~188 USD | A single environment left running for a full month |

The last row explains where the ceiling comes from. Two hundred US
dollars is approximately what one environment costs if nobody destroys
it, so the ceiling is set at the price of the exact failure this record
exists to prevent. A burst, by contrast, is cheap. Sustained runtime is
what is expensive, which is why the controls sit on teardown rather than
on sizing, and why a quiet month with two short windows costs a fraction
of a normal one.

Scheduling the runtime also improves two things the project already
claims. Recovery is asserted to be rebuild-first (ADR-0011), and
recreating Dev regularly exercises that claim instead of leaving it to a
single drill. And an environment that is routinely destroyed and
rebuilt makes teardown correctness a daily property rather than an
end-of-project event.

The honest cost is that Dev no longer offers an always-available
cluster. Work needs a recreation window first, and that recreation has
to be reliable enough that the delay is predictable. That burden is
accepted deliberately, and it is the reason this record supersedes part
of ADR-0004 rather than quietly reinterpreting it.

Public IPv4 charges were added to the model after the first pass omitted
them. They did not change the direction of the conclusion. They widened
the gap. The correction is recorded here because a cost model that is
silently wrong is worse than one that is openly provisional.

## Consequences

Gained: a budget with three levels that mean different things, so a busy
implementation month has somewhere legitimate to sit instead of turning
every threshold into noise. A cost model whose largest driver is a
variable the owner controls. An operating model one person can carry. A
supersession that is explicit about its scope. Tagging that makes
attribution and orphan detection possible. And repeated rebuild evidence
as a by-product of the lifecycle rather than an extra exercise.

Paid for: no environment is continuously available, so work carries a
recreation delay and depends on that recreation being dependable. An
environment-hour ledger has to be maintained by hand until cost
attribution can produce it. Scheduling adds a new failure mode, because
a failed recreation now blocks work that a running cluster would have
absorbed. A three-level budget is also more to hold in mind than a
single number, and it only works if the review at 150 USD is genuinely
performed rather than waved through. And because accepted records are
immutable, ADR-0004 keeps its Accepted status with no back-reference,
and so do ADR-0006 and ADR-0007 where the same assumption is restated. A
reader learns the full reach of the supersession from this record and
the repository README, not from those three records themselves.

Not claimed: no saving, because no AWS resource has run and no bill
exists. Every figure here is an estimate from published unit pricing,
not a measured cost.

## Deferred Decisions

The datastore product and its sizing remain deferred (ADR-0012), so the
datastore line in the cost model is a placeholder rather than a
commitment. Node instance type and count, volume sizing, retention
figures, the technical form of the budget alerts, the notification
destination, the concrete scheduling windows, and any customer-managed
key remain implementation decisions. Several published rates could not
be resolved from the regional pricing tables and stay unresolved rather
than assumed: the regional gp3 volume rate, managed relational database
instance rates, and the hourly rate for interface endpoints. One
instance rate used in the model is derived from linear scaling within
its family rather than read directly, and is treated as derived.

The certificate model is not deferred: the platform uses a
non-exportable public certificate with an integrated AWS service, which
carries no certificate charge.

## Revisit Triggers

Revisit when the first month of actual cost data arrives and can be
compared against this estimate. Revisit if the per-hour rate of an EKS
control plane, a NAT gateway, or a public IPv4 address changes
materially. Revisit when the datastore is selected, because an
instance-based choice changes the persistent floor in a way an on-demand
choice does not. Revisit if the work genuinely requires more than one
concurrent environment. Revisit the three budget levels if normal months
land consistently far below the target, which would mean the ceiling is
wider than the work needs, or if the review at 150 USD fires so often
that it stops being informative. And revisit the scheduling decision
itself if recreating an environment proves unreliable or slow enough
that it damages the work it was meant to fund.
