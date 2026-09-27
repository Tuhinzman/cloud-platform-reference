# ADR-0020: Govern the AMI-baked Kubernetes sandbox image by release pin and identity controls

## Status

Proposed (2026-09-27)

This record makes two narrow changes to Accepted decisions, both named exactly
in **Supersession** below and both bounded to one image: the Kubernetes pod
sandbox image baked into the EKS-optimized Amazon Linux 2023 AMI that the dev
node group selects by a pinned release.
- It supersedes one sentence and one clause of ADR-0017's Decision for that
  image.
- It narrows ADR-0015's exact-digest admission for that image, in one
  discovery window per pinned release.

Everything else in ADR-0017 and ADR-0015 remains Accepted and authoritative.
ADR-0006 and ADR-0019 are unchanged.

## Context

ADR-0017 has two requirements that matter here:
- every image identity the selected runtime pulls must be project-built, or
  pinned by digest, mirrored and scanned before the runtime window opens;
- a component whose image cannot be mirrored and pinned is blocked.

ADR-0019 keeps images delivered by the EKS-managed node/AMI mechanism under
that rule until the mechanism is measured. ADR-0015 evaluates a platform
runtime component fresh for every window and binds any exception to its exact
`linux/amd64` digest.

Every pod on a node runs inside a sandbox container, so the sandbox image
runs in every pod. On this project's node path, the EKS-optimized Amazon
Linux 2023 AMI chosen by `ami_type`, no Kubernetes object selects that
image. It comes with the AMI.

A read-only control-surface measurement, made before any node-bearing window
and without running a node, established the following.

- **Provider controls.** The pinned AWS provider exposes `release_version`
  on the managed node group, and `image_id` and `user_data` on the launch
  template.
- **Release pinning.** For Kubernetes 1.36, AWS publishes one parameter set
  per AMI release; 18 releases were listed. An unpinned node group takes
  whichever release AWS recommends when the group is created, and that
  recommendation's parameter was at its eighteenth version. Release
  `1.36.4-20260923` names one public, immutable AMI in each region,
  `amazon-eks-node-al2023-x86_64-standard-1.36-v20260923`.
- **How the image is baked.** The AMI's public build source at the matching
  release tag (`awslabs/amazon-eks-ami`, tag `v20260923`, commit
  `2de204d7369af45eb1177e5815bd0be350ce3f01`) shows what happens to the
  sandbox image:
  - The build pulls it once, retags it as `localhost/kubernetes/pause:latest`,
    labels it pinned so the runtime does not collect it, records its source
    reference, and exports it into the AMI.
  - At node start, the node agent sets containerd's sandbox image to that
    local tag.
  - So, from source, node startup does not pull it.
- **Unestablished source.** The build template's default source reference
  is `public.ecr.aws/eks-distro/kubernetes/pause:3.10`. AWS's own build can
  override that default, so the source reference and digest of the image
  actually baked into the published AMI are not established before a node
  exists.
- **Cost of a project-owned sandbox.** A project-owned sandbox is possible
  only by taking over node bootstrap, through a custom AMI or a containerd
  override in launch-template user data.
  - The AMI build needs explicit ECR credentials to pull a sandbox image
    from an ECR registry.
  - The node agent's source records that on one path, its SOCI snapshotter
    path, containerd cannot fetch the sandbox image from ECR at sandbox
    creation, because ECR credentials are not yet available then.
  - From that source, not from a measurement: an override pointing at the
    platform registry would need a credentialed pre-pull, completed before
    the kubelet creates the first pod sandbox.

These findings come from four sources: the provider schema, AWS's published
release parameters, the AMI metadata, and the AMI's public build source.
None of them is a runtime observation, and no node has run this AMI in this
project.

So the exact identity of this image cannot be evaluated under ADR-0015
before a node of the release has run. The first node-bearing use of a
release necessarily runs the image before its exact digest is known.

ADR-0017's revisit trigger for an unmirrorable surface is not literally met.
This image can be mirrored, but only by taking over node bootstrap, which
this record declines for the reasons below. Without this record, ADR-0017's
blocking clause would block every component that runs a pod.

## Considered Options

