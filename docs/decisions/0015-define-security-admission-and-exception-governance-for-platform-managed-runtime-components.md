# ADR-0015: Define security admission and exception governance for platform-managed runtime components

## Status

Accepted (2026-09-08)

Supersedes nothing. This record is additive and edits no Accepted decision.

## Context

The platform runs two kinds of container image. The first is application
change: services this project builds, or upstream workload services it
deploys as part of the reference workload. ADR-0009 governs that path end to
end, and its security gate is explicit — Trivy, blocking on fixable HIGH and
CRITICAL findings, with every scanning exception carrying a written
justification and an expiry. ADR-0014 extends the same threshold to justified
upstream workload components.

The second kind is the class this record governs: non-workload runtime
components that the platform operates in order to provide platform
capabilities. They are not application change. They are infrastructure the
platform runs in order to be a platform, and their pinning authority sits
with the runtime and observability records rather than the delivery records.

No Accepted record assigns security admission for that second class. ADR-0009
is scoped by its own opening to how application change moves. ADR-0014's
fleet definition excludes the platform observability stack. ADR-0010, which
owns the observability architecture, says nothing about image scanning,
vulnerability thresholds, or exceptions. ADR-0006 delegates the exact add-on
list as an implementation decision and nothing further. ADR-0013 places a
blocking consequence for an unresolved fixable high or critical finding at
Production Validation, inside a paragraph about maintenance and upgrade
ownership.

The gap was found by measurement rather than by reading. Applying the
Accepted ADR-0009 gate flags to platform components the implementation had
already selected produced blocking results across the whole set, and a
bounded forward search over published chart versions found no version that
cleared the gate. Implementation measurement therefore exposed a
security-governance responsibility gap that existing Accepted records and
requirement ownership do not explicitly assign. That measurement establishes
that the question is real and cannot be deferred. It does not establish which
answer is correct, and this record is deliberately not written to reach a
particular outcome.

Two properties of the problem shape the decision. Components in this class
are ephemeral where they are deployed with an environment: ADR-0010 makes the
observability stack part of the environment definition, created with the
environment and destroyed with it, so exposure is bounded by an approved
window rather than continuous. And vulnerability evidence is point-in-time: a
gate result describes the vulnerability data of the day it ran, so an
admission decision is a statement about a moment, not a durable property of
an artifact.

One asymmetry matters more than it first appears. The gate fires on findings
the scanner reports as fixable, meaning a fixed version of the package
exists. For a component this project builds, that is actionable — rebuild.
For a component published by someone else, a fix can exist in the package
while no image carrying it has been published, so "fixable" can mean fixable
by a third party on a schedule this project neither sets nor sees. That
distinction is not a reason to admit anything. It is a reason the policy has
to be explicit about what the project is expected to do before it may even
consider an exception.

## Decision

Adopt an environment-graded security-admission policy for platform-managed
runtime components.

### Governed class

This record governs **non-workload runtime components that the platform
operates in order to provide platform capabilities**. Examples of that class
include observability components, ingress components, certificate
components, and controller-class components.

It covers initial admission, upgrade and re-admission, vulnerability
freshness, bounded exceptions, and environment-role consequences.

It does not govern owner-built workload services, justified upstream workload
exceptions, application CI/CD security policy, any individual vulnerability
identifier, or any individual current image. Those remain with ADR-0009 and
ADR-0014.

The class definition above is authoritative, and membership follows from it
rather than from a list. If a future datastore, cache, message broker or
similar dependency satisfies that definition, this record governs its
platform-image security admission. If its ownership and deployment model
instead places it inside a workload or application class, the governing
workload record applies. No component receives a standing exemption from this
record because its deployment model has not yet been chosen.

### Admission

**Default.** Any fixable HIGH or CRITICAL finding against a component in the
governed class places that component on HOLD. HOLD is a normal and acceptable
outcome, not a failure of process.

**Development and validation roles.** A component on HOLD may be admitted
only through an explicit, owner-approved, per-digest, window-bounded security
exception satisfying the contract below. Admission is never automatic and
never implied.

**Production Validation.** No unresolved fixable HIGH or CRITICAL finding is
admissible. There is no exception path at this role.

### Exception authority is window-bound

The bounded exception path exists only for a component running inside an
explicitly authorized, bounded Development or Validation runtime window. The
exception's entire exposure argument rests on that boundary: the component
exists for a known, approved, finite period and is destroyed with its
environment.

A persistent or long-lived component in the governed class cannot use this
exception mechanism. Such a component that fails the gate is HOLD, and this
record supplies no path to admit it.

If platform lifecycle architecture later introduces long-lived components
inside this governed class, that is a revisit trigger, because the exposure
and expiry model this policy depends on no longer applies to them.

Production Validation admits no exception regardless of lifecycle.

### The gate definition is fixed

