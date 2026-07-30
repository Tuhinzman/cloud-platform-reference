# ADR-0006: Adopt Amazon EKS as the workload runtime

## Status

Proposed

## Context

Container-based workloads are the approved workload boundary, and the
workload runtime is the platform's second structural blocker: networking,
delivery, release mechanics, and observability all take their realistic
shape from it. The requirements it serves are fixed. Workloads must be
scheduled without manual placement and receive their configuration at
runtime (REQ-009), and health evaluation, failed-instance replacement, and
capacity adjustment must work without an operator watching (REQ-010).

The decisions beneath it are already in place: AWS (ADR-0002), Terraform
with remote state (ADR-0003), one dedicated account in us-east-1 with a
persistent Dev environment and ephemeral Validation and Production
Validation environments (ADR-0004), and centralized identity (ADR-0005).

The project owner has already built and validated self-managed Kubernetes
in an earlier bare-metal platform. Repeating that control-plane work here
would prove nothing new. The reference value of this project lies in
demonstrating managed Kubernetes architecture and operations on AWS. The
owner selected Amazon EKS on that basis, and engineering analysis validated
the direction rather than reopening it.

## Decision

The platform's workload runtime is Amazon EKS with the AWS-managed control
plane. Worker capacity runs on EC2-backed managed node groups initially.

Each active environment gets its own cluster, and no cluster is shared
across environment roles. The Dev cluster is persistent while
implementation is active. The Validation and Production Validation
clusters are ephemeral: created from the same version-controlled
definitions for approved exercises, then destroyed once their evidence is
captured. Cluster lifecycle follows the environment lifecycle fixed in
ADR-0004, and every cluster is created, changed, and removed through the
controlled Terraform workflow of ADR-0003. Node placement follows the two
Availability Zone conceptual baseline.

The Kubernetes version is pinned in the infrastructure definitions and
stays within the EKS standard support window. Upgrades move one minor
version at a time through the controlled change workflow and are tested
before they reach Production Validation. Entering extended support is not
a default path and requires explicit owner review.

Essential cluster add-ons have explicit ownership. Managed add-ons are
preferred where they provide clear lifecycle and compatibility value,
their versions are pinned, and changes follow the same controlled upgrade
workflow. The exact add-on list is an implementation decision.

Workload identity follows the principles of ADR-0005, and its concrete
mechanism is deferred until runtime-related identity needs are evaluated.
The autoscaling implementation, any service mesh, and any multi-cluster
management are deferred, and no permanent production cluster exists in
this project.

## Considered Options

| Option | Assessment | Outcome |
|---|---|---|
| Amazon EKS | Managed control plane with the full Kubernetes API, fits the managed-operations goal | Selected |
| Amazon ECS | Simpler and cheaper, but not Kubernetes, and would not demonstrate the intended progression from self-managed to managed Kubernetes | Rejected |
| ECS with Fargate | Removes node management entirely, at the cost of the operational surface this reference is meant to show | Rejected |
| Self-managed Kubernetes on EC2 | Already demonstrated in the owner's bare-metal project, repeating it adds operational burden without new proof | Rejected |
| App Runner or Lambda class services | Not a general container orchestration platform for this workload boundary | Rejected |

## Rationale

The runtime question here is not whether Kubernetes, but which operational
share of it this project should carry. The bare-metal project already
proved the self-managed share: control-plane lifecycle and operational
responsibility. What remains unproven, and what
this reference is for, is the managed share: consuming a managed control
plane responsibly, operating node groups, pinning and upgrading versions
on a schedule the platform controls, and proving that whole clusters can
be created and destroyed as routine operations.

EKS keeps that operational responsibility honest. AWS runs the control
plane, while upgrades, node capacity, add-on lifecycle, workloads, and
teardown remain the platform's job, executed through the same controlled
workflow as every other piece of infrastructure. The Kubernetes API also
protects the Replaceable quality: workload manifests and operational
skills transfer to any conformant cluster, which keeps the logical
architecture portable even though the control plane is AWS-operated.

Cluster-per-environment extends decisions already made. Environment
isolation lives at the cluster boundary, matching the state isolation of
ADR-0003 and the environment lifecycle of ADR-0004, and every ephemeral
cluster becomes a full-lifecycle proof rather than a namespace cleanup.

## Consequences

Gained: a managed control plane instead of a second control-plane build,
clusters that are repeatable because the ephemeral environments require
it, production-inspired operations with real upgrade and lifecycle duties,
a lower operational floor for one person, and a portfolio that shows
managed Kubernetes work next to the existing self-managed record.

Paid for: the control plane bills for every hour a cluster exists, so the
persistent Dev cluster is a standing cost and every ephemeral cluster adds
cost for its lifetime. The runtime deepens the AWS dependency, and
managed-service constraints bound what can be tuned. Version upgrades stay
the platform's responsibility on the support window's schedule rather than
at leisure. Cluster lifecycle discipline becomes both an engineering
responsibility and a cost-control responsibility.

## Deferred Decisions

This record leaves open, for later decision records or approved
implementation planning: ingress, any service mesh, the autoscaling
implementation, the workload identity mechanism, observability
implementation, backup implementation, node instance types and Spot usage,
the exact add-on list, networking implementation, GitOps and CI/CD
tooling, and the exact Kubernetes version number.

## Revisit Triggers

Revisit this decision if workload characteristics change in a way the
runtime cannot serve well, if AWS pricing changes materially, if
managed-service limitations block a requirement, if runtime portability
concerns grow beyond what the Kubernetes API protects, or if production
requirements ever change the scope of this reference.