| Option | Assessment | Outcome |
|---|---|---|
| A. Project-owned sandbox: mirror a pause image to the platform registry, pin it by digest, scan it, and point containerd at it through launch-template user data with a credentialed pre-pull, or through a custom AMI | Satisfies ADR-0017 and ADR-0015 literally, but takes over the node bootstrap contract that the launch template deliberately leaves to EKS. Adds a foundation registry repository, user data, and a pre-pull step that must finish before the first pod sandbox; if it fails, the node cannot run pods. None of it has been measured here | Rejected |
| B. Keep the AWS-baked sandbox image, fixed by a pinned AMI release, with one bounded discovery window per release and the controls below | Keeps the node bootstrap contract with EKS and adds no join-time dependency. The exact digest is observed in the discovery window, detectively, and then evaluated under ADR-0015 before any later use | Selected |

## Decision

**Keep the AWS-baked sandbox image of the pinned EKS-optimized AMI** for the
dev node group, governed by this record instead of by ADR-0017's pin, mirror
and block rule.

**Rationale.**
- The image is baked into an immutable AMI and, on the build path shown by
  its source, is not pulled during node startup.
- `release_version` pins the exact AMI release, and with it the image.
- Option A would add custom, credentialed bootstrap logic and a new way for
  a node to fail to run pods. That costs more than the identity it would
  gain over the controls below.

The choice rests on that evidence and on option A's failure surface, not on
schedule. This record does not rely on the word "pulls" in ADR-0017 to take
the image out of that rule. It supersedes the rule for the image
explicitly.

**Scope.** This record covers exactly one image: the Kubernetes pod sandbox
image baked into the EKS-optimized Amazon Linux 2023 AMI named by the node
group's pinned `release_version`. It applies only while the node group
selects that AMI through `ami_type` and `release_version`, with no custom AMI
and no containerd sandbox override. It covers no other image of any kind. Any
other image found delivered by the node/AMI mechanism stays under ADR-0017
unchanged and blocks as ADR-0017 requires.

**ADR-0015.** The sandbox image is a non-workload runtime component that the
platform operates on every node, so ADR-0015 governs it. Only one requirement
is narrowed: in the discovery window below, the identity evaluated is the
source-declared one, not the exact running digest. **This record creates no
new security exception path.** Any fixable HIGH or CRITICAL finding on an
identity that can be evaluated holds by default and is admissible only
through ADR-0015's full exception contract. No discovery window runs in the
Production Validation role.

**Release pin.** The node group's `release_version` is pinned to one exact
AMI release. A change of release is a reviewed code change. A release that
has never had a discovery window starts this lifecycle with one; a release
that has had one keeps its recorded outcome, including BLOCKED.

**Discovery window.** The first node-bearing use of a pinned release is a
discovery window for this image. It is not pre-admitted execution. It runs in
a Development or Validation role only, and it exists to observe the baked
identity. Before it opens, all of these must hold:
1. `release_version` is pinned to the exact release.
2. The release's exact immutable AMI identity is recorded: its AMI ID for
   the region, from AWS's published parameter for that release.
3. The source-declared sandbox identity is resolved by immutable digest,
   including its `linux/amd64` child where the reference is an index. That
   identity is the sandbox image reference in the AMI build source at the
   release tag.
4. That `linux/amd64` identity has been evaluated under ADR-0015. If it is
   on HOLD, the discovery window does not open unless ADR-0015's full
   exception contract admits that identity for that window.
5. No workload or GitOps deployment is part of the window.

In the window, immediately after each node joins, capture `node.status.images`
and confirm that the node group's `releaseVersion` is the pinned release and
that every node runs the recorded AMI ID
(`eks.amazonaws.com/nodegroup-image`). This observation is **detective** for
the exact baked digest: it reports what the AMI carries once a node exists,
and nothing before that window establishes the baked bytes.

**Match rule.** The observed digest matches only when every node reports
`linux` and `amd64` and the digest satisfies one of these:
- it equals the evaluated `linux/amd64` identity;
- it equals the index digest resolved before the window, where the exact
  index bytes are retained, the digest recomputes from those bytes, and the
  single `linux/amd64` entry in those bytes is the evaluated identity.

Anything else is a mismatch, including a different index with the same child.

