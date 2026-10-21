# ADR-0006: Amazon EKS for workloads

Status: Accepted (2026-07-30); revised 2026-10-21, decision unchanged.

## What we will use

Run container workloads on Amazon EKS with an AWS-managed control plane.
Start with EC2-backed managed node groups for worker capacity.

Each active environment gets its own cluster. Do not share a cluster
between environment roles.

Create, change and remove clusters through the Terraform workflow
in ADR-0003. Use the two-Availability-Zone baseline for node placement.
Node sizing and autoscaling details are decided separately.

EKS fits the project's goal of demonstrating managed Kubernetes on AWS.
AWS operates the control plane; the project remains responsible for
node capacity, add-ons, workloads, upgrades and cleanup.

## How we keep it manageable

Run clusters only during approved work windows. Capture evidence,
destroy runtime when the window ends and verify cleanup.

ADR-0013 replaces the original always-running Dev cluster decision.
There is no permanent production cluster.

Pin the Kubernetes version in Terraform and stay within EKS standard
support. Upgrade one minor version at a time through the reviewed change
workflow. Test upgrades before Production Validation. Entering extended
support requires explicit owner review.

Give each essential add-on an owner and pin its version. Prefer managed
add-ons when they simplify compatibility and maintenance. Follow the
same reviewed upgrade workflow for add-on changes.

Networking, workload identity, delivery and observability are covered
by their own decisions. Service mesh and multi-cluster management
remain deferred.

EKS still carries running costs and AWS-specific constraints. Keeping
clusters temporary controls cost but requires reliable recreation.

Revisit if cost, workload needs, portability requirements or EKS
limitations make this choice unsuitable.
