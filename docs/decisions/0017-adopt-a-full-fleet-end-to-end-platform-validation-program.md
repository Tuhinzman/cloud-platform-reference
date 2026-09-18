# ADR-0017: Adopt a full-fleet end-to-end platform validation program

## Status

Proposed (2026-09-18)

Supersedes ADR-0016's scope-bounding Decision, that implementation scope
is bounded by demonstrated platform-validation value rather than by fleet
completeness, for the justified project-built inventory only. Outside that
inventory the bounding Decision continues to govern.

Supersedes ADR-0016 stopping condition 5 only as the per-component
admission test for that same inventory. For any component outside it,
condition 5 stands unchanged and still requires a named unproven property,
an explicit owner decision and a record.

**ADR-0016 stopping condition 4 is not superseded and remains in force.**
The three fleet-scale properties it names stay declared limitations until
evidence retires them. Stopping conditions 1, 2 and 3 also remain in
force. Everything else ADR-0016 decided stands, and it keeps its Accepted
status. ADR-0014 and ADR-0012 are unaffected and keep theirs. No accepted
record is edited.

## Context

ADR-0016 bounded the implemented workload on 2026-09-18. Its measurements
were correct and remain correct: nine components are unwired, none of them
falls inside an existing language tier, six new tiers are required, eight
components deliver through shared templates with zero service-local
pipeline logic, and both provenance-eligible component classes carry a
CI-native evidence bundle with a DIRECT published-digest binding.

ADR-0016 reasoned from those measurements to a judgement, and the
judgement rested on one premise stated in its own text: three of the four
breadth properties ADR-0014 wanted are runtime properties, "they require a
cluster, and no runtime window is authorized." On that premise the
remaining work bought one already-demonstrated property at the cost of six
language tiers, and bounding was the better engineering decision.

The premise has changed. The owner has selected a different objective:
demonstrate the platform's complete delivery-to-runtime chain end to end,
from source through shared CI, scanning, SBOM, ECR, immutable digest,
GitOps desired state, Argo CD, EKS, ingress, Route 53, TLS, a real
external request, OpenTelemetry collection, the metric, log and trace
stores, dashboards, alerting, a controlled failure, recovery, retained
evidence and teardown with orphan verification. That objective requires a
runtime window, and it requires the workload that the chain is
demonstrated against.

ADR-0016 anticipated this. Its stopping condition 4 records the three
fleet-scale properties as declared limitations and states that they
"become work only if a future owner-authorized runtime window is justified
on its own engineering value rather than on completing this scope." The
end-to-end chain is such a justification: it is a platform property, not a
fleet count, and it is unreachable today at any fleet size because no
ingress, DNS or certificate implementation exists.

What ADR-0016 did not anticipate is the delivery-breadth half of the same
decision, and stopping condition 5 blocks it. That condition admits a
component only when it validates a property the representative scope has
not already demonstrated, tested per component. Admitting nine components
one at a time under that test would require nine separate property claims,
and for several of them the honest claim is that the component
demonstrates the same mechanism again at a larger scale. This record
answers that question once, for the whole justified project-built surface,
rather than nine times with weaker reasoning each time.

Measured at this record's drafting, against the repositories and the
rendered desired state rather than from estimate:

- 17 justified project-built components: 15 application services across
  10 language tiers, and 2 tier-less configured components.
- 8 wired, of which 5 carry the full chain and 3 reach lint only;
  9 unwired; zero service-local pipeline logic.
- 4 language tiers have a template; 6 are net-new.
- 5 workload ECR repositories and 1 platform mirror; 4 components have
  ever published; 3 carry a project-owned digest in desired state;
  1 carries four-signal runtime validation.
- The rendered fleet is 20 Deployments and 26 containers, declaring
  3350 MiB of memory limits and no CPU requests or limits at all.
- The rendered runtime image surface is larger than the component
  inventory: besides the project-built images it includes one upstream
  exception pinned by tag rather than digest, three infrastructure
  dependencies, and five init-container images of which four are
  `busybox:latest` and one is `busybox` with no tag at all. None of
  these is mirrored into the platform registry today.
- `flagd-ui` is built by this project but runs as a sidecar container
  inside the `flagd` pod. Chart 0.40.10 composes the image reference for
  a component's primary container only, so `flagd-ui` is not reachable
  by the supported override mechanism.

