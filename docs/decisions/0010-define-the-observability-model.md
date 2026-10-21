# ADR-0010: Monitoring, logs and traces

Status: Accepted (2026-07-31); revised 2026-10-21, decision unchanged.

## What we will use

Run one in-cluster observability stack per active environment, using
existing node capacity. Recreate it with the environment and remove it
with runtime after exporting required evidence.

The stack lives inside the environment so that its lifecycle, cost and
isolation follow the environment's, and rebuilding an environment also
proves its observability. AWS managed observability services were not
selected: their data would outlive teardown at a standing ingestion cost,
and correlation would split across vendor models.

Applications send OpenTelemetry data to one Collector gateway per
environment. The gateway enriches and routes telemetry, so services never
learn backend details and stores can change without touching a service.
Applications do not send directly to storage backends.

Use Prometheus for metrics and Grafana for operational views.
Loki is the proposed log store. Select Jaeger or Tempo for traces
using measured trace-to-log correlation on EKS.

Collect platform and workload metrics, logs and traces. Make them
queryable and record actual telemetry coverage per service.

Pin component versions and review upgrades under ADR-0006.
Components needing AWS access use Pod Identity under ADR-0008.

Keep dashboards on the operator access path, without another public
entry. Protect telemetry ingestion through ADR-0007's network controls.

Keep account audit events and selected EKS control-plane logs in
AWS-native services. Do not duplicate them in the observability stack.
A retained audit trail requires separate approval as a persistent
foundation.

## Operating and validation rules

Telemetry must identify the environment, service and deployed image
digest. Add Kubernetes identity at the gateway and verify that it
survives the complete collection path on EKS. Include trace IDs in
logs when trace context exists.

Provide three views: environment health, workload golden signals and
deployed image versions. Each view must answer a practical question
and be referenced by an operating procedure.

Keep alerts small in number and focused on symptoms, including missing
telemetry. Send them to one notification destination. Each alert needs
a clear meaning and first diagnostic step owned by platform operations.
There is no escalation chain.

Investigate distributed faults through traces and startup failures
through workload state, then use logs to explain the cause.
Capture evidence and verify recovery.

Validate one deliberately induced fault from alert through root cause
to confirmed recovery before declaring this implementation complete.

Use short, documented retention periods and verify deletion of expired
data. Bound storage and attribute cardinality, keep sampling simple
and account for trace-store memory use.

Applications must continue during Collector outages. Measure and
record the resulting telemetry loss.

Node-level collection agents and SLO tooling remain deferred.
Revisit if retention, audit, service commitments, operator workload
or unacceptable telemetry loss requires a different model.
