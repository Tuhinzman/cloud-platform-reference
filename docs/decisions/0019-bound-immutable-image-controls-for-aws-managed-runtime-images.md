# ADR-0019: Bound immutable-image controls for AWS-managed runtime images

## Status

Proposed (2026-09-22)

Narrowly supersedes one sentence and one clause of ADR-0017's Decision,
named exactly in **Supersession** below and bounded to one measured image
class. Everything else in ADR-0017 remains Accepted and authoritative.
ADR-0006, ADR-0008 and ADR-0015 are unchanged.

## Context

ADR-0017 requires that every image identity the selected runtime pulls is
either project-built and published by this project's pipeline, or pinned
by digest, mirrored and scanned before the runtime window opens. That
requirement was written without measuring what the EKS managed add-on
mechanism actually exposes.

A bounded zero-node observation measured it. The four pinned managed
add-ons were created on a real cluster with no worker capacity, so their
workload objects were written by the provider but no container ever ran.
All seven resulting image references are tag-based; none is digest-pinned.
The add-on version is not a reliable proxy for the image that would run:
`eks-pod-identity-agent` v1.3.10-eksbuild.3 ships images tagged v0.1.37,
and `vpc-cni` v1.22.3-eksbuild.1 ships a third container tagged
v1.3.7-eksbuild.1.

The add-on configuration schemas explain why the project cannot close the
gap by configuration. Every image-related object in them sets
`additionalProperties: false` and exposes `pullPolicy` alone. There is no
repository, tag, digest or image-reference field. `imagePullSecrets`
selects credentials, not identity.

The EKS-managed node/AMI mechanism is named in this record's class because
it is the same kind of provider-selected delivery, but it was **not**
measured by this observation, which ran with no worker capacity. The
project currently selects node images by `ami_type` with no `image_id`,
so AWS chooses the image. Whether that mechanism exposes supported control
is a separate measurement, owed before the class is relied on for it.

So for the managed add-on mechanism ADR-0017's requirement is not merely
unmet; it is unreachable through any supported configuration. Leaving it
stated as a requirement would make the record describe a control the
project cannot exercise, which is worse than recording the limitation.

## Decision

**Keep the AWS-managed EKS add-on model**, and keep the EKS-managed
node/AMI mechanism.

**Define the AWS-delivered image class narrowly.** An image belongs to it
only when both hold: it is delivered by the EKS managed add-on mechanism
or the EKS-managed node/AMI mechanism, **and** that mechanism exposes no
supported project control over the pulled image reference or digest. The
second condition is measured per mechanism and per version, never assumed.
Until that measurement exists, images delivered by the node/AMI mechanism
remain under ADR-0017 unchanged. The measurement is owed before the first
node-bearing runtime window.

**This is a delivery-control class, not a security class.** It changes
what the project can control about image identity before a pull. It
changes nothing about what the project admits. ADR-0015 applies to it in
full, with no new exception path and no vendor-managed carve-out.

**Everything the project can pin or mirror stays under ADR-0017
unchanged**, including project-built workload images, project-selected
third-party workload images, Helm and controller images chosen by platform
desired state, Argo CD, ESO, observability components, Kafka, Valkey,
seed and client images, and init containers of all of these.

**Compensating controls, required for the AWS-delivered class.**

1. Pin the exact add-on and version, where the mechanism accepts a version.
2. Retain the measured image-reference discovery as evidence.
3. Before every runtime window, resolve each discovered tag or reference
   to its immutable digest.
4. Resolve the `linux/amd64` child digest where the reference is a
   multi-platform index.
5. Scan that exact digest under ADR-0015.
6. ADR-0015 governs the outcome unchanged: a fixable HIGH or CRITICAL
   finding holds by default; a Development or Validation admission is
   possible only through the existing bounded exception contract; there is
   no Production Validation exception.
7. During the runtime window, capture the actual `imageID` and compare it
   to the identity admitted before the window.
8. A mismatch is a HOLD.
9. Workload and GitOps validation does not proceed until that identity
   assertion passes.