## Decision

**The implementation target is the full justified project-built fleet,
attempted through the platform's shared engineering path, with every final
per-component result explained by evidence.** Attempted is the operative
word. This record sets a surface to put through one delivery model, not a
result to achieve.

**Four scopes, named separately, because conflating them is how a breadth
programme becomes a completeness programme.**

1. **Delivery-fleet target.** Every one of the 17 justified project-built
   components receives the applicable shared delivery chain: static
   validation where its language offers it, build, whatever tests it
   actually has, container health validation, the two-pass scan, SBOM
   generation, artifact publication, digest recording, and a CI-native
   evidence bundle. Each contributes declarative configuration only.
   Service-local pipeline logic still requires written justification
   under ADR-0014, which this record does not relax.

2. **Security-admitted fleet.** The subset of the delivery fleet whose
   built digest passes the ADR-0009 gate that ADR-0014 extends and
   ADR-0015 fixes for the platform-managed class. A component that fails
   is **SECURITY-HOLD**, which ADR-0014 already records as an honest
   outcome and which this record does not convert into a problem to
   solve. The gate is never weakened, narrowed, ignored or substituted
   to enlarge this set.

3. **Runtime-admitted fleet.** The subset of the security-admitted fleet
   that is technically able to complete the runtime stages the programme
   applies to it, together with the non-project-built components the
   selected runtime requires. A component that is not is
   **TECHNICAL-HOLD**, defined below.

4. **Full-fleet result.** Every component in the justified project-built
   inventory carries exactly one terminal classification:
   `FULL-CHAIN-VALIDATED`, `SECURITY-HOLD`, `TECHNICAL-HOLD` or
   `NOT-DEPLOYED-BY-DECISION`. A programme in which some components are
   held is a completed programme, not a failed one. A programme that
   reports every component green without the evidence for it is a failed
   one regardless of the count.

**A per-component result and a programme-level result are different
things, and neither is evidence for the other.** The four classifications
above are per-component. They describe how far one component travelled
through the chain the programme applies to it. The programme's own
outcome, the external request path, alerting, controlled failure and
recovery, teardown and orphan verification, is a programme-level result
and is answered once for the platform. No component is classified on a
programme-level property, and no programme-level property is claimed
because some number of components reached a per-component result.

**`FULL-CHAIN-VALIDATED`, per component.** A component carries this only
when every one of the following is true of that component, each with
retained evidence, and each only where the item applies to it:

- The applicable shared delivery chain completed for it, composed from
  shared templates with no unjustified service-local pipeline logic.
- Its static-validation, build and test results are measured and reported
  truthfully. A component with no tests upstream records that it has
  none. A component whose language offers no conventional lint or test
  gate in this pipeline records that fact rather than an absence that
  reads as a pass.
- It passed security admission under the gate ADR-0009 sets, ADR-0014
  extends and ADR-0015 fixes.
- Its artifact was published and its immutable digest recorded, read back
  independently from the registry.
- The desired state that deploys it references that exact digest.
- Reconciliation of that desired state onto the cluster was observed.
- Its workload reached the healthy or ready state declared for it in
  advance. The declared expectation is what is checked: a component with
  no listening endpoint is not expected to serve one, and its expected
  state is stated before the runtime rather than inferred afterwards.
- Telemetry attribution for it was demonstrated to the depth the
  programme requires, which ADR-0010 already refuses to claim is uniform
  across a polyglot fleet.

Route 53, TLS, the external browser path, alerting, controlled failure,
recovery and teardown are **not** per-component requirements and are never
required of an individual component for this classification. They are
programme-level results.

**`SECURITY-HOLD`.** The component's built digest did not pass security
admission, and no admissible exception exists for it. This class is
governed by the security-admission records, not by this one, and nothing
here weakens, narrows or reinterprets them. It is a completed result.

