# ADR-0020: Govern the AMI-baked Kubernetes sandbox image by release pin and identity controls

## Status

Proposed (2026-09-27)

Narrowly supersedes one sentence and one clause of ADR-0017's Decision,
named exactly in **Supersession** below. The supersession is bounded to one
image: the Kubernetes pod sandbox image baked into the EKS-optimized Amazon
Linux 2023 AMI that the dev node group selects by a pinned release.
Everything else in ADR-0017 remains Accepted and authoritative. ADR-0006,
ADR-0015 and ADR-0019 are unchanged.

## Context

ADR-0017 has two requirements that matter here:
- every image identity the selected runtime pulls must be project-built, or
  pinned by digest, mirrored and scanned before the runtime window opens;
- a component whose image cannot be mirrored and pinned is blocked.

ADR-0019 keeps images delivered by the EKS-managed node/AMI mechanism under
that rule until the mechanism is measured.

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

ADR-0017's revisit trigger for an unmirrorable surface is not literally met.
This image can be mirrored, but only by taking over node bootstrap, which
this record declines for the reasons below. Without this record, ADR-0017's
blocking clause would block every component that runs a pod.

## Considered Options

| Option | Assessment | Outcome |
|---|---|---|
| A. Project-owned sandbox: mirror a pause image to the platform registry, pin it by digest, scan it, and point containerd at it through launch-template user data with a credentialed pre-pull, or through a custom AMI | Satisfies ADR-0017 literally, but takes over the node bootstrap contract that the launch template deliberately leaves to EKS. Adds a foundation registry repository, user data, and a pre-pull step that must finish before the first pod sandbox; if it fails, the node cannot run pods. None of it has been measured here | Rejected |
| B. Keep the AWS-baked sandbox image, fixed by a pinned AMI release, under the compensating controls below | Keeps the node bootstrap contract with EKS and adds no join-time dependency. The baked digest is known only from the first node that runs the release, so the identity control for it is detective | Selected |

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

**ADR-0015 applies in full.** The sandbox image is a non-workload runtime
component that the platform operates on every node. So the fixed gate, fresh
evaluation for each window, the exception contract and the absence of any
Production Validation exception all apply unchanged. A fixable HIGH or
CRITICAL finding holds by default.

**Compensating controls.**

1. **Pin the release.** Pin the node group's `release_version` to one exact
   AMI release. A change of release is a reviewed code change, and it resets
   controls 2 to 6 for the new release.
2. **Scan the declared identity before the first window.** Before the first
   node-bearing window on a release, resolve the source-declared sandbox
   identity for that release: the sandbox image reference in the AMI build
   source at the release tag. Resolve it to its digest and its `linux/amd64`
   child digest, and scan that child under ADR-0015.
3. **Capture the baked digest in the first window.** In the first
   node-bearing window on a release, capture `node.status.images` from every
   node after it joins and before any workload or GitOps deployment. Read the
   digest recorded for the image carrying the sandbox tag. This observation
   is **detective** for the exact baked digest: it reports what the AMI
   carries once a node exists, and nothing before that window establishes
   the baked bytes.
4. **Match rule.** The observed digest matches only when every node reports
   `linux` and `amd64` and the digest equals either:
   - the pre-window resolved `linux/amd64` child; or
   - the resolved index whose single `linux/amd64` entry is that child.

   An index digest content-addresses its manifest list. So an index whose only
   `linux/amd64` entry is the scanned child fixes the bytes a `linux/amd64`
   node runs. Anything else is a mismatch, including a different index with
   the same child.
5. **Admit the observed identity.** When the first observation matches,
   record the observed digest and, where it is an index, its single
   `linux/amd64` child. Scan that child under ADR-0015. Once admitted, it is
   the sandbox identity for the pinned release.

   A first-window mismatch is a HOLD for that window. The observed digest is
   recorded and scanned, but it becomes the admitted identity only by an
   explicit owner decision recorded under the revisit trigger. Until then the
   release stays on HOLD.
6. **Check every later window.** Before every later window on the release,
   scan the admitted child again under ADR-0015. In the window, every node
   must run the pinned release: the node group's `releaseVersion` must equal
   it, and each node's `eks.amazonaws.com/nodegroup-image` label must equal
   the pinned release's AMI ID for the region. Every node must also report
   the admitted sandbox digest, captured at the same point as control 3.
