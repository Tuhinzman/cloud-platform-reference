# Requirements Baseline

## Purpose

This baseline turns the target capabilities of the [Platform Capability Model](capability-model.md) into measurable obligations. Each requirement states a condition the platform must satisfy and the observable proof that will count as satisfying it. Architecture and implementation will be judged against these conditions.

Requirement status is not carried in this file. Each requirement is validated with captured evidence as the platform is built, and the current discharged, partially proven and not-yet-proven set is stated in the repository README.

## How to Read This Baseline

Requirements are numbered `REQ-001` onward, sequentially, with no meaning attached to the order beyond grouping by domain. Every requirement carries the same seven fields: an ID, a title, a business reason, the capability IDs it serves, the requirement itself, acceptance criteria, and its architecture impact.

The `Capability` field references exact IDs from the capability model; the Coverage Summary at the end is the single owner of capability-to-requirement traceability. Acceptance criteria describe the proof that will count, not the steps that produce it. All wording is target-state: "must" marks an obligation, not a status. Whether a given obligation is met today is stated in the README, not here.

## Platform Foundation

### REQ-001

**Title:** Documented platform definition and clean establishment

**Business Reason:** A platform only its author can assemble cannot be reviewed, reproduced, or trusted. The repository has to carry everything needed to stand the platform up.

**Capability:** CAP-PF-01, CAP-INF-04

**Requirement:** The repository must document the platform's structure, conventions, bootstrap prerequisites, and the ordered procedure for establishing the platform in a clean target cloud environment, and that procedure must be sufficient to complete the establishment without undocumented steps.

**Acceptance Criteria:**

- An engineer holding only the repository and the documented prerequisites can complete platform establishment by following the written procedure, without undocumented manual steps.
- Every bootstrap prerequisite is listed with its purpose and why it must exist before the versioned definitions take over.
- One execution of the procedure in a clean target cloud environment is captured as evidence.

**Architecture Impact:** Bootstrap ordering and state management; the boundary between what must exist first and what the versioned definitions provision.

### REQ-002

**Title:** Environment lifecycle and configuration separation

**Business Reason:** Validation needs isolated environments that come and go cheaply. Environments built from shared definitions stay honest copies of each other; hand-tuned ones drift apart.

**Capability:** CAP-PF-02, CAP-PF-03

**Requirement:** The platform must provide isolated environments with a declared purpose and lifecycle, including short-lived validation environments, and environment-specific configuration must stay separate from shared platform definitions so the same definitions serve every environment.

**Acceptance Criteria:**

- A short-lived validation environment is created and later removed following its documented lifecycle.
- A value that differs per environment is changed without editing shared platform definitions.
- At least two environments are produced from the same shared definitions, differing only in their environment-specific configuration.

**Architecture Impact:** Environment isolation boundaries and configuration layering.

## Infrastructure

### REQ-003

**Title:** Infrastructure from version-controlled definitions

**Business Reason:** If the console is the only record of what exists, nobody can rebuild the platform or check a change before it lands.

**Capability:** CAP-INF-01

**Requirement:** All platform infrastructure beyond the documented bootstrap prerequisites must be provisioned from definitions held in version control, and those definitions must remain the authoritative description of intended infrastructure state.

**Acceptance Criteria:**

- Each provisioned platform resource beyond the documented bootstrap prerequisites traces to a definition in the repository.
- A change made only in the definitions, once applied, is visible in the running infrastructure.

**Architecture Impact:** Organization of infrastructure definitions and their state storage; the bootstrap boundary from REQ-001.

### REQ-004

**Title:** Controlled change, drift correction, and clean teardown

**Business Reason:** Uncontrolled changes and abandoned resources are how small platforms rot and quietly accumulate cost. Change control, drift handling, and teardown are the counterweights.

**Capability:** CAP-INF-02, CAP-INF-03

**Requirement:** Infrastructure changes must pass approval and validation before automation applies them; divergence between declared and actual state must be detectable and correctable through the declared workflow; and any environment or set of billable resources must be removable through a documented teardown procedure.

**Acceptance Criteria:**

- A required validation failure prevents the declared change from progressing.
- A deliberately introduced divergence between declared and actual state is detected and corrected through the declared workflow.
- Billable resources of an environment are absent after its documented teardown procedure completes.

**Architecture Impact:** Change and approval workflow, state comparison, teardown ordering across dependent resources.

## Identity & Security

### REQ-005

**Title:** Central human authentication and accountable access

**Business Reason:** Local accounts linger after people should have lost access, and nobody can audit them. A central identity source fixes both.

**Capability:** CAP-IS-01, CAP-IS-02