**On a match.**
- The observed identity is recorded.
- The window proves identity, not prior admission. The source-declared
  evaluation stood in for the exact digest, and the window is never described
  as pre-admitted execution.
- From the next window on, the sandbox image is evaluated under ADR-0015's
  normal contract.

**On a mismatch or an unobservable identity.**
- HOLD immediately.
- Capture evidence.
- No workload or GitOps deployment.
- Tear down.

No owner approval given in the same window can continue it. The release is
BLOCKED. It is used again only after a recorded decision on the revisit
trigger, and only once the exact image it runs has been retrieved and
evaluated as below.

**Exact observed-image evaluation.** An observed digest is not assumed to be
retrievable. A node-local tag or digest is not, by itself, a retrievable
identity.
- Before any later window on a release, the exact observed image must be
  retrieved independently by immutable identity and evaluated under
  ADR-0015.
- If the exact observed bytes cannot be retrieved and evaluated, the release
  remains BLOCKED.
- Owner approval does not substitute for retrieval, for the scan, or for the
  ADR-0015 disposition.

Once retrieved and evaluated, the exact observed identity, with its
`linux/amd64` entry where it is an index, is the admitted identity for the
release.

**Later windows.** Every later window on the release must satisfy all of
these:
- It runs the same pinned release. The node group's `releaseVersion` equals
  the pinned release, and each node's `eks.amazonaws.com/nodegroup-image`
  label equals the recorded AMI ID.
- The admitted identity is evaluated fresh under ADR-0015 before the window.
- Every node reports the admitted identity, captured at the same point as in
  the discovery window, under the same match rule.

Workload and GitOps validation does not start until that check passes.

**No equivalence by analogy.** No other image and no other AMI is governed by
analogy. Pinning an AMI release is not mirroring, and this record creates no
general AMI-mirror equivalence.

**HOLD and BLOCKED.** Each of the following is a HOLD:
- the source-declared identity cannot be resolved or evaluated before the
  discovery window;
- the observed digest does not match;
- the sandbox tag is absent, or appears without a digest, in
  `node.status.images`;
- the node group's `releaseVersion` differs from the pinned release, or a
  node's AMI label differs from the recorded AMI ID;
- the sandbox image holds under ADR-0015 without an approved exception.

A HOLD before a window keeps it closed. A HOLD inside a window stops workload
and GitOps validation, and the window continues only to capture evidence and
tear down. A release whose exact observed image cannot be
retrieved and evaluated is BLOCKED. Every HOLD and BLOCKED outcome is
recorded, never waived, and never resolved by inference.

**Declared limitation.** For this image the project has no pull-time control
and no project-owned copy.
- In each discovery window the image runs before its exact digest is
  evaluated. There, the ADR-0015 evaluation covers the source-declared
  identity, not the bytes that ran, and evidence from that window carries
  that qualifier.
- The identity control is detective, not preventive.
- The source-declared reference is a tag, resolved when the check runs,
  which is later than the AMI build. It may have moved since, which fails
  closed as a HOLD.
- It is not established that `node.status.images` exposes a digest for the
  baked image, or that the observed image can be retrieved independently.
  Either gap holds or blocks the release rather than being inferred away.
- The kubelet reports a bounded number of images, largest first. That is why
  the capture is taken as each node joins.
- Pinning the release also freezes the node operating system and kubelet
  patch level until a reviewed change moves it.

## Consequences

Gained:
- node image selection that is fixed and reviewable, rather than whatever
  release AWS recommends on the day of the apply;
- no project-owned node bootstrap and no join-time registry dependency;
- a sandbox identity the project observes, and must retrieve and evaluate
  before reuse, instead of assuming.

Paid for:
- one discovery window per release, during which the image runs before its
  exact evaluation;
- a scan of the source-declared identity before that window, and of the
  exact identity before every later one;
- a release that cannot be used again if its baked image cannot be retrieved
  and evaluated.

Not claimed:
- that the sandbox image is project-built, mirrored, or under pull-time
  project control;
- that the discovery window's sandbox was admitted before it ran;
- that the source-declared identity equals the baked one; the discovery
  window decides that;
- that any node has run this AMI; no runtime validation has happened under
  this record at proposal;
