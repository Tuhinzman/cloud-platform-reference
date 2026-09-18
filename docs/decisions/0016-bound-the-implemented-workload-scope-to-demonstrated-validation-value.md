# ADR-0016: Bound the implemented workload scope to demonstrated platform-validation value

## Status

Accepted (2026-09-18)

Supersedes one selection in ADR-0014: that the implemented fleet is the
complete justified AstroShop application fleet. Everything else ADR-0014
decided stands, and it keeps its Accepted status. ADR-0012 is unaffected
and keeps its Accepted status. No other accepted record is affected.

## Context

ADR-0014 widened the implemented workload from ADR-0012's four to six
services to the complete justified application fleet. It did so for a
reason that was correct when it was written: several properties worth
proving are properties of breadth rather than depth, and it named four
of them. Whether one delivery pipeline genuinely serves many services
instead of a few hand-tuned ones. Whether reconciliation holds across a
fleet. Whether telemetry attribution survives when many services emit at
once. Whether teardown is clean when there is more to clean up.

That record also estimated where the cost of breadth sits, and the
estimate has held: "adding a service inside a language tier that the
pipeline already supports is declarative configuration. What costs real
effort is a new language tier and, more seriously, the security
exceptions a component brings with it over time."

Implementation has now produced measurements that ADR-0014 could not
have had, because nothing was implemented when it was written. Two
things about the remaining work are different from what the original
cost model assumed, and both are measured rather than estimated.

The first is that the cheap case is exhausted. Of the nine components
not yet in the delivery path, zero fall inside a language tier the
pipeline already supports. Every one of them requires a new tier:
accounting and cart on .NET, ad and fraud-detection on the JVM,
product-reviews and recommendation on Python, currency on C++, email on
Ruby, and flagd-ui on Elixir. Six new tiers for nine components, at
roughly one and a half components per tier. ADR-0014 identified the
language tier as the expensive unit; what remains is entirely that unit.

The second is that three of the four breadth properties cannot be
advanced by the work that remains. Fleet-scale reconciliation, telemetry
attribution under fleet load, and fleet teardown are runtime properties.
They require a cluster, and no runtime window is authorized. Only the
first property is reachable without one, and it is already demonstrated:
eight components deliver through the shared templates across four
language tiers and two tier-less configured components, with zero
service-local pipeline logic anywhere in the fleet.

Artifact provenance has also reached a boundary that can be stated
exactly rather than approximately. ADR-0014 defines five component
classes, and only two of them can carry project-built provenance at all:
project-built application services, and project-built configured
components. Justified upstream exceptions carry none by design, which
ADR-0014 states rather than implies, and the remaining two classes are
not project-built. Both classes that can carry it now have a verified
CI-native evidence bundle with a DIRECT published-digest binding, where
the SHA-256 of the retained registry manifest bytes is the published
digest. That is complete within the scope where completeness is
possible, and it was established by two components: shipping for
project-built application services, and image-provider for project-built
configured components.

None of this makes ADR-0014 wrong. It was a sound decision on the
evidence available in August, and its cost model was accurate about
where cost lives. What changed is that the cheap half of the fleet is
done and the expensive half no longer buys the properties the expansion
was justified by.

## Decision

**Implementation scope is bounded by demonstrated platform-validation
value, not by fleet completeness.** Additional workload components enter
implemented delivery scope only when they validate a platform property
that the representative implementation has not already demonstrated.

This restores, for the implemented fleet, the admission test ADR-0012
applied to the minimum evidence set: a component is included because it
proves something the rest does not. ADR-0014 correctly observed that
this test is the wrong one for judging requirement satisfaction against
a fleet. It is the right one for deciding what to build next, which is
the question this record answers.

**No new service count is set.** Replacing sixteen with some smaller
number would repeat the mistake this record exists to avoid, which is
deciding scope by counting. The stopping conditions below are the scope.

**Stopping conditions.** The implemented scope is sufficient when all
five hold, and each is checkable rather than asserted.

1. The shared delivery model is demonstrated across at least two
   language tiers and at least one tier-less configured component, with
   zero service-local pipeline logic. Measured at this record's
   drafting: four tiers, two tier-less components, zero service-local
   logic across eight wired components.