The gate definition is fixed for comparable admission evidence. It does not
change in either direction in order to obtain a different result, and a gate
that has been altered produces evidence that is not comparable with evidence
produced before the alteration.

Fixed for this purpose: Trivy as the scanning platform; HIGH and CRITICAL as
the selected severities; the unfixed-finding filter applied so that only
fixable findings block; a non-zero exit on blocking findings; no ignore file;
and no scanner substitution.

A future deliberate change to the gate definition requires its own reviewed
decision, stating what changes and why, and re-establishing the comparison
basis. Such a change can never be made inside an exception, as part of an
exception, or as a consequence of one. An exception is a recorded decision to
admit a measured artifact; it is never a change to the measurement.

### Mandatory exception contract

Every field below is required. An exception missing any field is incomplete
and cannot be approved.

1. Affected component.
2. Exact linux/amd64 immutable digest the exception binds.
3. Identifier for each blocking finding.
4. Affected package for each blocking finding.
5. Severity for each blocking finding.
6. Fixed-version availability for each blocking finding.
7. Exploitability in this exact context.
8. Runtime exposure.
9. Necessity, established under the test below.
10. Compensating controls.
11. Justification.
12. Owner.
13. Environment role.
14. Approval evidence.
15. Expiry.
16. Removal trigger.
17. Vulnerability database metadata current at approval.
18. Bounded currency-search evidence.
19. Lowest-obtainable-security-debt evidence.

The following rules bind every exception:

1. An exception is per-component, per-digest, per-window.
2. It is never inherited by another digest or another window.
3. It expires at the end of the authorized runtime window.
4. A newly obtainable fixed artifact is a removal trigger, not an expiry
   event.
5. Every new window requires fresh vulnerability evaluation. A prior grant is
   never evidence for a later window.
6. No scanner ignore file.
7. No combined-ignore entry.
8. No severity reduction.
9. No removal of the unfixed-finding filter.
10. No scanner substitution to obtain a pass.
11. No automatic exception.
12. No blanket exception.
13. HOLD remains an honest and acceptable outcome.
14. Exception disclosure is mandatory for any public claim or evidence chain
    whose conclusion materially depends on the excepted component. Such a
    claim carries the qualifier and is never described as clean,
    vulnerability-free, or security-gate-passed. A claim whose conclusion
    does not depend on the excepted component does not inherit the qualifier
    merely because the same runtime window contained an exception: teardown
    and orphan-scan evidence, for example, stands on its own. The test is
    dependence, not co-occurrence, and it is never used to avoid disclosing a
    dependent claim.

### Necessity test

Necessity is established only by naming the specific Accepted architecture
obligation or frozen validation criterion that cannot be exercised without
this component. The named obligation or criterion must be identifiable in the
record that carries it.

If no such obligation or criterion can be named, necessity is not established
and the exception cannot be granted.

Generic assertions do not establish necessity. Wording such as "useful for
validation", "needed for the project", or "required for completeness" is
insufficient on its own and does not satisfy this field.

### Bounded currency test

Before an exception may be considered, inspect the same upstream image
repository for currently published identities newer than the pinned identity
that are compatible with the pinned chart's supported image override
mechanism.

The test deliberately does not require internet-wide research into
alternative images, self-building third-party platform components, chart
forks, or arbitrary alternative distributions. Its purpose is to establish
that the project has not simply failed to take an available upgrade, not to
make the project responsible for the upstream ecosystem.

The search produces positive recorded evidence whether or not it finds
anything. The record captures the repository inspected, the pinned identity,
the time of the search, the search boundary applied, the identities
evaluated, and the result.

Finding zero compatible newer identities is a valid measured result. It is
not equivalent to the search not having been performed, and the two are never
recorded in the same way. Where the pinned identity is the only compatible
obtainable candidate, it is trivially the lowest-debt candidate, and fields
18 and 19 are still present and still evidenced.

### Lowest obtainable security debt

Among compatible obtainable identities, security debt is ordered
deterministically:

1. Fewer blocking CRITICAL findings is lower security debt.
2. If blocking CRITICAL counts are equal, fewer blocking HIGH findings is
   lower security debt.
3. If both counts are equal, this comparison provides no preference.

An exception normally binds the lowest-debt obtainable compatible identity.
Binding a higher-debt identity requires separate written justification
recorded with the exception.

Lower security debt does not mean an identity is admissible. This ordering
only selects the candidate against which exception evaluation occurs.

## Considered Options

