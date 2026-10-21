# ADR-0015: Security admission for platform components

Status: Accepted (2026-09-08); revised 2026-10-21, decision unchanged.

Adds a separate admission policy. ADR-0009, ADR-0010, ADR-0013 and
ADR-0014 remain unchanged.

## Scope and security gate

This policy covers non-workload components that provide platform
capabilities, including observability, ingress, certificates and controllers.

A datastore, cache or broker follows this policy when its ownership and
deployment make it a platform component. Application components follow
ADR-0009 and ADR-0014. Classify by purpose and ownership, not by product name.

Any fixable HIGH or CRITICAL finding places the component on HOLD. HOLD is
a normal, acceptable outcome, not a process failure.

Use Trivy with HIGH and CRITICAL severities, the unfixed-finding filter,
and a non-zero exit for blocking findings. No ignore file, combined-ignore
entry, severity reduction or scanner substitution.

Keep the gate unchanged in both directions. Any change requires a separate
reviewed decision and a new comparison baseline. An exception admits a
measured artifact; it cannot change the measurement.

## Admission by environment

| Environment or lifecycle | Rule |
|---|---|
| Development or Validation | A failing component needs an explicit owner-approved exception for one component, digest and runtime window. |
| Production Validation | No unresolved fixable HIGH or CRITICAL findings. No exception path. |
| Persistent or long-lived component | This policy provides no exception path. A failing component stays on HOLD. |

An exception requires an authorized, finite Development or Validation
window. The component must be destroyed with its environment.

The grading is deliberate. A universal gate with no exception path would
make the platform's ability to run its own infrastructure depend on
third-party release cadence and would reward scanning less often, while a
uniform exception policy would ignore that these components are ephemeral
and environment-scoped. Grading keeps strictness absolute where the
project's public claims are strongest.

Passing a scan or approving an exception does not authorize a runtime
window by itself.

## Exception requirements

Every exception must contain all of these fields:

- Identity and approval: affected component, exact linux/amd64 immutable
  digest, owner, environment role and approval evidence.
- Findings: identifier, affected package, severity and fixed-version
  availability for every blocking finding.
- Risk and purpose: exploitability in this context, runtime exposure,
  necessity, compensating controls and justification.
- End conditions: expiry and removal trigger.
- Supporting evidence: vulnerability database metadata current at approval,
  bounded currency-search evidence and lowest-obtainable-security-debt
  evidence.

Missing information means the exception cannot be approved.

Necessity must identify the Accepted architecture obligation or frozen
validation criterion that cannot be exercised without the component,
including where that requirement is recorded. General usefulness is
insufficient.

Before requesting an exception, check the same upstream image repository
for newer published identities compatible with the pinned chart's supported
image override mechanism. This does not require searching unrelated
distributions, rebuilding third-party components or forking charts.

Record the repository, pinned identity, search time, search boundary,
candidates evaluated and result. Finding no compatible newer candidate
is a valid result; skipping the search is not.

Compare compatible, obtainable candidates in this order:

1. Fewer blocking CRITICAL findings.
2. If equal, fewer blocking HIGH findings.
3. If both are equal, the comparison gives no preference.

Normally select the candidate with the lowest security debt. Choosing a
higher-debt candidate needs separate written justification. Even when only
one candidate exists, retain the search and selection evidence.

Lower security debt does not itself permit admission.

## Expiry, disclosure and limits

An exception applies only to its recorded component, digest and window.
It cannot transfer to another digest or window. No automatic or blanket
exceptions.

It expires when the authorized window ends. A newly obtainable fixed
artifact triggers removal of the exception without waiting for expiry.
Every new window requires fresh vulnerability evaluation and approval;
a previous grant cannot be reused.

Public claims and evidence that depend on an excepted component must
disclose the exception. Do not describe that component or dependent result
as clean, vulnerability-free or security-gate-passed. Independent results,
such as teardown verification, need no qualifier merely because an
exception existed in the same window.

Exceptions leave residual risk. Production Validation may remain blocked
by upstream vulnerabilities, including when that blocks project completion.

Image signing and build attestation remain deferred. Retain digest identity
and the recorded approval chain. Exception record format and storage remain
implementation choices.

Review this policy when exceptions recur across consecutive windows,
long-lived components are introduced, an excepted component is involved
in an incident, exception handling materially prevents validation,
signing changes the trust basis, or upstream vulnerabilities repeatedly
block Production Validation. A review does not itself grant admission.
