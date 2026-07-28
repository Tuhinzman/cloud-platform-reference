# Platform Capability Model

## Purpose

This document states what the platform must be able to do. It sits between the [Project Charter](project-charter.md), which explains why the project exists, and the [Requirements Baseline](requirements-baseline.md), which attaches measurable conditions to what is written here.

Capabilities are separated from implementation so the architecture can be judged on whether it satisfies them.

## How to Read This Model

A capability describes what the platform must be able to do without prescribing how it is implemented. To earn a place here, a capability has to be technology-neutral, describe useful platform behavior, and support at least one future requirement.

Each capability has an identifier of the form `CAP-<domain-code>-NN`, numbered sequentially inside its domain. Every capability has one owning domain; where another domain depends on it, the text points to the owner.

Every capability in this document is a target; the measurable conditions each must satisfy are defined in the [Requirements Baseline](requirements-baseline.md).

## Domain Overview

| Domain | Purpose | Capabilities |
|---|---|---|
| Platform Foundation | Defines the platform itself: its documentation, environments, and configuration boundaries. | CAP-PF-01 to 03 |
| Infrastructure | Creates, changes, and removes the platform's infrastructure in a controlled, repeatable way. | CAP-INF-01 to 04 |
| Identity & Security | Controls who and what can act on the platform, and makes those actions accountable. | CAP-IS-01 to 06 |
| Networking | Governs how traffic enters, leaves, and moves inside the platform. | CAP-NET-01 to 03 |
| Application Runtime | Runs workloads and keeps them running. | CAP-RT-01 to 03 |
| Software Delivery | Moves changes from source to production under control. | CAP-SD-01 to 04 |
| Observability | Makes platform and workload behavior visible and explainable. | CAP-OBS-01 to 03 |
| Resilience | Prepares for loss and failure, and proves that recovery works. | CAP-RES-01 to 02 |
| Platform Operations | Keeps the platform healthy and maintainable day to day. | CAP-OPS-01 to 02 |
| Cost Management | Keeps cloud spend visible, attributable, and deliberate. | CAP-COST-01 to 02 |

Domains are peers; the order above is presentational, not an execution sequence.

## Platform Foundation

- **CAP-PF-01 — Documented platform definition.** The platform's structure, conventions, and the prerequisites and order needed to establish it from nothing are documented in the repository itself.
- **CAP-PF-02 — Environment lifecycle.** The platform can provide isolated environments with a stated purpose and lifecycle, including short-lived environments that exist only for validation and are removed afterwards (via CAP-INF-03).
- **CAP-PF-03 — Configuration separation.** Environment-specific configuration stays separate from shared platform definitions, so shared definitions can serve every environment.

## Infrastructure

- **CAP-INF-01 — Provisioning from versioned definitions.** All platform infrastructure beyond documented bootstrap prerequisites is provisioned from definitions held in version control.
- **CAP-INF-02 — Controlled, drift-resistant change.** Infrastructure changes are approved and validated before automation applies them, and the declared state stays authoritative: divergence between declared and actual state can be detected and corrected through the same workflow.
- **CAP-INF-03 — Clean teardown.** Any environment or set of billable resources can be removed cleanly and completely.
- **CAP-INF-04 — Rebuild from nothing.** The platform's infrastructure can be recreated from the repository and its documented prerequisites alone.

## Identity & Security

Identity is the platform's primary security boundary: trust is granted to verified identities, not to network locations.

- **CAP-IS-01 — Central human authentication.** People authenticate through a central federated identity source; per-system local accounts are not the operating model for human access.
- **CAP-IS-02 — Accountable authorization.** Access is granted to identities based on need, and every grant and security-relevant action can be attributed and reviewed.
- **CAP-IS-03 — Workload identity.** Workloads authenticate with identities rather than long-lived static credentials where practical and supported by the selected runtime and external services; exceptions require documented justification.
- **CAP-IS-04 — Secret handling.** Secrets are retrieved at runtime from an external secret source and never embedded in code, images, or repositories.
- **CAP-IS-05 — Privileged access.** Permanent privileged access is minimized; elevated access is explicitly granted, scoped, and preferably time-bound.
- **CAP-IS-06 — Supply-chain protection.** The artifacts the platform runs can be traced to the source change and build that produced them (CAP-SD-01).