**`TECHNICAL-HOLD`.** A measured technical condition prevented the
component from completing a stage the programme applies to it, for a
reason that is not a security-admission outcome. The condition may arise
at any stage, including static validation, build, the tests the component
actually has, container health validation, artifact publication, digest
pinning through the supported desired-state mechanism, dependency startup,
runtime start, or deployment readiness. A record in this class is
incomplete, and the component is not classified, unless it carries three
things: **the exact measured cause, the exact stage that was blocked, and
a reference to the evidence that measured it.** A component is never
placed here on a suspected, predicted or unmeasured basis, and the class
is not a container for results nobody investigated. Where the blocking
condition is a property of the platform's own tooling or of the upstream
chart rather than of the component, the record says so, because that
distinction is what makes the result actionable.

**`NOT-DEPLOYED-BY-DECISION`.** A component **inside the justified
project-built inventory** that was intentionally excluded from the runtime
by an explicit recorded decision rather than blocked by a measurement. The
exact decision and its reason are recorded. Deliberate exclusion is never
reported as, or confused with, a technical or security failure, and a
technical or security failure is never recorded as a decision.

The load generator and the workload's bundled observability stack sit
**outside** the justified project-built inventory, under ADR-0014's
default exclusion, which this record does not disturb. They are not part
of the inventory this record classifies, they take no per-component
terminal classification under it, and they never enter the denominator
against which a per-component result is reported.

**The non-project-built runtime surface enters scope with the fleet.**
ADR-0012 requires a deployed component the project did not build to be
pinned by digest, mirrored into the platform registry so that no pod start
depends on an external service, and scanned there under the same threshold
that gates built services. ADR-0014 created a separate infrastructure
dependency class and left its form open without restating that handling.
This record closes that gap for this programme: **every image identity the
selected runtime pulls is either project-built and published by this
project's pipeline, or pinned by digest, mirrored and scanned before the
runtime window opens.** Init-container images are inside this rule and are
not a category that escapes it by being small. An image identity that
cannot be mirrored and pinned blocks the component that requires it, and
that block is recorded rather than waived.

**The programme inherits the platform's standing exercises rather than
replacing them.** ADR-0011 places a workload-data restore exercise on the
platform's standing proofs and makes it actionable once the data model and
datastore are settled. ADR-0012 established that the workload holds
durable data, and ADR-0011 requires durable data of that kind to be placed
in a managed service with native backup. No datastore product has been
selected, none is implemented, and no backup or restore has been
exercised. Where the programme's runtime includes that datastore, the
restore exercise is owed as a result in its own right and is not
discharged by application-level fault recovery, which is a different
exercise answering a different question. Nothing here relaxes that
obligation, moves it, or converts one exercise into the other.

**What this supersedes in ADR-0016.** Two elements, named exactly.

The Decision sentence "Implementation scope is bounded by demonstrated
platform-validation value, not by fleet completeness", together with the
sentence that follows it, is superseded for the justified project-built
inventory. It continues to govern anything outside that inventory.

Stopping condition 5 is superseded as the per-component admission test for
components already inside the justified project-built inventory. This
record is the explicit owner decision that condition 5 requires, made once
for that inventory and recorded here rather than nine times. For any
component **outside** that inventory, condition 5 stands unchanged and
still requires a named unproven property, an explicit owner decision and a
record.

Stopping condition 4 is not superseded and remains fully in force. The
owner-selected end-to-end programme supplies the engineering
justification that condition 4 asks for, and supplying a justification is
not the same as satisfying the trigger. **The trigger is satisfied only
when an owner-authorized runtime window justified by this objective
actually opens**, under the existing runtime authorization model.
Accepting this record neither opens nor authorizes such a window, and no
runtime window is authorized by it. Until one opens, the three fleet-scale
properties remain declared limitations, recorded exactly as ADR-0016
recorded them. After one opens, they retire only where evidence supports
retirement, and only to the extent it does.

**What remains in force.** Everything else in ADR-0016: its measured
historical basis, the distinction between bounded and complete, the rule
that no new service count is the objective, stopping conditions 1, 2 and 3
including that ADR-0012's minimum evidence set remains the bar against
which requirement satisfaction is judged, the admission test for
components outside the justified inventory, and the statement that
historical records keep their meaning. Everything ADR-0016 kept in force
from ADR-0014 and ADR-0012 stays in force, unchanged: the two-scope model,
the five-class classification, the two-tier evidence-depth model, the
reusable delivery model, the two-pass scanning order, the risk-based
security exception policy, provenance and attribution obligations, the
rule that prior bare-metal evidence is not this platform's evidence, and
the default exclusion of the load generator and the bundled observability
stack.