7. **No equivalence by analogy.** No other image and no other AMI is governed
   by analogy. Pinning an AMI release is not mirroring, and this record
   creates no general AMI-mirror equivalence.

**Ordering.** In any window, workload and GitOps validation does not start
until control 4 has passed (first window on a release) or control 6 has
passed (every later window).

**Failure and HOLD behaviour.** Each of the following is a HOLD:
- the source-declared identity cannot be resolved or scanned before the
  window;
- the observed sandbox digest does not match (control 4 or control 6);
- the sandbox tag is absent, or appears without a digest, in
  `node.status.images`;
- the node group's `releaseVersion`, or a node's `nodegroup-image` label,
  differs from the pinned release;
- the sandbox image holds under ADR-0015 without an approved exception.

A HOLD stops workload and GitOps validation in that window. The window
continues only to capture evidence and tear down. A HOLD is recorded, never
waived, and a changed or unobservable identity is never accepted by
inference.

**Declared limitation.** For this image the project has no pull-time control
and no project-owned copy.
- The identity control is detective, not preventive. The baked digest is
  unknown before the first window on a release, and that window runs pods on
  the image before the comparison is made.
- The source-declared reference is a tag, resolved when the check runs,
  which is later than the AMI build. It may have moved since, which fails
  closed as a HOLD.
- It is not yet established that `node.status.images` exposes a digest for
  the baked image. An image pulled and retagged by the build may be reported
  by tag only, which would HOLD the first window.
- The kubelet reports a bounded number of images, largest first. That is why
  the capture is taken before any workload.
- Pinning the release also freezes the node operating system and kubelet
  patch level until a reviewed change moves it.

## Consequences

Gained:
- node image selection that is fixed and reviewable, rather than whatever
  release AWS recommends on the day of the apply;
- no project-owned node bootstrap and no join-time registry dependency;
- a sandbox identity the project observes, records and scans instead of
  assuming.

Paid for:
- one node-bearing window per release whose sandbox identity is established
  only during that window;
- a scan of the source-declared identity before it, and of the admitted
  child before every later window;
- a HOLD whenever the observation disagrees with the declaration, or the
  digest cannot be read.

Not claimed:
- that the sandbox image is project-built, mirrored, or under pull-time
  project control;
- that the source-declared identity equals the baked one; the first window
  decides that;
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

One sentence and one clause of ADR-0017's Decision are superseded. Both sit
under "The non-project-built runtime surface enters scope with the fleet",
and each is superseded **only as applied to the image in Scope**.

**A**, the pin-and-mirror requirement:

> every image identity the selected runtime pulls is either project-built
> and published by this project's pipeline, or pinned by digest, mirrored
> and scanned before the runtime window opens

For the image in Scope, that obligation becomes the seven compensating
controls above.

**B**, the blocking clause that enforces A:

> An image identity that cannot be mirrored and pinned blocks the component
> that requires it

For the image in Scope, not being mirrored does not block on that ground
alone. The controls govern it instead, and a mismatched or unobservable
identity remains a HOLD. The rest of that sentence stands: "and that block
is recorded rather than waived". Every disposition under this record is
recorded.

Between A and B sits one sentence that is **not** superseded: init-container
images are inside the rule. Nothing else in ADR-0017 is superseded.

ADR-0019 is not superseded, but its effect narrows for this one image,
because the ADR-0017 rule it keeps node/AMI images under is itself narrowed
here.
- The pre-window measurement found that the node/AMI mechanism exposes
  supported project control over this image: a custom AMI through
  `image_id`, or a containerd override through `user_data`.
- So, under ADR-0019's second condition, the image is outside the
  AWS-delivered class and would otherwise remain under ADR-0017.
- ADR-0019's measurement for any other node/AMI delivery remains owed and
  is not discharged by this record.

## Revisit Triggers

Revisit if:
- the first observation shows a sandbox digest different from the declared
  one, any later window shows one different from the admitted one, or the
  digest cannot be observed;
- AWS publishes the baked sandbox digest per release, which would move
  control 3 before the window;
- the AMI or node agent changes so that the sandbox image is pulled at node
  start rather than baked;
- AWS offers a supported sandbox override that needs no credentialed
  pre-pull, which would make option A cheap;
- a sandbox digest carries a fixable HIGH or CRITICAL finding and no newer
  release clears it;
- the node group changes AMI family, adopts a custom AMI, or adds a
  containerd override, any of which ends this record's scope;
- any other image is found delivered by the node/AMI mechanism.
