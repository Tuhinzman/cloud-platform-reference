# ADR-0014: Workload scope and evidence

Status: Accepted (2026-08-01); revised 2026-10-21, decision unchanged.

Replaces only ADR-0012's four-to-six-service cap. Later scope changes
follow ADR-0016 and ADR-0017.

## Scope

The platform is the product. AstroShop provides the workload used to
validate it.

Keep two scopes:

- Minimum evidence set: representative services that prove the required
  platform capabilities.
- Implemented fleet: the full justified application fleet, subject to
  ADR-0016 and ADR-0017, used to test shared delivery, telemetry and cleanup.

Every component must support a useful application or validation path.
A larger service count does not itself prove a better platform.

Classify each inventory component once:

- Project-built application service: upstream source built in project CI.
  Record whether its container definition is unchanged or modified.
- Project-built configured component: an upstream binary packaged with
  project configuration, such as the frontend proxy. Record the build
  and SBOM without claiming authorship of the upstream binary.
- Upstream exception: a component not built here. Record its justification
  and revisit condition. Pin its digest, mirror it to platform ECR and
  scan it there against the same gate. Do not claim project build provenance.
- Infrastructure dependency: a broker, cache or datastore. Choose managed
  or in-cluster operation based on need and cost. Data that must survive
  teardown follows ADR-0011's managed backup requirement.
- Not deployed: excluded components, including the workload's bundled
  observability stack and Collector. Workload telemetry uses the platform
  gateway.

The load generator stays excluded by default. It may run only within a
bounded, owner-approved validation window.

## Delivery and evidence

Use shared pipeline stages and language templates. Services provide
declarative configuration; service-specific pipeline logic needs written
justification.

Follow ADR-0009 for available static checks and tests, builds, container
health checks, scanning, SBOMs, publication and digest handoff. Retain scan
findings before enforcing the security gate so blocked builds still
produce useful evidence.

Keep the service inventory in the application repository. The reference
repository links to it instead of maintaining a second inventory.

For each deployed component, record:

- Origin, classification, modifications, container definition or source
  image, and dependency purpose.
- Shared pipeline and build result for project-built components, their
  SBOM, scan results, registry digest and desired-state digest.
- Runtime health, telemetry where supported, limitations, active
  exceptions and teardown results.

Use representative paths for deeper validation: browser entry,
multi-service checkout, asynchronous processing, durable data, feature
control, rollback, fault investigation, recovery and fleet teardown
with orphan checks. Cover more than one application runtime.

Evidence depth may differ between components. Record what was observed;
planned work is not validated work. Prior bare-metal results do not
prove AWS behavior.

Preserve upstream attribution: LICENSE, copyright notices, NOTICE when
supplied, and notices identifying modified files. Keep a derivation
record with the exact upstream version, included and excluded components,
exceptions, modifications, ownership and reproduction instructions.

## Security and limits

Keep the fixed ADR-0009 security gate. Platform-managed runtime components
also follow ADR-0015.

Exceptions are risk-based, with no numeric quota. Each exception records
the finding ID, affected package, severity, fixed-version availability,
exploitability, runtime exposure, validation value, compensating controls,
justification, owner, expiry and removal condition.

Hold or exclude a component when:

- An exploitable CRITICAL finding has no acceptable mitigation.
- An available safe fix is skipped without justification.
- Its validation value does not justify its security debt.
- The exception cannot be time-bounded.
- Its exposure violates the accepted security model.

HOLD is a valid result. Do not suppress findings or widen access merely
to pass validation.

Runtime windows and spending follow ADR-0013. Revisit the scope when
workload maintenance displaces platform work, exceptions accumulate,
shared pipelines need unjustified special cases, costs approach review
thresholds, or upstream changes make maintenance impractical.

This decision defines scope and evidence requirements. It does not
claim that the full fleet is deployed, validated or production-ready.
