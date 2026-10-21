# ADR-0016: Bound workload scope by validation value

Status: Accepted (2026-09-18); revised 2026-10-21, decision unchanged.

Replaces only ADR-0014's full-fleet implementation target.
ADR-0017 later supersedes this scope boundary and stopping condition 5
for the justified project-built inventory. Conditions 1 to 4 remain in force.

## Decision

The platform is the product. Add workload components when they help
demonstrate a platform capability that the existing implementation
has not already proved.

At acceptance, measurement rather than estimate drove this: eight
components already delivered through the shared templates with no
service-local pipeline logic, the nine remaining components all needed new
language tiers (six in total), and three of the four breadth properties
ADR-0014 wanted required a runtime window that was not authorized. The
remaining work would have repeated an already-demonstrated property at the
cost of six templates and a wider exception surface.

Do not set a replacement service-count target. Scope depends on the
evidence needed, rather than the number of services or languages.

This boundary continues to apply outside ADR-0017's justified project-built
inventory. Within that inventory, follow ADR-0017's full-fleet programme;
a separate new-capability justification is not required for every component.

## Stopping conditions

1. Shared delivery is demonstrated across at least two language tiers
   and one configured component without an application language tier,
   with zero service-local pipeline logic.

2. Each project-built class in ADR-0014 has at least one verified
   CI-native evidence path: an application service and a configured
   component. Each path must have a DIRECT published-digest binding:
   the SHA-256 of retained registry manifest bytes equals the published
   digest.

3. ADR-0012's minimum evidence set remains the basis for judging
   requirement satisfaction.

4. Fleet-scale reconciliation, telemetry attribution under fleet load
   and fleet teardown remain declared limitations until evidence proves
   them. Testing them requires an owner-authorized runtime window
   justified by its engineering value. Expanding scope does not itself
   authorize that window.

5. Before adding a component, name the unproven platform capability,
   obtain an explicit owner decision and record it in the project's
   operational state record or an architectural record. A session report,
   implementation plan or agent recommendation is insufficient. ADR-0017
   replaces this admission test only for its justified project-built
   inventory.

Meeting these conditions does not establish completion of ADR-0017's
later full-fleet programme.

## What stays unchanged

ADR-0012 and the remaining decisions in ADR-0014 continue to apply,
including component classification, evidence requirements, shared
pipelines, scan-before-enforcement ordering, security exceptions,
upstream attribution and reproducibility.

The load generator remains excluded by default. The workload's bundled
observability stack stays excluded. Runtime authorization and cost
controls remain in force.

This decision does not remove or reclassify inventory components.
It does not turn incomplete work into completed work or change what
earlier evidence proves. Report build, publication and runtime validation
only where supported by evidence.

Revisit the boundary when a new platform capability needs additional
components, an independently justified runtime window makes broader
validation useful, required language support breaks the shared pipeline
model, provenance capabilities change, or upstream changes make the
inventory inaccurate.