- that this image belongs to ADR-0019's AWS-delivered class.

## Evidence

A read-only control-surface measurement on 2026-09-27, retained as evidence,
covered four sources:
- the pinned provider schema;
- AWS's published Kubernetes 1.36 Amazon Linux 2023 release parameters;
- the metadata of the AMI for release `1.36.4-20260923`;
- the AMI's public build source at tag `v20260923`, with each file
  hash-matched to its Git blob.

No node was created and no AWS resource was changed. This record states the
conclusions and does not reproduce the evidence.

## Supersession

**ADR-0017.** One sentence and one clause of ADR-0017's Decision are
superseded. Both sit under "The non-project-built runtime surface enters
scope with the fleet", and each is superseded **only as applied to the image
in Scope**.

**A**, the pin-and-mirror requirement:

> every image identity the selected runtime pulls is either project-built
> and published by this project's pipeline, or pinned by digest, mirrored
> and scanned before the runtime window opens

For the image in Scope, that obligation becomes the release pin, the
discovery window, the exact observed-image evaluation and the later-window
checks in the Decision.

**B**, the blocking clause that enforces A:

> An image identity that cannot be mirrored and pinned blocks the component
> that requires it

For the image in Scope, not being mirrored does not block on that ground
alone. HOLD and BLOCKED under this record take its place. The rest of that
sentence stands: "and that block is recorded rather than waived".

Between A and B sits one sentence that is **not** superseded: init-container
images are inside the rule. Nothing else in ADR-0017 is superseded, and every
other image class is unchanged by this record.

**ADR-0015.** ADR-0015 admits a measured artifact by its exact digest, on
the premise that the artifact measured before a window is the one that runs
in it. Three clauses bind that:
- the Admission rule for Development and validation roles, a "per-digest,
  window-bounded security exception";
- exception-contract field 2, "Exact linux/amd64 immutable digest the
  exception binds";
- binding rules 1 and 2: an exception is per-digest and "never inherited by
  another digest".

For the image in Scope, that premise is narrowed only in a bounded case:
- in one discovery window per exact pinned release;
- before any workload or GitOps validation;
- never in the Production Validation role.

In that case the artifact measured, and the digest any exception binds, is
the source-declared `linux/amd64` identity, because the exact running digest
cannot be known before the window. Whether it is the one that runs is
established only in the window, by the match rule, and a running identity
that fails the match rule is a HOLD.

Nothing else in ADR-0015 is narrowed:
- the fixed gate and the severities;
- the default HOLD;
- the full exception contract and every other binding rule, including
  rule 5's fresh evaluation, which the discovery window meets on the
  source-declared identity;
- necessity, currency and lowest debt;
- window-bound exceptions and disclosure;
- the Production Validation rule.

From the next window on, ADR-0015 applies to the exact observed identity
unchanged.

**ADR-0019.** ADR-0019 is not superseded. Its effect narrows for this one
image, because the ADR-0017 rule it keeps node/AMI images under is itself
narrowed here.
- The pre-window measurement found that the node/AMI mechanism exposes
  supported project control over this image: a custom AMI through
  `image_id`, or a containerd override through `user_data`.
- So, under ADR-0019's second condition, the image is outside the
  AWS-delivered class and would otherwise remain under ADR-0017.
- ADR-0019's measurement for any other node/AMI delivery remains owed and is
  not discharged by this record.

## Revisit Triggers

Revisit if:
- a discovery window shows a digest different from the source-declared one,
  a later window shows one different from the admitted one, or the digest
  cannot be observed;
- the exact observed image cannot be retrieved independently or evaluated
  under ADR-0015;
- AWS publishes authoritative per-release metadata for the baked sandbox
  digest, which would remove the need for detective discovery and move the
  exact evaluation before the first window;
- the AMI or node agent changes so that the sandbox image is pulled at node
  start rather than baked;
- AWS offers a supported sandbox override that needs no credentialed
  pre-pull, which would make option A cheap;
- a sandbox digest carries a fixable HIGH or CRITICAL finding and no newer
  release clears it;
- the node group changes AMI family, adopts a custom AMI, or adds a
  containerd override, any of which ends this record's scope;
- any other image is found delivered by the node/AMI mechanism.