10. A new add-on version requires the image mapping and digests to be
    rediscovered and re-evaluated. They are never inferred from the
    add-on version, which the evidence shows does not track the tag.

**Declared limitation.** For the AWS-delivered class the project does not
have pull-time immutable artifact control. The provider-delivered
reference is tag-based, the tag may be mutable, and its mutability is not
controlled by this project. The compensating identity control is
**detective for the AWS-managed component, not preventive**: it observes
what ran, it does not constrain what is pulled. What it does prevent is
downstream progress — workload and GitOps validation stop when the runtime
identity does not match the admitted identity. This is not equivalent to
project-owned immutable digest delivery and is never described as such.

**Production Validation consequence.** ADR-0015 is unchanged. If an
AWS-managed add-on digest carries unresolved fixable HIGH or CRITICAL
findings, it cannot pass Production Validation, because ADR-0015 provides
no Production Validation exception path. This record creates no Production
Validation work; Production Validation remains outside the current
programme unless existing authority says otherwise.

## Consequences

Gained: an architecture record that matches what the platform can actually
control, a measured and narrow exception boundary, and a detective
identity control that stops downstream validation on mismatch rather than
allowing it to proceed unverified.

Paid for: a per-window digest-resolution and scanning step for the
AWS-delivered class, a re-discovery obligation on every add-on version
change, and a permanent declared limitation on pull-time image control for
that class.

Not claimed: that the AWS-delivered class is as controlled as
project-owned digest delivery, that tag mutability has been eliminated or
mitigated at pull time, that ADR-0015 admission is relaxed anywhere, or
that any add-on digest has yet been scanned. None of that is true at
acceptance.

## Evidence

A bounded control-plane-only observation on 2026-09-22, retained as
evidence: an EKS 1.36 cluster created with no worker capacity, reaching
zero nodes and zero pods with no container or initContainer execution, so
the add-on workload objects were read as the provider wrote them. It
discovered seven tag-based image references across the four pinned add-ons
and none pinned by digest, and it closed with a zero-residual teardown. The
add-on configuration schemas were captured alongside it. This record states
the measured conclusions and does not reproduce the evidence.

## Supersession

One sentence and one clause of ADR-0017's Decision are superseded, both
under "The non-project-built runtime surface enters scope with the fleet",
and each **only as applied to the AWS-delivered image class defined
above**. For every other image identity both stand unchanged and in full.

**A**, the pin-and-mirror requirement:

> every image identity the selected runtime pulls is either project-built
> and published by this project's pipeline, or pinned by digest, mirrored
> and scanned before the runtime window opens

For the class, that obligation becomes the ten compensating controls above.

**B**, the blocking clause that enforces A:

> An image identity that cannot be mirrored and pinned blocks the component
> that requires it

For the class, an identity the provider mechanism exposes no supported
control over does not block its component on that ground alone; the ten
controls govern it instead, and an identity mismatch remains a HOLD.
Superseding A without B would leave the class blocked by a rule enforcing a
requirement A no longer makes of it. The rest of that ADR-0017 sentence,
"and that block is recorded rather than waived", stands unchanged for the
class: the disposition is recorded, never silently waived, and this record
with its retained evidence is where it is recorded.

Between A and B in ADR-0017 sits one sentence that is **not** superseded:
init-container images are inside the rule and are not a category that
escapes it by being small. Everything else in ADR-0017, including its four
scopes, its result model and its own supersessions of ADR-0016, is
untouched and remains Accepted. ADR-0015 is not superseded, narrowed or
reinterpreted by this record.

## Revisit Triggers

Revisit if AWS exposes supported control over the pulled image reference
or digest for managed add-ons or managed node images, which would remove
the basis for the class and return it to ADR-0017 unchanged. Revisit if a
resolved add-on digest carries a fixable HIGH or CRITICAL finding with no
available fixed add-on version, since that is an ADR-0015 hold the
programme must answer rather than absorb. Revisit if a runtime `imageID`
comparison fails, because a mismatch measures either tag mutation or a
gap in the resolution step. Revisit if the class is ever proposed to cover
an image the project could pin or mirror.
