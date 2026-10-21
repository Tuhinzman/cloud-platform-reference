# ADR-0013: Operations and cost control

Status: Accepted (2026-08-01); revised 2026-10-21, decision unchanged.

## Runtime lifecycle

Run every environment, including Dev, through:

Create → implement → validate → capture evidence → destroy → verify cleanup.

This replaces the continuously running Dev assumption in ADR-0004
and ADR-0006. Dev VPC retention in ADR-0007 follows the rules below.
Other architecture decisions remain unchanged.

Keeping Dev continuously running reduces setup time but incurs idle runtime
costs. Scheduled windows retain the foundations and limit runtime spending,
at the cost of recreating the environment before validation.

Before each window, record its purpose, estimated hours and cost,
owner approval and teardown time. Afterward, record start/end times,
actual usage, evidence, cleanup results and any cost variance.

At window end, remove the EKS control plane, node groups, NAT Gateway
and Elastic IP, load balancers, ephemeral volumes, workloads and
in-cluster observability.

Retain only approved foundations: Terraform state, registry artifacts,
secrets, evidence and backups, selected durable data and the DNS zone.

Remove VPC networking when full teardown is required. Otherwise,
decide retention using rebuild time, drift risk, dependency cleanup,
CIDR reuse and simplicity. Absence of an hourly charge is not sufficient.

Run environments sequentially by default. Validation and Production
Validation must never overlap. Dev may overlap one of them only for
an approved validation need, with separately estimated cost and duration.

## Monthly AWS budget

| Level | Required response |
|---|---|
| About 100 USD: preferred target | As spend approaches it, review usage, runtime hours, previous cleanup and retained resources. This is not a stop threshold. |
| 150 USD: review threshold, actual or forecast | Require written justification, reconciled hours, an orphan check and owner review. Stop optional new billable work. Further required validation needs renewed approval. |
| 200 USD: hard ceiling, actual or forecast | HOLD. Create no new billable resources. Capture required evidence, remove unnecessary runtime, check for orphans and investigate unexplained spend. Resume only after an explicit owner decision changes the ceiling. |

At the 150 USD threshold, already-approved evidence capture, safety work
and controlled teardown may continue.

Include every AWS charge, including public IPv4 addresses, storage,
DNS and data transfer. External registrar charges sit outside this
AWS budget. Count addresses from the actual network configuration.

Configure budget alerts before the first billable resource and recheck
pricing immediately before creation. Compare estimates with actual
cost and explain material differences.

Budget alerts notify; they do not prevent spending. Cost response stays
owner-controlled. Automated destructive cleanup remains deferred.

The certificate model uses non-exportable public certificates integrated
with AWS services, which carry no certificate charge.

## Operating rules

The owner reviews billing after each window and weekly. Weekly review
also covers anomalies, runtime hours, registry retention, retained
resources and evidence retention. Update public documentation after
material changes.

Every retained foundation needs a purpose, owner, expected monthly cost,
access boundary, retention rule, recovery path, final removal procedure
and a continuing reason to exist.

Require these resource tags:
Project, Environment, Component, Lifecycle, Owner and ManagedBy.
Add other tags only for a stated need.

Test Kubernetes, add-on, Argo CD, chart and dependency upgrades in a
temporary environment. Keep rollback evidence before Production Validation.
Use existing security gates and rolling replacement for node/base-image
updates. Verify Terraform and provider changes through a reviewed plan.

Failed upgrade validation, unresolved fixable HIGH or CRITICAL findings,
or missing rollback evidence block Production Validation.

Also HOLD on unapproved billable creation, missing required tags or
budget alerts, unexplained or unattributable cost, expired work windows,
orphaned resources, failed teardown, failed state recovery or secret
rotation, or an unavailable evidence destination. For each HOLD, record
what halts, what may continue, who decides and the evidence required
before resuming.

Check for orphaned billable resources after every teardown, including
unreleased Elastic IPs.

Revisit when actual costs, pricing, concurrency needs or unreliable
recreation make these limits or operating choices unsuitable.
