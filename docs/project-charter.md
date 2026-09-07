# Project Charter

## Purpose

This project exists to show what platform engineering looks like when the decisions are made deliberately: goals first, then the capabilities the platform must provide, then measurable requirements, and only then architecture and tooling.

The engineering problem it addresses is ordering. Platform work usually starts from a technology list. Someone picks an orchestrator, a provisioning tool, and a delivery pipeline, and the architecture becomes whatever those choices allow. The reasoning rarely survives the build. A system produced this way can work well and still be impossible to evaluate, because nobody can say why it is shaped the way it is or what would justify changing it.

Architecture comes before implementation here because structural decisions are the expensive ones. A tool can be replaced; a structure gets built on. Settling requirements and architecture first keeps the technology replaceable and the reasoning open to inspection. Whatever the platform eventually runs on will be an outcome of those decisions, not their starting point. The working method that enforces this ordering is recorded in [ADR-0001](decisions/0001-adopt-an-architecture-first-evidence-backed-delivery-method.md).

The project is also meant to be read. It is written to hold up in front of a senior engineer first, to be reproducible and teachable second, and to be quickly legible to a recruiter or hiring manager third.

## Vision

When this project is complete, the repository should stand on its own. A new engineer should be able to open it and follow the argument from goals to running system without needing the author in the room. Someone with the listed prerequisites should be able to rebuild the environment from what is written down, and someone newer to platform work should be able to see how each choice was reasoned through.

Decisions will be recorded alongside the alternatives that were rejected, so the platform can be maintained, extended, or replaced by someone who was not there when it was designed. Claims will rest on captured evidence. The whole thing should finish without unnecessary complexity or uncontrolled cloud cost, because restraint is part of the demonstration.

This charter describes the intended outcome, and the rest of the repository has to earn it.

## Engineering Approach

The design work is capability-driven and moves in a fixed sequence. Goals are translated into a capability model, which states what the platform must be able to do. Capabilities produce measurable requirements, and requirements shape the logical architecture. Only when the architecture calls for a concrete component does technology selection begin, and each of those selections will be recorded with its own reasoning. The sequence is the point: a capability can be examined without arguing about products, and a requirement can be tested without caring what implements it.

## Engineering Principles

The work is governed by these principles:

- Engineering decisions before engineering tools.
- Architecture precedes implementation.
- Evidence before public claims.
- Every major decision requires documented reasoning.
- Security is designed, not appended.
- Cost is an engineering constraint.
- Reproducibility is a first-class requirement.
- Complexity must justify measurable value.
- Documentation teaches engineering, not commands.
- Implementation remains replaceable.

The platform is being designed toward five quality objectives:

- **Understandable.** A new engineer can identify the platform's purpose, boundaries, workflows, and major decisions from the documentation.
- **Reproducible.** Approved procedures and repository content can recreate the intended environment without undocumented manual knowledge.
- **Observable.** Engineers can inspect the state of the platform and its workloads through relevant signals.
- **Recoverable.** At least one defined failure or loss scenario has a documented and validated recovery path.
- **Replaceable.** Capability definitions and logical architecture do not depend on one implementation technology.

## Scope

### Included

The project intends to cover the full path from goals to evidence:

- A capability model stating what the platform must be able to do, and a small set of measurable requirements derived from it.
- A logical architecture that satisfies those requirements without depending on a specific vendor or product.
- A working implementation on the target cloud platform, defined and managed as code, with each significant technology selected through a recorded decision at the point the design needs it.
- Controlled software delivery, identity-based access, observability of platform and workload state, documented operations, and validated recovery.
- Evidence for every material claim, including cost visibility and teardown for anything that bills.

The workload question this charter once left open, whether the platform runs an existing application or a smaller purpose-built one, was settled in [ADR-0012](decisions/0012-formalize-the-reference-workload.md). The platform runs a capability-derived subset of an existing multi-service application, chosen because a purpose-built workload would have meant writing instrumentation, service dependencies, and failure modes by hand before any platform validation could begin. The workload is an instrument for validating the platform, never a deliverable of its own.

How the platform is operated and what it is allowed to cost are settled in [ADR-0013](decisions/0013-define-operations-and-cost-guardrails.md): one operating owner, a three-level monthly AWS budget, and one create-to-cleanup lifecycle for every environment role. That record also replaced the assumption that a development environment stays continuously running, which is where this project's cost constraint stopped being a principle and became a design change.

### Intentionally Out of Scope

This is a reference platform, not a hosted service. It will not involve:

- real production traffic or real customers
- an enterprise SLA or 24/7 operations
- full compliance certification
- multi-region disaster recovery
- unlimited scale
- a permanent production environment

Here, production-inspired means the project applies selected professional practices: architecture before implementation, controlled change, identity-based access, repeatable infrastructure, software delivery controls, observability, documented operations, recovery validation, cost awareness, and evidence-backed claims. Treating it as more than that would put claims ahead of evidence.

## Success Criteria

The project will be judged against the following outcomes, none of which are met at the time of writing. These are outcome statements; their measurable form belongs to the requirements baseline.

- The documentation allows another engineer to understand, evaluate, and reproduce the intended platform design.
- The platform can be recreated from documented prerequisites and procedures.
- Major engineering decisions have documented reasoning.
- Infrastructure is defined and managed through code.
- Software delivery is automated and controlled.
- Security controls are intentional and reviewable.
- Metrics, logs, and traces are validated.
- At least one meaningful failure and recovery path is tested.
- Billable resources have a tested teardown path.
- Costs and limitations are documented.
- Public claims are supported by evidence.

Where the result falls short of a target, the shortfall will be documented.
