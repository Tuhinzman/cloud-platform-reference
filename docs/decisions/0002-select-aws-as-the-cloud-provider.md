# ADR-0002: Select AWS as the cloud provider

## Status

Accepted (2026-07-29)

## Context

The architecture foundation is complete: the project charter, capability model,
requirements baseline, system context, and logical architecture are in place,
and ADR-0001 fixed the working method. The first technology decision the design
needs is the cloud provider, because almost every later decision —
infrastructure definition, environment topology, identity, runtime, networking,
delivery, observability, recovery — draws its realistic options from this one.

The system context models the Cloud Provider Control Plane as an external
system: a substrate and control authority that the platform's automation
drives, never the platform itself. The logical architecture depends on provider
capabilities but names no provider; its eight responsibility groups remain
valid whichever provider is chosen.

The project owner selected AWS as the project direction. Engineering analysis
was performed to validate the owner-selected direction, not to reopen the
provider decision. The validation checked that AWS can satisfy the charter's
constraints, the nineteen requirements, the logical architecture, and this
project's cost, evidence, and teardown expectations, and it recorded where the
credible alternatives are stronger.

## Decision

AWS is the cloud provider for this platform.

The existing AWS account becomes the dedicated project account. This is not a
shortcut. The account is completely empty — no workloads, no unrelated
resources, no production resources — so it delivers the same isolation outcome
a fresh account would: zero migration and cleanup work, no blast radius into
unrelated infrastructure, clean cost attribution, and an uncontaminated
baseline for proving teardown. No new account is required.

AWS IAM Identity Center is the preferred direction for human authentication. It
is a direction only; the identity architecture, including the federation model
and privileged-access mechanics, is deferred to a later identity decision
record.

This record selects the provider and nothing else. No AWS service, region,
account topology, or tool is chosen here.

Existing familiarity reduces execution risk, but it does not replace
engineering evaluation.

## Considered Options

**1. AWS.** The selected direction, validated in the rationale below.

**2. Microsoft Azure.** A credible alternative with real strengths: Entra ID is
a first-party central identity provider with a free tier, the managed
Kubernetes control plane carries no charge on its free tier, and resource
groups give a clean, granular deletion unit that makes environment teardown
easy to prove. It was not chosen because those strengths are not decisive for
this project's requirements, while the constraints that are decisive — delivery
speed inside a constrained window and the need for mature account-level
isolation and governance — favor AWS.

**3. Google Cloud.** The strongest alternative on structural cleanliness: its
project model is the tidiest isolation and teardown unit of the three, and cost
attribution follows that structure almost for free. It was not chosen because
its first-party infrastructure-definition path is the thinnest of the three,
its backup tooling is narrower, and the decisive constraints — delivery speed
and the reference value of building on a provider with broad industry
adoption — favor AWS.

Neither alternative is a strawman: on requirement fit alone, all three
providers pass. The decision was made by the owner on project constraints and
validated by engineering analysis, not produced by an open scoring exercise.

## Rationale

AWS is appropriate for this project because:

- All nineteen requirements have viable provider-level paths: federated human
  authentication, workload identity primitives, managed container runtimes,
  controlled networking, metrics, logs, and traces, backup tooling, and cost
  visibility with attribution and budgets.
- AWS provides mature account-level isolation and governance options, allowing
  later architecture decisions to define the appropriate account topology
  without pre-deciding it here; those options serve the controlled-isolation
  and rebuild-from-nothing obligations (REQ-001, REQ-004).
- It leaves the widest option space for the decision records that follow,
  particularly infrastructure definition and workload runtime, which keeps
  those decisions honest instead of pre-empted.
- Its evidence-capture paths are mature and well documented, which matters in a
  project where every completion claim must be proven.
- AWS is a provider with broad industry adoption and strong relevance to the
  audience this repository is written for.
- The owner's intermediate AWS familiarity lowers delivery risk inside the
  project's constrained delivery window. This is supporting evidence, not the
  primary engineering reason; the reasons above stand without it.

AWS is also weaker in ways this project has to manage rather than deny:

- Teardown ergonomics are weaker than Google Cloud's project deletion or
  Azure's resource-group deletion. There is no single native unit that removes
  everything, so teardown must be proven through the controlled infrastructure
  workflow (REQ-004).
- Idle-cost and billing-surprise risk is the highest of the three; quiet
  standing costs accumulate unless watched.
- Both weaknesses translate into the same obligation: strict cost and lifecycle
  discipline — budgets, alerts, and attribution conventions — from the first
  resource onward (REQ-019).

## Consequences

Gained: faster delivery on a platform the operator already works in, mature
provider-level capabilities behind every logical responsibility group, the
widest option space for later decisions, and a reference with broad industry
relevance.

Paid for: a higher cost-governance burden from day one, because budgets,
alerts, and a strict tagging convention are prerequisites rather than
refinements; teardown proof that must come from the platform's own controlled
workflows rather than one provider-native deletion; and a standing obligation
to check each later decision record for provider lock-in so the logical
architecture stays replaceable.

## Deferred Decisions

This record deliberately leaves open, for their own decision records:
infrastructure definition and state management; environment model and
topology; human identity architecture; workload identity and secret retrieval;
runtime or orchestration; networking and traffic routing; build, delivery, and
artifact storage; progressive release; observability and alert destination;
workload application; and backup and recovery. It also defers region
selection, AWS Organizations and multi-account implementation details,
permission sets, and every AWS service selection.

## Revisit Triggers

Revisit this decision if cloud cost repeatedly exceeds the documented expected
level; if a requirement proves impractical or disproportionately expensive to
satisfy on AWS; if the delivery-speed assumption fails in practice; if AWS
pricing or service changes materially alter the analysis; or if later
decisions create lock-in or teardown risk the logical architecture cannot
absorb. One slow or expensive week does not qualify; a repeating pattern does.
