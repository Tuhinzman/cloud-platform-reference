# ADR-0017: Validate the full delivery-to-runtime path

Status: Accepted (2026-09-18); revised 2026-10-21, decision unchanged.

Supersedes ADR-0016's scope boundary and stopping condition 5 only for
the justified project-built inventory. Conditions 1 to 4 remain in force.
Outside that inventory, ADR-0016's scope and admission rules still apply.

## Decision

Attempt the complete platform delivery-to-runtime path using the justified
project-built inventory: 17 components when this decision was accepted.

The platform remains the product. The workload demonstrates shared
delivery, security admission, GitOps, runtime behavior and observability.

ADR-0016 bounded scope on the premise that no runtime window was
authorized. The owner's end-to-end objective requires one, and at full
fleet the shared delivery model and the security policy become falsifiable
across ten language ecosystems instead of four. The external request path,
the largest new capability, needs the frontend and the proxy rather than
fleet breadth; it is included because it is the objective's centre.

Keep four scopes separate:

- Delivery target: every justified project-built component receives the
  applicable shared delivery stages.
- Security-admitted fleet: digests admitted under the existing security rules.
- Runtime-admitted fleet: admitted components technically able to run,
  together with the non-project-built dependencies they require.
- Final result: an evidence-backed classification for every component
  in the project-built inventory.

Service count is not the success criterion. A HOLD is a valid component
result, and the security gate must not change to increase the admitted fleet.

## Component results

Each inventory component receives exactly one final classification:

| Result | Meaning |
|---|---|
| FULL-CHAIN-VALIDATED | Every applicable component-level stage below has retained evidence. |
| SECURITY-HOLD | Its digest failed security admission and no admissible exception exists. |
| TECHNICAL-HOLD | A measured technical condition blocked an applicable stage. |
| NOT-DEPLOYED-BY-DECISION | An explicit recorded decision excluded it from runtime, with the reason stated. |

FULL-CHAIN-VALIDATED requires:

- Shared delivery stages completed: applicable static checks, build,
  available tests, container health validation, two-pass scanning, SBOM
  and a CI-native evidence bundle. Service-local pipeline logic needs
  written justification.
- Applicable security admission satisfied, with any permitted exception
  disclosed under the governing security ADR.
- Artifact published, immutable digest recorded and independently read
  back from the registry.
- GitOps desired state references that exact digest, and reconciliation
  onto the cluster was observed.
- The component reached the health or readiness state declared before
  the runtime window.
- Telemetry attribution demonstrated to the depth required for that
  component. Coverage need not be identical across languages.

Missing upstream tests or unavailable checks must be recorded as such,
not reported as passes.

TECHNICAL-HOLD requires the exact measured cause, blocked stage and evidence
reference. Identify whether the cause belongs to the component, platform
tooling or upstream chart. Suspicion alone is insufficient.

A deliberate exclusion must not disguise a security or technical failure.

The load generator and bundled workload observability stack remain outside
this inventory. They receive no classification and are excluded from counts.

## Platform-level validation

Record these outcomes separately from component classifications:

- A real external request through Route 53, TLS and ingress to the workload.
- OpenTelemetry collection, metrics, logs, traces and useful dashboards.
- Alerting, a controlled failure and recovery.
- Retained evidence, runtime teardown and orphan verification.

A component's FULL-CHAIN-VALIDATED result does not prove these outcomes.
Likewise, a successful external request does not prove every component's
delivery chain.

Where the runtime includes the durable datastore, ADR-0011's managed backup
and data-restore exercise remain required. Application fault recovery
does not substitute for restoring data.

## Controls and limits

Every runtime image must be project-built and published through the shared
pipeline, or digest-pinned, mirrored and scanned before the window opens.
This includes sidecars and init containers.

An image that cannot meet those controls blocks its dependent component,
except where the later, narrowly defined rules in ADR-0019 or ADR-0020 apply.
Those records do not weaken security admission. A block is recorded, never
waived.

Acceptance sets the objective. Implementation, AWS changes, publication,
runtime windows and spending still require owner authorization under the
existing model. Check capacity and cost before opening a window.

ADR-0016's fleet-scale limitations remain until runtime evidence retires
them, only to the extent measured. Earlier records retain their historical
meaning. This decision creates no completion or production-readiness claim.

Revisit the programme when the first newly implemented language tier, or
later measured tier work, shows delivery effort or security debt materially
above this record's basis, shared templates cannot support required
components without unjustified special cases, too few admitted components
remain to validate fleet behavior, costs reach ADR-0013's review threshold,
required images cannot meet the applicable controls, or upstream changes
invalidate the inventory.