**Requirement:** Human access to the platform must authenticate through a central federated identity source, be granted to identities based on need, and leave security-relevant actions attributable to the identity that performed them.

**Acceptance Criteria:**

- Access for a person is granted and revoked at the central identity source, each grant is recorded, and revocation removes platform access without changes to individual systems.
- A security-relevant action can be attributed to the identity that performed it from recorded logs.
- Routine human access uses no per-system local accounts; any exception is documented.

**Architecture Impact:** Identity federation boundary, role and permission model, placement of audit records.

### REQ-006

**Title:** Workload identity over static credentials

**Business Reason:** Long-lived static credentials leak and outlive their purpose, and on a solo-operated project nobody is watching for either. The standing secret should not exist where the stack can avoid it.

**Capability:** CAP-IS-03

**Requirement:** Workloads must authenticate to platform and external services using identities rather than long-lived static credentials where practical and supported by the selected runtime and external services, and every remaining long-lived static credential must carry a documented justification.

**Acceptance Criteria:**

- Workload-to-service authentication uses identity-based or short-lived credentials where practical and supported by the selected runtime and external services.
- Every remaining long-lived static workload credential is listed with a documented justification.

**Architecture Impact:** Runtime identity integration and trust relationships with external services.

### REQ-007

**Title:** Secret handling, controlled privilege, and artifact provenance

**Business Reason:** Embedded secrets, unbounded admin access, and untraceable artifacts are the three usual ways a small platform loses the ability to say who can do what and what is actually running.

**Capability:** CAP-IS-04, CAP-IS-05, CAP-IS-06, CAP-SD-01

**Requirement:** Secrets must be retrieved at runtime from an external secret source appropriate to the implementation and never embedded in code, images, or repositories. Permanent privileged access must be minimized, with elevated access explicitly granted and scoped, and preferably time-bound. Artifacts running on the platform must be traceable to the source change and build that produced them.

**Acceptance Criteria:**

- No secret value appears in the repository, build artifacts, or image contents; workloads obtain secrets at runtime from the external secret source.
- Identities holding permanent privileged access are documented and justified, and elevated grants are recorded with their scope.
- The running artifact can be traced to its source revision and build record.

**Architecture Impact:** Secret source integration, privilege boundaries, and build metadata propagation into deployed artifacts.

## Networking

### REQ-008

**Title:** Controlled connectivity, naming, and routing

**Business Reason:** Entry points, naming, and routing need to be deliberate from the start; release control and security both depend on them, and network behavior is the hardest thing to make deliberate after the fact.

**Capability:** CAP-NET-01, CAP-NET-02, CAP-NET-03

**Requirement:** Traffic must enter and leave the platform only through defined, restrictable points; platform components and workloads must reach their dependencies through stable names; and requests must be routable to a chosen workload version in support of controlled release.

**Acceptance Criteria:**

- Externally reachable entry points are enumerated, and a connection attempted outside them fails.
- An outbound connection attempted to a destination outside the permitted egress rules fails.
- A workload still reaches a dependency by its stable name after the dependency's instances are replaced.
- During a release, requests are directed to a chosen workload version, and that direction is observable.

**Architecture Impact:** Ingress and egress boundaries, name resolution, and the routing control points release strategies will rely on.

## Application Runtime

### REQ-009

**Title:** Run and configure container-based workloads

**Business Reason:** The platform's value starts with running its workloads without hand-placed, hand-configured deployments; one artifact that runs everywhere keeps environments comparable.

**Capability:** CAP-RT-01

**Requirement:** The platform must run workloads packaged as containers, scheduled onto available capacity without manual placement, with environment-specific configuration supplied at runtime rather than built into the artifact.

**Acceptance Criteria:**

- A workload deploys from its container artifact without a manual placement decision.
- The same artifact runs in two environments with different configuration, without being rebuilt.

**Architecture Impact:** Scheduling model and the configuration injection path from REQ-002's separation.

### REQ-010

**Title:** Health evaluation and capacity adjustment

**Business Reason:** A platform that needs a person watching it to stay up is an application server, not a platform. On this project the failure handling cannot depend on an operator being awake.

**Capability:** CAP-RT-02, CAP-RT-03

**Requirement:** Workload health must be continuously evaluated, with instances that fail evaluation replaced without operator intervention, and workload capacity must be adjustable through the declared workflow and able to follow demand where the workload justifies it.

**Acceptance Criteria:**

- An instance made to fail its health evaluation is replaced without operator action, and the replacement is observable.
- A deliberate capacity change through the declared workflow results in the corresponding number of running instances.
- Where demand-following is enabled for a workload, a demand change results in an observed capacity change; where it is not enabled, the reason is documented.