| Option | Assessment | Outcome |
|---|---|---|
| **A. Strict universal gate.** Any fixable HIGH or CRITICAL finding holds the component in every environment role, with no exception path. | The strongest option on integrity and the only one that cannot be gamed. Its cost is that it delegates the platform's ability to run its own infrastructure to third-party release cadence, and it creates a quiet incentive to scan less often, which is worse than a governed exception. Chosen deliberately, it is a defensible posture; it must be chosen knowing it can prevent the platform from being exercised at all. | Rejected |
| **B. Risk-based bounded admission without an environment gradient.** Findings hold by default; a documented, expiring, approved exception may admit a component under defined conditions, uniformly across roles. | Reuses the exception shape ADR-0009 already establishes, but discards the most relevant architectural fact available: ADR-0010 makes the stack ephemeral and environment-scoped. A uniform policy must be calibrated either too strictly for a bounded development window or too loosely for the production-like role, and under delivery pressure uniform policies drift toward the looser calibration. | Rejected |
| **C. Environment-graded admission.** Findings hold by default; development and validation roles may admit through a bounded exception; Production Validation admits none. | Matches the shape the Accepted records already imply. ADR-0013 places its blocking consequence at Production Validation, ADR-0004 declares the role order, and ADR-0010 scopes the stack to an ephemeral environment. It preserves absolute strictness where the project's public claims are strongest. Its real weakness is decay: graded policies fail when development exceptions quietly become permanent and when role-qualified evidence is later cited without its qualifier. The expiry, removal trigger and disclosure rules above are load-bearing for that reason. | **Selected** |
| **D. Upstream-currency-bounded admission.** Admit where the project is at the newest published upstream artifact and no artifact carrying the fix is obtainable. | Identifies a genuine distinction the gate collapses, and it is grounded in ADR-0009's principle that findings without an available fix are reported rather than hidden. As a standalone policy it is unsound: it requires continuously re-proving a negative, the answer changes silently the moment a publisher ships a rebuild, and it is the easiest of the four to abuse. Adopted as a mandatory precondition inside option C rather than as a policy in its own right. | Rejected as a standalone policy; adopted as a condition |

## Consequences

Components within the governed class now have an explicit admission standard,
and membership follows from the class definition rather than from an
enumeration that would need extending each time the platform grows.

**The Production Validation rule can block Production Validation and
therefore final project completion.** If no acceptable third-party artifact
exists — that is, if publishers have not released an artifact that clears the
gate — Production Validation cannot proceed, and no exception path exists to
relieve it. This is an accepted security trade-off. It is recorded here so
that it is neither hidden nor quietly worked around if it occurs, and so that
the choice was made before the pressure of encountering it. Nothing in this
project's method promises that an accepted architecture is always immediately
runnable, and this record does not create such a promise.

Development and validation windows carry real residual risk when an exception
is granted. That risk is bounded by the window and by the ephemeral lifecycle
ADR-0010 already defines, but it is not eliminated, and evidence produced in
such a window carries a qualifier that travels with every claim depending on
the excepted component.

Tying the exception path to a bounded authorized window means a long-lived
component in this class has no exception route at all. That is a deliberate
asymmetry: the exposure argument that justifies admission does not exist
without the boundary, so neither does the admission.

Governance cost is recurring rather than one-time. Every exception is
evaluated fresh for every window, which is the mechanism that prevents an
exception from becoming permanent by inattention.

This record also supplies the authority under which a platform Collector, or
any other component in the governed class, may be evaluated for exception if
it fails a later point-in-time freshness scan, including a component that
passes today. It pre-authorizes nothing. A component that passes now and
fails later is held, and any exception is evaluated on its own facts at that
time.

**Relationships.** This record is additive. It supersedes nothing, edits
nothing, and contradicts no Accepted record.

ADR-0009 is unchanged and continues to govern application delivery artifacts.
This record does not extend ADR-0009's scope; it establishes separate
authority for a class that record does not address.

ADR-0010 is unchanged and continues to govern observability architecture.

ADR-0013 is unchanged. The Production Validation strictness adopted here is
compatible with its existing consequence for an unresolved fixable high or
critical finding. This record governs the class defined above going forward
and takes no position on how that record's maintenance and upgrade wording
should be read for anything else, or on how it should have been read before
this record existed.

ADR-0014 is unchanged.

## Deferred Decisions

The concrete format and storage location of an approved exception record is
an implementation decision and is not fixed here.

Image signing and build attestation for components in the governed class
remain deferred, consistent with ADR-0009's treatment of the same question
for application artifacts. Until they are available, digest identity and the
recorded approval chain carry the provenance.

## Revisit Triggers

- The same component and digest requires exceptions across multiple
  consecutive windows. The condition is then no longer safely treated as
  transient, and the policy trade-off is reviewed. This trigger causes
  review; it does not by itself admit or reject the component.
- Platform lifecycle architecture introduces long-lived components inside
  the governed class, so that the bounded-window exposure and expiry model
  this policy depends on no longer applies to them.
- A measured incident involves a component admitted under exception.
- Exception governance materially prevents platform validation rather than
  bounding it.
- Platform image provenance or signing becomes available and changes the
  trust basis on which admission rests.
- Production Validation is repeatedly blocked by third-party security
  currency, indicating the trade-off recorded in Consequences is costing more
  than it protects.