## Networking

- **CAP-NET-01 — Controlled ingress and egress.** Traffic enters and leaves the platform only through defined points that can be restricted.
- **CAP-NET-02 — Internal connectivity and naming.** Platform components and workloads can reach the services they depend on by stable name; this capability also serves the runtime's service discovery.
- **CAP-NET-03 — Traffic routing.** Requests can be directed to a specific workload or workload version, which is what makes progressive release (CAP-SD-03) possible.

## Application Runtime

Container-based workloads are the platform's workload boundary; the runtime that provides this is a later, recorded decision. Which application the platform will run also remains open, and these capabilities apply regardless.

- **CAP-RT-01 — Run container-based workloads.** Workloads packaged as containers can be run and scheduled onto available capacity without manual placement, receiving their environment-specific configuration at runtime.
- **CAP-RT-02 — Health evaluation.** Workload health is continuously evaluated. Instances that fail evaluation are replaced without waiting for an operator.
- **CAP-RT-03 — Scaling.** Workload capacity can be raised or lowered, and can follow demand where the workload justifies it.

## Software Delivery

- **CAP-SD-01 — Source-controlled build and validation.** Every change originates in version control and is automatically built and validated into a versioned, retained artifact before it can be deployed.
- **CAP-SD-02 — Controlled promotion.** Deployments move through environments in a defined order, and reaching production requires an explicit approval.
- **CAP-SD-03 — Progressive, abortable release.** A release can be rolled out progressively, halted mid-way, and reversed, with a defined path back to the last known-good state when it fails.
- **CAP-SD-04 — Guided onboarding.** A new application can be brought onto the platform through a documented, guided path, without bespoke platform work; Platform Operations supports this path but does not own a separate copy of it.

## Observability

- **CAP-OBS-01 — Telemetry collection.** Metrics, logs, and traces can be collected from both the platform and its workloads.
- **CAP-OBS-02 — Inspection and correlation.** Current and historical state can be examined through operational views, and signals from platform and workloads can be correlated so a problem can be followed across that boundary.
- **CAP-OBS-03 — Detection and alerting.** Defined conditions are detected and raised to an engineer with enough context to act.

## Resilience

Resilience here is deliberately modest: prove that recovery works for what matters, rather than claim the platform survives everything.

- **CAP-RES-01 — Backup and restore.** State designated as worth keeping is backed up and can be restored.
- **CAP-RES-02 — Validated recovery.** Defined failure scenarios have documented recovery procedures, and those procedures can be exercised deliberately to prove they work.

## Platform Operations

- **CAP-OPS-01 — Documented operations.** Routine operation and troubleshooting follow documented procedures built on the observability capabilities (CAP-OBS-01 to CAP-OBS-03).
- **CAP-OPS-02 — Controlled maintenance.** Platform components can be maintained and upgraded through the same controlled-change discipline that governs infrastructure (CAP-INF-02).

## Cost Management

The charter treats cost as an engineering constraint; these capabilities make that enforceable.

- **CAP-COST-01 — Cost visibility.** Cloud spend can be inspected and attributed to the environments and components that cause it, and tracked against what was expected.
- **CAP-COST-02 — Billable-resource lifecycle.** Every billable resource has a known purpose and an end-of-life path, using the teardown capability owned by Infrastructure (CAP-INF-03).

## Capability-Level Exclusions

This model stops at behavior. It does not:

- select products or providers; that happens in decision records when the architecture calls for them
- define architecture topology, environment counts, or account structure
- state measurable acceptance criteria; those belong to the requirements baseline
- claim that any capability is implemented
