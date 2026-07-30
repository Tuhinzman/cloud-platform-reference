# ADR-0003: Adopt Terraform and remote state management

## Status

Proposed

## Context

The requirements baseline already fixes what infrastructure work must look
like here. Everything beyond documented bootstrap prerequisites must come from
version-controlled definitions (REQ-003), the platform must be establishable
in a clean account from the repository alone (REQ-001), and every change must
pass approval, surface drift, and tear down cleanly (REQ-004). Manual console
provisioning cannot meet any of that. It leaves no reviewable record, cannot
be repeated, and offers nothing to compare declared intent against.

A declarative tool needs one more thing to do this job: state, the record that
binds each definition to the real resource it manages. Without state the tool
cannot tell what it owns, what drifted, or what to remove. That makes state an
asset in its own right. Losing it orphans resources that keep billing,
concurrent writes corrupt it, and since it can carry sensitive resource
attributes, broad read access is a security exposure.

This record settles the definition model, the tool, and the state-management
model together. They are not separable in practice, because a state pattern is
only concrete relative to a tool, and a tool choice without a state model
cannot be executed.

## Decision

Platform infrastructure will be defined declaratively in version-controlled
Terraform configurations held in this repository. The definitions are the
authoritative description of intended infrastructure state. Anything created
outside them is either imported under management or removed.

State lives in a persistent remote backend rather than on any one machine.
Each environment keeps its own state, isolated at the configuration-root
level. Terraform workspaces are not used for environment isolation, because
they hide which environment a command targets and would constrain the
environment topology before it is decided. The backend itself is excluded
from normal environment destruction and gets a separate, documented final
decommission process.

The backend must provide remote object storage, encryption at rest and in
transit, versioning that can restore prior state, access restricted to the
identities that need it, locking against concurrent writes, and a defined
recovery path. The intended shape is an object-storage backend on AWS using
the native lock file, which removes the need for a separate lock table. That
is a candidate implementation pattern, subject to cost and execution
approval. No backend resource exists yet.

The backend is also the one piece of infrastructure that cannot start from
remote state. It gets a small bootstrap configuration, kept apart from normal
environment definitions, whose initial local state may be migrated into the
backend it creates. The procedure will be documented and approved before it
is ever run.

Every change follows one workflow: format, initialize, validate, static and
security checks, plan, owner review of the plan, apply of the reviewed plan,
post-apply validation, and evidence capture. Destruction follows the same
discipline, with a reviewed destroy plan and a post-destroy check that no
billable resource remains. The workflow starts local and manual. A future
automation pipeline may take over the mechanical steps up to plan, and it
starts plan-only. Automatic apply is not approved by this record.

The backend will use the project's approved primary AWS region, us-east-1.
The environment and account topology decision will record the regional
rationale and its wider architectural consequences. No backend or other AWS
resource will be created without separate cost and execution approval.

## Considered Options

| Option | Strength | Main limitation | Outcome |
|---|---|---|---|
| Terraform | Readable declarative language, near-complete AWS coverage, largest ecosystem of providers and checks | BUSL license and IBM ownership create a standing replaceability concern | Selected |
| OpenTofu | Same language and providers under an open-source license, adds built-in state encryption | Thinner documentation and tooling defaults, less recognized by this repository's audience | Primary alternative and migration path |
| AWS CloudFormation | Service-managed state, no bootstrap problem | Locks the definition layer to one provider and hides state management | Rejected |
| AWS CDK | General-purpose languages for authoring | Inherits CloudFormation's limits, review shifts to generated templates | Rejected |
| Pulumi | Open-source engine, self-managed backends possible | Oriented toward its hosted service, AWS support bridged from Terraform's provider | Rejected |
| Manual console or CLI | None for this project | Contradicts REQ-003 directly, nothing reproducible or reviewable | Rejected baseline |

## Rationale

Terraform is selected on engineering grounds. Its declarative language can be
reviewed by a reader who has never run the tool, and its plan output gives the
approval workflow a concrete artifact to judge, which is exactly what the
controlled-change obligation in REQ-004 needs. AWS provider coverage is
mature and tracks new services closely. Remote state, locking, and drift
detection are first-class rather than bolted on. The surrounding ecosystem of
linters, security scanners, and documentation is the deepest of the options
compared.

The definition language is also cloud-neutral. The logical architecture does
not depend on one provider, and a definition layer with the same property
keeps the Replaceable quality intact in the layer most likely to be rebuilt.

The honest cost of this choice is its license. Terraform is source-available
under BUSL 1.1, not open source, and its steward is now IBM. Using it to
manage this project's own infrastructure is permitted, and the restriction is
aimed at competing commercial offerings, but direction and licensing are
outside this project's control. OpenTofu is the answer this record relies on:
a fork under an open-source license that keeps the same language and provider
ecosystem, close enough that migration is a realistic path rather than a
rewrite. Familiarity and market share were noted during evaluation and were
not treated as engineering justification. Relevance to the audience this
repository is written for carries some weight, as it did in the provider
decision, but the reasons above stand without it.

## Consequences

Gained: infrastructure that can be rebuilt from the repository, changes that
arrive as reviewable plans, drift that becomes visible instead of silent,
teardown as a first-class reviewed operation, and a definition layer that
would survive a provider change better than any provider-native option.

Paid for: state becomes a protected operational dependency with its own
recovery obligations. The backend is a persistent resource that outlives
workload teardown, so it carries a standing cost and lifecycle duty and is
the documented exception in every zero-resource claim under REQ-019. The
bootstrap is a special case that must be documented precisely. The licensing
and ownership situation has to be watched rather than assumed away. Manual
approval on every apply slows delivery, which is accepted while the platform
is small because it keeps early risk down.

## Deferred Decisions

This record leaves open, for later decision records or approved
implementation planning: account topology and environment count, the exact
backend resources and encryption-key choice, IAM roles and policies, the
automation platform, any move beyond plan-only automation, networking,
runtime, secrets tooling, observability tooling, backup implementation, and
module boundaries beyond demonstrated reuse.

## Revisit Triggers

Revisit this decision if Terraform's licensing or product direction changes
materially, if OpenTofu becomes the operationally stronger choice for this
platform, if required AWS capabilities stop arriving in Terraform's provider,
if state locking or recovery proves unreliable in practice, if a multi-account
topology outgrows the chosen state model, or if automation needs change the
approval model this record fixes. One rough week does not qualify. A
repeating pattern does.