2. Every ADR-0014 project-built component class capable of carrying
   build provenance has at least one verified CI-native evidence path
   with a DIRECT published-digest binding. Measured: both eligible
   classes, by shipping and by image-provider.
3. ADR-0012's minimum evidence set remains the bar against which
   requirement satisfaction is judged. This record does not move it, and
   ADR-0014 did not move it either.
4. Fleet-scale reconciliation, telemetry attribution under fleet load,
   and fleet teardown remain **declared limitations**. They are recorded
   as unproven rather than carried as outstanding work, and they become
   work only if a future owner-authorized runtime window is justified on
   its own engineering value rather than on completing this scope.
5. A component is admitted only when it validates a platform property
   not already demonstrated by the representative scope. Before
   implementation begins, three things must hold: the property is named
   explicitly, admission is an explicit owner decision, and that
   decision is recorded in `STATE.yaml` or in an architectural record.
   A session report, an implementation plan, or an implementation
   agent's recommendation does not satisfy this condition on its own.

**What remains in force.** Everything ADR-0014 decided except the one
selection named above, specifically: the two-scope model separating the
minimum evidence set from the implemented fleet; the five-class
component classification and the evidence each class owes; the two-tier
evidence-depth model of a fleet-wide minimum and representative deep
validation by path; the reusable delivery model of shared stage and
language-tier templates with declarative per-service configuration and
service-local logic requiring written justification; the two-pass
scanning order; the risk-based security exception policy, including that
a held component is an honest outcome; the provenance and upstream
attribution requirements and the Apache-2.0 compliance obligations; the
rule that prior bare-metal evidence is not this platform's evidence; the
default exclusion of the load generator and the exclusion of the bundled
observability stack; and the supersession relationship ADR-0014 holds
over ADR-0012's service-count limit. From ADR-0012: the workload is an
instrument and the platform is the product, the ownership classes, the
durable-data requirement, and public reproducibility and attribution.

**Precisely what is superseded.** One sentence in ADR-0014's Decision,
"The **implemented fleet** is the complete justified AstroShop
application fleet", and the Considered Options row that records
"Implement the complete justified application fleet" as Selected. The
remainder of that Decision sentence, that the fleet exists to exercise
operational breadth and that its components are not individually
load-bearing for any requirement, remains true and remains in force.
Nothing else in ADR-0014 is narrowed, reinterpreted or set aside.

**What is not decided here.** This record does not remove any component
from the fleet inventory, does not change any component's
classification, and does not retire the fleet as an architectural
concept. The inventory in ADR-0014 remains the description of the
justified application fleet. What changes is that implementing all of it
is no longer the objective.

**Historical records keep their meaning.** Every earlier record that
describes ADR-0014 breadth as incomplete was accurate when written and
remains accurate as a statement about the full-fleet target. Nothing
here converts that target into a completed one, and no evidence record,
state entry or public claim may be read as saying the fleet was
delivered. The full-fleet target was not reached; it was bounded.

## Considered Options

| Option | Assessment | Outcome |
|---|---|---|
| Keep the full-fleet implementation scope | Honours ADR-0014 as written, and continues to optimize for a target whose remaining work costs six language tiers while advancing one already-demonstrated property and no runtime property | Rejected |
| Edit ADR-0014 in place to narrow its scope | Produces a tidier register and destroys the record of why breadth was chosen, leaving a decision that appears never to have been reconsidered | Rejected |
| Supersede ADR-0014 entirely | Simpler to read, and discards a two-scope model, a classification, an exception policy and an evidence-depth model that all remain correct | Rejected |
| Set a smaller fixed service count | Easy to check, and decides scope by counting, which is the failure this record exists to prevent | Rejected |
| Supersede only the implementation-scope selection, bounded by stopping conditions | Keeps every part of ADR-0014 that still holds, changes the one selection the measurements undermine, and leaves a written admission test for future components | Selected |
| Defer the decision until a runtime window is authorized | Defensible, and leaves the project carrying an open target it has decided not to pursue, which is less honest than bounding it | Rejected |

## Rationale

