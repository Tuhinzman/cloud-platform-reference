# ADR-0019: Identity controls for AWS-managed images

Status: Accepted (2026-09-22); revised 2026-10-21, decision unchanged.

Narrowly replaces ADR-0017's pin-and-mirror requirement and its related
blocking clause for the image class defined below.
ADR-0006, ADR-0008 and ADR-0015 remain unchanged.
ADR-0020 later defines specific controls for the AMI-baked sandbox image.

## Scope

Keep the AWS-managed EKS add-on and managed node/AMI models.

This policy applies to an image only when both conditions hold:

- It is delivered through the EKS managed add-on or managed node/AMI mechanism.
- That mechanism provides no supported project control over the pulled
  image reference or digest.

Measure this limitation for each mechanism and version. Do not assume it
from the AWS-managed label.

The 2026-09-22 observation found tag-based image references and no supported
image override for the measured add-on versions. It used no worker nodes
and did not establish node/AMI controls or runtime image identity.

Node/AMI controls must be measured before the first node-bearing window.
Until then, ADR-0017 continues to apply, subject to ADR-0020's later,
specific sandbox-image decision.

Everything the project can pin or mirror remains under ADR-0017.
This includes workload images, project-selected controllers, observability
components, dependencies, seed and client images, and init containers.

## Required controls

1. Pin the exact add-on and version wherever supported. Discover and
   retain its actual image references.

2. Before every runtime window, resolve each reference to an immutable
   digest. For a multi-platform image, resolve its linux/amd64 child digest.

3. Scan that exact digest under ADR-0015. Fixable HIGH or CRITICAL findings
   mean HOLD by default. Development or Validation requires the existing
   owner-approved, digest-specific, window-bounded exception. Production
   Validation permits no exception.

4. During the window, capture the actual imageID and compare it with the
   image identity admitted before the window.

5. Workload and GitOps validation may proceed only after that comparison
   passes. A mismatch means HOLD.

6. When an add-on version changes, rediscover its image references and
   re-evaluate their digests. Never infer image identity from the add-on
   version number.

For this measured class, inability to pin or mirror does not by itself
block the component. These controls replace that delivery requirement;
security admission still applies in full. Record the outcome explicitly.

## Evidence

A bounded control-plane-only observation on 2026-09-22, retained as
evidence: an EKS 1.36 cluster created with no worker capacity reached zero
nodes and zero pods, so the add-on workload objects were read as the
provider wrote them. It found seven tag-based image references across the
four pinned add-ons, none pinned by digest, captured the add-on
configuration schemas, and closed with a zero-residual teardown. This
record states the measured conclusions and does not reproduce the evidence.

## Limits and review

The runtime comparison verifies what ran. It cannot prevent a different
image from being pulled or starting. Provider-controlled tags may change,
and this project does not control their mutability.

Keep this limitation visible in evidence and public claims. Do not describe
this mechanism as project-controlled immutable delivery.

This decision grants no runtime authorization and adds no Production
Validation work to the programme.

Revisit when AWS provides supported image control, an add-on fails the
security gate without an available fixed version, runtime identity does
not match, or this policy is proposed for an image the project can control.
Supported image control removes the basis for this exception and returns
the affected class to ADR-0017.