**Relationship to ADR-0014.** ADR-0014 selected the complete justified
application fleet as the implemented scope, and ADR-0016 superseded that
one sentence. This record does not revive it by reference. It makes its
own selection, on a narrower and different basis: not that breadth
exercises operational surface, but that the end-to-end chain and the
polyglot delivery surface are platform properties that cannot be
demonstrated otherwise. A reader needs this record and ADR-0016 to see the
whole history, and ADR-0014 keeps its Accepted status and its own
reasoning intact.

**Historical records keep their meaning.** Every earlier record
describing ADR-0014 breadth as incomplete was accurate when written and
remains accurate. Every earlier record describing the scope as
deliberately bounded under ADR-0016 was accurate when written and remains
accurate as a statement about the period it covers. Nothing here converts
a historical INCOMPLETE into a completion, and no state entry, evidence
record or public claim may be read that way. This record changes what the
project intends to attempt next. It changes nothing about what the
project had done when those records were written.

**Not authorized by this record.** Acceptance of this record authorizes no
implementation, no AWS mutation, no image publication, no runtime window
and no cost. Each of those follows the existing authorization model:
ADR-0003 for the Terraform workflow, ADR-0013 for cost and window
approval, ADR-0015 for security admission, and a separate owner grant,
recorded before each bounded step.

## Considered Options

| Option | Assessment | Outcome |
|---|---|---|
| Keep ADR-0016's bounded scope | Honours a sound record whose premise, that no runtime window is available, is no longer the owner's position, and leaves the end-to-end chain permanently undemonstrable | Rejected |
| Admit the nine components one at a time under ADR-0016 stopping condition 5 | Uses the existing mechanism without a new record, and would require nine property claims of which several would honestly be "the same mechanism at larger scale", weakening the test it uses | Rejected |
| Edit ADR-0016 in place | Produces a tidier register and destroys the record of why the scope was bounded on measurement | Rejected |
| Supersede ADR-0016 entirely | Simpler to read, and discards a correct measured basis, a still-valid admission test for components outside the inventory, and three stopping conditions that remain the right constraints | Rejected |
| Supersede only the scope decision and the admission test's application to the justified inventory, with a four-scope result model | Changes the one judgement the new objective invalidates, keeps every measurement and constraint that still holds, and makes a held component a completed outcome rather than an open task | Selected |
| Set the target as "all 17 green" | Easy to report against, and converts a security or technical HOLD from an honest result into a failure the programme is pressured to suppress | Rejected |

## Rationale

The owner's objective names nine platform properties. Not all nine are
advanced by fleet breadth, and saying so is the difference between a scope
decision and a rationalization.

**Advanced strongly by breadth.** The reusable delivery mechanism is the
clearest case. ADR-0014 promised only that the control structure is
shared, and explicitly refused to promise one identical job implementation
across every language. At four tiers that claim is nearly unfalsifiable.
At ten, spanning .NET, the JVM, Python, Ruby, C++ and Elixir alongside Go,
Node, Rust and PHP, it becomes a claim a reader can check and the project
can fail. Security admission is the same argument with a sharper edge: ten
ecosystems present ten different base-image and dependency vulnerability
profiles, and the risk-based exception policy ADR-0014 spent its
governance on has so far been exercised on a handful of components.
GitOps reconciliation across the admitted workload is unreachable today at
3 pinned components out of 20 rendered, and is one of the three
limitations ADR-0016 declared. Telemetry attribution under fleet load is
the second, and ADR-0010 records that the owner's prior project lost
exactly that attribution across collection hops, which makes it a measured
risk rather than a hypothetical one. Runtime dependency handling is
entirely unproven: no runtime window has ever run the broker, the cache or
the datastore, and the asynchronous producer-to-broker-to-consumer path is
one of the nine deep-validation paths ADR-0014 named and none has
exercised.