The distinction that matters is between what was measured and what is
judged. The measurements are that nine components remain, that they
require six new language tiers, that none of them fits an existing tier,
that eight components deliver through shared templates with zero
service-local logic, that one of four breadth properties is demonstrated
and three require a cluster, and that both provenance-eligible classes
carry a DIRECT-bound bundle. Those are facts about the repository and
the retained evidence, and a reader can check every one of them.

The judgement is that continuing would optimize for completeness rather
than for learning value. A reviewer reading this project learns that one
delivery pipeline serves services across four language ecosystems and
two components with no application source at all, without a line of
service-local pipeline logic. A fifth, sixth and seventh ecosystem
demonstrate the same property again. The marginal engineering argument
is close to zero, while the marginal cost is six template
implementations and a wider exception surface that ADR-0014 already
listed under what breadth is paid for.

This is the project's own stated non-goal. The charter does not optimize
for technology count, for making every accepted decision look fully
implemented, or for eliminating every declared limitation. A declared
limitation that names exactly what is unproven is worth more than a
larger fleet that proves the same thing repeatedly.

An in-place edit of ADR-0014 was rejected on the same reasoning ADR-0014
applied to itself. That record declined to supersede ADR-0012 entirely
because doing so "discards reasoning that remains correct and overstates
what changed", and instead superseded one rule and said so precisely.
Editing ADR-0014 now would do what it refused to do: it would erase a
sound August decision, leave no trace that the scope was reconsidered on
evidence, and make every earlier record that cites the full-fleet target
unreadable. A narrow superseding record keeps the reasoning, the
reversal and the evidence for the reversal all legible at once.

The revisit trigger question deserves an honest answer rather than a
convenient one. ADR-0014 says to revisit if maintaining the fleet begins
to compete with the platform work it exists to validate. On maintenance
burden alone, that trigger has **not** fired: the eight wired components
have needed almost no upkeep and the shared-template model has held
without service-local logic. This record does not claim otherwise. The
case for narrowing rests on the measured inversion of cost and return
described above, and on ADR-0014's own statement that fleet size is not
the objective, not on a maintenance burden that has not materialized.

The platform remains the product, and this record moves that boundary
toward the platform rather than away from it. ADR-0012 established that
the workload is an instrument. Continuing to build workload services in
ecosystems the platform already handles is workload engineering, and it
competes for attention with the platform surfaces a reviewer actually
inspects. Bounding the instrument at the point where it stops teaching
something new is what keeps AstroShop an instrument.

## Consequences

Gained: an implementation scope with a written admission test rather
than an open target, a stated boundary for artifact provenance that is
complete where completeness is possible, effort released from language
tiers that demonstrate an already-demonstrated property, and a public
position that is easier to defend because it says what is unproven.

Paid for: the fleet-scale properties ADR-0014 wanted stay unproven, and
are now declared limitations rather than planned work. The delivery
model's reusability is demonstrated across four language ecosystems
rather than ten, so a claim about ecosystems beyond those four cannot be
made. The exception surface stays smaller, which is a benefit, but it
also means the exception policy is exercised on fewer components than
ADR-0014 anticipated.

Not claimed: that the fleet was delivered, that full-fleet CI/CD is
complete, that any component beyond the implemented set has been built,
scanned, published or deployed by this project, that the wider fleet has
runtime validation, or that the platform is production-ready. None of it
is true, and the stopping conditions above exist so that none of it can
be implied by silence.

## Deferred Decisions

Whether any further language tier is implemented at all is left open. If
one is, it is admitted through stopping condition 5 on the same terms as
any other component, and no ecosystem is favoured here. Whether a future
runtime window is opened for the three declared limitations is an owner
decision under the existing runtime authorization model and the cost
guardrails in ADR-0013. Whether the remaining components are eventually
removed from the fleet inventory, or left as described but
unimplemented, is not decided here.

## Revisit Triggers

Revisit if a platform property emerges that the representative scope
demonstrably cannot validate. Revisit if a runtime window is authorized
for reasons of its own and fleet-scale properties become reachable as a
by-product. Revisit if the shared delivery model turns out to require
service-local logic for an ecosystem the project decides it needs, since
that would falsify stopping condition 1 rather than merely strain it.
Revisit if the provenance boundary changes, for example if a component
class that cannot carry build provenance today becomes able to. Revisit
if upstream restructures the application in a way that makes the
remaining inventory description inaccurate.
