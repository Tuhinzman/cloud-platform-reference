# ADR-0004: Define the environment and account topology

## Status

Proposed

## Context

The requirements baseline asks for environments that come and go on demand:
isolated environments with a declared purpose and lifecycle, including
short-lived validation environments produced from the same shared definitions
(REQ-002). It also asks for a declared promotion order with a recorded
approval before the final stage, where production means a production-like
validation stage rather than a permanently hosted service (REQ-012). The
project charter places a permanent production environment explicitly out of
scope.

The provider, the definition tool, and the primary region are already fixed:
AWS (ADR-0002), Terraform with remote state (ADR-0003), and us-east-1. What
remains is how environments and account boundaries are organized so those
obligations can be met without unnecessary standing cost.

An earlier working direction assumed four environments, with separate QA and
Stage stages. This record simplifies that to three, because separate QA and
Stage environments here would be built from the same definitions and would
repeat similar evidence without adding engineering value.

## Decision

The platform runs in one dedicated AWS account, in us-east-1, with three
environment roles:

- **Dev** is persistent. It is the shared working environment and exists
  while the project is under active implementation.
- **Validation** is ephemeral. It is created for approved validation work,
  carries the QA and Stage responsibilities of the promotion order, and is
  destroyed once its evidence is captured.
- **Production Validation** is ephemeral and exists only for the final
  production-like validation activities. It is not a permanent production
  environment.

Changes promote in one declared order: Dev, then Validation, then Production
Validation. Promotion into Production Validation requires a recorded owner
approval. Evidence is captured before any ephemeral environment is torn
down, and each ephemeral environment is destroyed as soon as its purpose is
complete.

Each environment has its own Terraform state root and its own state object,
and no state root manages more than one environment. A mistake in one
environment cannot reach another through state, which extends the separation
already fixed in ADR-0003.

A small set of shared foundations persists across environment teardown. The
Terraform state backend is the approved case, and other approved persistent
foundations may be added by future ADRs. Every persistent resource carries a
documented purpose, cost visibility, a lifecycle owner, a recovery procedure
where applicable, and a separate final decommission procedure. Everything
else is environment-specific and dies with its environment: the network,
runtime, workloads, load balancing, application data, and environment-scoped
observability components. No exact AWS service is selected by this record.

The conceptual baseline is two Availability Zones, used where later
architecture decisions require or justify it. A third zone needs
justification from a later runtime or service decision.

## Considered Options

Environment models:

| Model | Assessment | Outcome |
|---|---|---|
| Dev only | Cannot demonstrate promotion or environment lifecycle (REQ-002, REQ-012) | Rejected |
| Dev plus Production Validation | Minimal, but leaves little evidence of an intermediate validation stage | Rejected |
| Three roles: Dev, Validation, Production Validation | Full promotion order and lifecycle proof at the lowest credible cost | Selected |
| Four environments with separate QA and Stage | Same definitions, similar evidence, double the middle-stage cost | Rejected |
| Permanent Dev, QA, Stage, Prod | Standing cost with no added proof for a reference project | Rejected |

Account models:

| Model | Assessment | Outcome |
|---|---|---|
| One dedicated account | The existing empty account, with isolation through state, naming, and later identity controls | Selected |
| Two accounts | Better blast radius, paid for with cross-account IAM and a doubled bootstrap | Rejected for now |
| Multi-account with AWS Organizations | The right shape at production scale, unearned complexity here | Deferred, with recorded triggers |

## Rationale

Three roles give the promotion order a real middle stage without running two
near-identical ones. Each role maps to a distinct proof. Validation shows
that an environment can be created from shared definitions, used, and
removed cleanly. Production Validation shows the recorded final approval and
the production-like exercises. Merging QA and Stage removes duplicated
evidence, not capability, because the same definitions can produce as many
ephemeral environments as a task ever needs.

One dedicated account is sufficient because the account is empty, dedicated
to this project, and operated by one person. The controls that matter at
this scale are state separation, naming and tagging conventions, and the
identity decisions that follow in their own record. Account-level isolation
would add cross-account roles and a heavier bootstrap while proving nothing
the requirements ask for, and adopting it because production platforms
usually do would be imitation rather than reasoning. Recording explicit
expansion triggers keeps the single-account choice deliberate and
reversible.

Two Availability Zones are the minimum credible production-inspired
baseline. A single zone would undercut the resilience reasoning the platform
is meant to demonstrate, and a third adds cost before any selected service
demands it.

## Consequences

Gained: a declared lifecycle for every environment, low idle cost because
only Dev and small foundations persist, controlled promotion with a recorded
final approval, ephemeral environments that must be repeatable in order to
exist at all, straightforward teardown proof, and a topology a reader can
hold in their head.

Paid for: one account concentrates blast radius, so isolation rests on state
separation, naming, tagging, and the identity controls decided later. Dev
and the shared foundations carry a standing cost that must stay visible and
reviewed. Ephemeral environments demand repeatable creation and disciplined
evidence capture, since anything manual would defeat their purpose. Where
the two-zone baseline applies, it costs more than a single-zone layout.

## Deferred Decisions

This record leaves open, for later decision records or approved
implementation planning: subnet counts, CIDRs, NAT strategy, the exact
network topology, the runtime platform, IAM roles and policies, delivery
tooling, exact AWS services, environment sizing, observability architecture,
DNS design, artifact storage, and any multi-account or AWS Organizations
implementation.

## Revisit Triggers

Revisit this topology if the platform ever serves real users or real
production traffic, if more than one team works on it, if separation of
duties or compliance requirements appear, if a workload must remain running
as persistent production, if account quotas come under pressure, if
blast-radius concerns outgrow logical isolation, or if billing ownership
needs to split. Any of these reopens the account model in a new decision
record.
