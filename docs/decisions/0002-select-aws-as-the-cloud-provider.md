# ADR-0002: Select AWS as the cloud provider

Status: Accepted (2026-07-29); revised 2026-10-21, decision unchanged.

## Context

The platform needs a cloud provider that supports its requirements,
reproducibility, evidence capture and cost constraints. The owner selected
AWS, and the original engineering assessment found viable implementation
paths for the project's requirements.

## Decision

Use AWS as the cloud provider.

Use the existing account as the dedicated project account. It was recorded
as empty when this decision was accepted, so a new account was unnecessary.

IAM Identity Center is the preferred direction for human authentication.
Its implementation belongs to the identity decision.

Region, account topology, individual services and tooling are decided
separately.

## Rationale

AWS provides suitable identity, infrastructure, runtime, networking,
observability and recovery capabilities. Its account controls and tooling
support the platform's reproducibility and evidence requirements.

The owner's AWS experience reduces delivery risk within the project
timeline. Familiarity supports the choice; it does not replace technical
evaluation.

## Alternatives

Azure and Google Cloud were credible alternatives. Azure's identity and
resource-group model, and Google Cloud's project isolation and cleanup
model, offered useful advantages.

AWS was selected because its capabilities, governance options and the
owner's experience fit this project's delivery constraints.

## Consequences

The platform gains an established provider ecosystem but accepts AWS
dependency and ongoing cost-management responsibilities.

Budgets, alerts and consistent resource tagging are required from the first
resource. Teardown must verify that resources within its scope are removed.
Later decisions must assess provider lock-in.

## Revisit

Reconsider AWS if costs repeatedly exceed expectations, a requirement
becomes impractical or disproportionately expensive, delivery assumptions
fail, pricing or capabilities change materially, or lock-in and teardown
risks become unacceptable.
