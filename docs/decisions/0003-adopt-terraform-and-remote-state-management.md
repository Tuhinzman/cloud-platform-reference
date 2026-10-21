# ADR-0003: Adopt Terraform and remote state management

Status: Accepted (2026-07-30); revised 2026-10-21, decision unchanged.

## Context

Infrastructure must be reproducible from version-controlled definitions.
Changes must be reviewable, drift visible and teardown verifiable.

Terraform state connects those definitions to real resources. It needs
protection because it can contain sensitive data and is necessary to
manage existing infrastructure.

## Decision

Use Terraform configurations in this repository to define infrastructure.
Import or remove resources created outside approved management. Resources
assigned to controllers by later Accepted ADRs follow those ownership rules.

Store state in a persistent remote backend in us-east-1. Separate
environments through configuration roots and state objects, not Terraform
workspaces.

The backend must provide:
- Encryption at rest and in transit.
- Access limited to identities that need it.
- Versioning and a documented recovery procedure.
- Locking to prevent concurrent writes.

AWS object storage with native lock files is the proposed backend pattern.
Exact resources and encryption-key choices remain implementation decisions.

Create the backend through a small, separate bootstrap configuration.
Document and approve the procedure before running it. Initial local state
may then migrate into the backend.

Infrastructure changes follow this workflow:

Format → initialize → validate → static and security checks → plan →
owner review → apply the reviewed plan → validate and capture evidence.

Destruction requires a reviewed destroy plan and verification that billable
resources within its scope are gone. The backend survives normal environment
teardown and has a separate final decommission procedure.

Start with local, manual execution. Future automation begins plan-only.
Automatic apply is not authorized. AWS resource creation requires separate
owner approval for cost and execution.

## Rationale and Alternatives

Terraform provides readable configurations, reviewable plans and established
AWS tooling. OpenTofu is the primary alternative and potential migration path.

CloudFormation and CDK couple infrastructure definitions to AWS. Pulumi was
considered, but Terraform's declarative workflow better fits this reference.
Manual provisioning does not meet its reproducibility requirements.

## Consequences

Infrastructure changes and drift become reviewable. State becomes an
operational dependency with security, recovery and maintenance duties.

The retained backend carries ongoing cost and must be declared in any
zero-resource claim. Terraform licensing and product direction remain risks.

## Revisit

Reconsider if licensing or product direction changes materially, OpenTofu
becomes operationally preferable, required provider capabilities are missing,
locking or recovery proves unreliable, or topology and automation needs
outgrow this model.