**Advanced weakly, and recorded as weak.** Registry and provenance
mechanics across the complete fleet is scale evidence, not capability
evidence. The DIRECT published-digest binding is already proven for both
provenance-eligible classes; repeating it twelve more times demonstrates
that the same mechanism holds at seventeen repositories and seventeen
lifecycle policies, which is worth knowing and is not a new capability.
Teardown across the broader runtime is weaker still as stated. Teardown
has already been proven zero-residual against 22 addresses, and more
application pods add almost no billable AWS surface. The genuine new
teardown risk is not fleet size at all: it is the ingress, load balancer,
DNS and certificate resource classes that ADR-0018 introduces, several of
which are created by an in-cluster controller and therefore sit outside
Terraform state. Scheduler and capacity behaviour sits between the two:
20 Deployments and 26 containers against a two-node `m6a.large` group is a
real scheduling and pod-slot question, but part of it is an artifact of
the node shape rather than a platform property.

**Not a breadth argument at all.** The external end-to-end request path
is the single largest genuinely new capability in this programme, and it
requires the frontend and the proxy, not seventeen services. It is
included here because it is the objective's centre, not because breadth
delivers it.

That analysis is why this record sets a surface rather than a target
count, and why the result model treats HOLD as a completion. If the honest
answer for a component is that a tier was built, the image was scanned and
the finding has no acceptable mitigation, the programme has produced a
real engineering result. The failure mode this record exists to prevent is
the one where that answer becomes inconvenient because a number is being
reported.

The cost ADR-0016 identified has not gone away. Six language tiers is
still the expensive unit, the exception surface still widens, and the
marginal provenance argument is still close to zero. What changed is that
those costs now buy an end-to-end demonstration that the project cannot
make at any fleet size without them, rather than buying a fifth proof of a
property already demonstrated four times.

In a production organization this would differ in stated ways. Workload
breadth would follow product need, a held component would have an owner
other than the person who held it, and no team would carry seventeen
services to validate a platform. Those are recorded assumptions, not
claims about this platform.

## Consequences

Gained: an end-to-end chain that can be demonstrated rather than
described, a delivery model whose polyglot reusability becomes falsifiable
across ten ecosystems, a security policy exercised across a genuinely
varied build surface, the three fleet-scale properties made reachable, a
result model in which an honest HOLD is a completed outcome, and one
explicit scope decision in place of nine weaker ones.

Paid for: six language-tier implementations, twelve additional registry
repositories with their lifecycle policies and standing storage cost, a
materially wider vulnerability surface across ten ecosystems, a mirroring
and digest-pinning obligation for every non-project-built runtime image
including init containers, a larger runtime footprint whose capacity shape
must be measured before a window rather than assumed, and a longer
programme whose delivery dates no longer fit the operating contract that
carried the bounded scope.

Not claimed: that the fleet will be delivered, that every component will
pass admission, that the chain will succeed end to end, that any component
beyond the currently implemented set has been built, scanned, published or
deployed, or that the platform is production-ready. None of it is true at
acceptance, and the result model exists so that none of it can be implied
by silence afterwards.

## Deferred Decisions

This record leaves open, for later decision records or approved
implementation planning: the order in which language tiers are
implemented, the per-tier template design, the registry repository set's
final membership, the node shape and capacity for a fleet runtime, the
number and length of runtime windows, whether `flagd-ui` is pursued
through a chart fork under ADR-0009's recorded fallback or left
TECHNICAL-HOLD, whether any held component is later retired from the
inventory, and the durable datastore product, which remains deferred under
ADR-0012 and constrained by ADR-0011.

## Revisit Triggers

Revisit if the first implemented language tier, or subsequent measured
tier work, shows that the delivery effort or the exception surface a tier
brings with it is materially larger than the basis this record assumes.
This record sets no numeric estimate, so the trigger is measured
implementation evidence rather than variance against a forecast. Revisit
if a tier cannot be brought
into the shared pipeline without service-local logic that cannot be
justified, since that falsifies ADR-0016 stopping condition 1 rather than
merely straining it. Revisit if the security-admitted fleet turns out to
be small enough that the runtime-admitted fleet cannot exercise the
fleet-scale properties this record is justified by. Revisit if fleet
runtime pushes the monthly cost model past the ADR-0013 review threshold.
Revisit if the non-project-built image surface proves unmirrorable in a
way that blocks the selected runtime. Revisit if upstream restructures the
application so that the justified inventory description becomes
inaccurate.