**Architecture Impact:** Health evaluation design, replacement behavior, and scaling triggers and limits.

## Software Delivery

### REQ-011

**Title:** Source-controlled build and validation

**Business Reason:** If a change can reach the platform without passing through version control and validation, every other delivery control is decorative.

**Capability:** CAP-SD-01

**Requirement:** Every deployable change must originate in version control and pass an automated build and validation workflow that produces a versioned, retained artifact before the change can be deployed.

**Acceptance Criteria:**

- A change that fails automated validation produces no deployable artifact.
- Each deployable artifact carries an identifier linking it to the source revision and build that produced it.
- A previously built artifact is retrieved and redeployed, and the retention configuration matches the documented retention period.

**Architecture Impact:** Build and validation workflow, artifact storage, and the versioning scheme provenance depends on.

### REQ-012

**Title:** Controlled promotion with production approval

**Business Reason:** Environment promotion only means something if nothing skips it, and production carries enough consequence to demand a deliberate human decision.

**Capability:** CAP-SD-02

**Requirement:** Deployments must move through environments in a declared order, and promotion to production must require an explicit, recorded approval. For this reference project, production means the final production-like validation stage rather than a permanently hosted service.

**Acceptance Criteria:**

- A deployment does not reach production without the recorded approval step.
- The promotion history of an artifact, including environments, times, and the approving identity, is reconstructible from records.

**Architecture Impact:** Promotion workflow, approval gate placement, and the stage sequence.

### REQ-013

**Title:** Progressive release, recovery, and guided onboarding

**Business Reason:** Releases fail; what matters is whether a failing release can be stopped and undone quickly. Guided onboarding keeps the delivery workflow reusable instead of bespoke.

**Capability:** CAP-SD-03, CAP-SD-04, CAP-NET-03

**Requirement:** A release must roll out progressively, be haltable mid-rollout, and be reversible to the last known-good state through a documented path. A new application must be able to join the platform through a documented, guided onboarding path without bespoke platform work.

**Acceptance Criteria:**

- A release halted mid-rollout leaves the prior version serving requests.
- A failed release is reversed to the last known-good state by following the documented path.
- The platform's first workload arrives through the documented onboarding path.

**Architecture Impact:** Release mechanics, their integration with routing from REQ-008, and the shape of the onboarding path.

## Observability

### REQ-014

**Title:** Telemetry collection and inspection

**Business Reason:** Operating and debugging start from being able to see what the platform is doing, and in this project the validation evidence itself will come from these signals.

**Capability:** CAP-OBS-01, CAP-OBS-02

**Requirement:** Metrics, logs, and traces must be collected from the platform and its workloads and be inspectable through operational views covering current state and a documented retention window of history.

**Acceptance Criteria:**

- For a running workload, an engineer can inspect its metrics, logs, and traces from the operational views.
- The deployed version and current health state of a workload are identifiable from the views.
- An event that has already ended can still be examined within the documented retention window.

**Architecture Impact:** Telemetry collection paths, storage and retention, and view organization.

### REQ-015

**Title:** Correlation, detection, and actionable alerting

**Business Reason:** When signals do not connect across the platform-workload boundary, every incident turns into archaeology. Alerts without context train people to ignore them.

**Capability:** CAP-OBS-02, CAP-OBS-03

**Requirement:** Signals from platform and workloads must be correlatable so one problem can be followed across that boundary, and defined conditions must raise alerts that reach an engineer with enough context to act on.

**Acceptance Criteria:**

- A deliberately induced workload fault is followed from its alert to the underlying platform and workload signals.
- Each defined alert condition states what it means and its first diagnostic step.
- An alert for a defined condition reaches an engineer through the declared channel.

**Architecture Impact:** Correlation keys across signal types, alert definitions, and alert routing.

## Resilience

### REQ-016

**Title:** Backup, restore, and exercised recovery

**Business Reason:** A recovery procedure that has never been run is a hypothesis. The platform needs one demonstrated, repeatable answer to losing something that matters.

**Capability:** CAP-RES-01, CAP-RES-02

**Requirement:** State designated as worth keeping must be backed up and restorable, and at least one defined, meaningful failure scenario must have a documented recovery procedure that has been exercised deliberately.

**Acceptance Criteria:**

- The designated state set is documented, and its documented restore procedure succeeds for that state.
- The chosen failure scenario's recovery procedure, executed as written, returns the affected part of the platform to service.
- The recovery exercise record captures what failed, what was done, and how long recovery took.

**Architecture Impact:** Backup scope and placement, and the recovery sequence for the chosen scenario.

## Platform Operations

### REQ-017

**Title:** Documented operating and troubleshooting procedures

**Business Reason:** Operability by someone who did not build it is the difference between a platform and the author's memory. It is also the standard the validation evidence will be judged against.

**Capability:** CAP-OPS-01, CAP-OBS-02, CAP-OBS-03

**Requirement:** Routine operation and troubleshooting must follow documented procedures that name the operational views and signals to use, sufficient for an engineer who did not build the platform to operate it.

**Acceptance Criteria:**

- Each routine operating task in the documented task list has a written procedure, and following it completes the task without undocumented knowledge.
- For at least one exercised scenario, a troubleshooting procedure leads from symptom to the relevant signals to a diagnosis.

**Architecture Impact:** Runbook organization and its linkage to the telemetry architecture.

### REQ-018

**Title:** Controlled maintenance and upgrades

**Business Reason:** Maintenance is where controlled platforms drift into uncontrolled ones, one urgent manual fix at a time.

**Capability:** CAP-OPS-02, CAP-INF-02

**Requirement:** Platform components must be maintained and upgraded through the same approved, validated change workflow that governs infrastructure, and maintenance actions must be reconstructible from records.

**Acceptance Criteria:**

- A component upgrade passes approval and validation before automation applies it.
- What changed and when is reconstructible from records for each maintenance action.

**Architecture Impact:** Upgrade sequencing and component version tracking.

## Cost Management

### REQ-019

**Title:** Cost visibility and billable-resource lifecycle

**Business Reason:** Cost is an engineering constraint of this project; that only holds if spend is visible, attributable, and every billable resource has a known way to stop costing money.

**Capability:** CAP-COST-01, CAP-COST-02, CAP-INF-03

**Requirement:** Cloud spend must be inspectable and attributable to the environments and components that cause it, and comparable against a documented expected level. Every billable resource must have a documented purpose and a teardown path that removes it.

**Acceptance Criteria:**

- Current spend can be broken down by environment and component from the cost views.
- A recorded comparison of actual spend against the documented expected level exists for at least one review period.
- Every billable resource carries a documented purpose and names its teardown path, validated under REQ-004.

**Architecture Impact:** Cost attribution conventions, resource lifecycle tracking, and teardown coverage from REQ-004.

## Coverage Summary

| Requirement ID | Requirement Title | Capability IDs |
|---|---|---|
| REQ-001 | Documented platform definition and clean establishment | CAP-PF-01, CAP-INF-04 |
| REQ-002 | Environment lifecycle and configuration separation | CAP-PF-02, CAP-PF-03 |
| REQ-003 | Infrastructure from version-controlled definitions | CAP-INF-01 |
| REQ-004 | Controlled change, drift correction, and clean teardown | CAP-INF-02, CAP-INF-03 |
| REQ-005 | Central human authentication and accountable access | CAP-IS-01, CAP-IS-02 |
| REQ-006 | Workload identity over static credentials | CAP-IS-03 |
| REQ-007 | Secret handling, controlled privilege, and artifact provenance | CAP-IS-04, CAP-IS-05, CAP-IS-06, CAP-SD-01 |
| REQ-008 | Controlled connectivity, naming, and routing | CAP-NET-01, CAP-NET-02, CAP-NET-03 |
| REQ-009 | Run and configure container-based workloads | CAP-RT-01 |
| REQ-010 | Health evaluation and capacity adjustment | CAP-RT-02, CAP-RT-03 |
| REQ-011 | Source-controlled build and validation | CAP-SD-01 |
| REQ-012 | Controlled promotion with production approval | CAP-SD-02 |
| REQ-013 | Progressive release, recovery, and guided onboarding | CAP-SD-03, CAP-SD-04, CAP-NET-03 |
| REQ-014 | Telemetry collection and inspection | CAP-OBS-01, CAP-OBS-02 |
| REQ-015 | Correlation, detection, and actionable alerting | CAP-OBS-02, CAP-OBS-03 |
| REQ-016 | Backup, restore, and exercised recovery | CAP-RES-01, CAP-RES-02 |
| REQ-017 | Documented operating and troubleshooting procedures | CAP-OPS-01, CAP-OBS-02, CAP-OBS-03 |
| REQ-018 | Controlled maintenance and upgrades | CAP-OPS-02, CAP-INF-02 |
| REQ-019 | Cost visibility and billable-resource lifecycle | CAP-COST-01, CAP-COST-02, CAP-INF-03 |

## Change Management

The filename stays stable, changes are amended in place, and Git history records how the baseline evolves. Active architecture and implementation work must remain traceable to the current version of this baseline; when a requirement changes, the work that depends on it is re-checked against the new wording.
