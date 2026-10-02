# ADR-0020: Govern the AMI-baked Kubernetes sandbox image by release pin and identity controls

## Status

Proposed (2026-09-27, revised 2026-10-02)

This record makes one narrow change to an Accepted decision, named exactly in
**Supersession** below and bounded to one image: the Kubernetes pod sandbox
image baked into the EKS-optimized Amazon Linux 2023 AMI that the dev node
group selects by a pinned release. It supersedes one sentence and one clause of
ADR-0017's Decision for that image.

Everything else in ADR-0017 remains Accepted and authoritative. ADR-0006,
ADR-0015 and ADR-0019 are unchanged.

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

Two measurements, made before any node-bearing window and with no node joining
a cluster, established the following.

A read-only control-surface measurement, from the provider schema, AWS's
published release parameters, the AMI metadata and the AMI's public build
source:

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

A pre-window probe and two registry retrievals:

- **Measured baked identity.** One instance was launched from the AMI of
  release `1.36.4-20260923` outside any cluster, with the kubelet not running,
  and the baked image was read from its containerd store and exported archive:
  - its record is `localhost/kubernetes/pause:latest`;
  - its recorded source is `eks/pause:3.10` in the AWS-owned EKS image
    registry, not the build template's default,
    `public.ecr.aws/eks-distro/kubernetes/pause:3.10`, whose digest was never
    resolved;
  - the archive's index is
    `sha256:76040a49ba6fc50056e8ff0a6c276baeb633fb12685540aaea884b717f31eddb`,
    with exactly one `linux/amd64` manifest,
    `sha256:7f2bdf4f52f04199c2fc9eec14cc4593b327deedbad2b9a399f127bb63a69577`,
    config
    `sha256:c1e1b3bcc801fdaf723cb41eb5ec402f294c9d84bdbc0dcf175d68c13a6865b9`
    and one layer,
    `sha256:6ea5d75b35fc7de260b98abfe408883d215ad7c91588fc40ce603d40878c7951`,
    each re-hashed from the stored bytes;
  - the store holds no digest-named record for the image.
- **Independent retrieval.** The same index was retrieved by digest from the
  AWS-owned EKS image registry in us-east-1 in two separate sessions. Each time
  it recomputed from its bytes, and its single `linux/amd64` entry, config and
  layer equalled the probe's.
- **Evaluation.** The retrieved artifact was scanned with ADR-0015's fixed gate
  on a fresh vulnerability database. The scanner found nothing it could
  analyze: the single layer holds one ELF file, `pause`, and no package
  database, language manifest, archive or embedded dependency metadata. The
  gate reported no finding. That records the absence of an analyzable surface,
  not the absence of vulnerabilities.

No node has run this AMI in this project. That node startup uses the baked
image and pulls no other is source-derived, not measured.

So the exact baked identity of a pinned release can be measured, retrieved and
evaluated under ADR-0015 before any node of the release runs. What cannot be
measured before a node exists is how the kubelet reports the image, and with
no digest-named record in the store, `node.status.images` may not expose its
digest.

ADR-0017's revisit trigger for an unmirrorable surface is not literally met.
This image can be mirrored, but only by taking over node bootstrap, which
this record declines for the reasons below. Without this record, ADR-0017's
blocking clause would block every component that runs a pod.

## Considered Options

| Option | Assessment | Outcome |
|---|---|---|
| A. Project-owned sandbox: mirror a pause image to the platform registry, pin it by digest, scan it, and point containerd at it through launch-template user data with a credentialed pre-pull, or through a custom AMI | Satisfies ADR-0017 and ADR-0015 literally, but takes over the node bootstrap contract that the launch template deliberately leaves to EKS. Adds a foundation registry repository, user data, and a pre-pull step that must finish before the first pod sandbox; if it fails, the node cannot run pods. None of it has been measured here | Rejected |
| B. Keep the AWS-baked sandbox image, fixed by a pinned AMI release, with its exact identity measured by a pre-window probe, retrieved by digest and evaluated under ADR-0015 before every window | Keeps the node bootstrap contract with EKS and adds no join-time dependency. The identity is known before any node of the release runs, and in the window each node is bound to the recorded AMI and release that carry it | Selected |
| C. Keep the AWS-baked sandbox image with one discovery window per release: evaluate the build source's declared image before the window and observe the baked digest in it | The probe recorded a different source than the build source declares, and the two were never shown to be the same artifact. Observing the baked digest in the window depends on `node.status.images` exposing it, which is not established. It also needed a narrowing of ADR-0015 that the probe makes unnecessary | Rejected |

## Decision

**Keep the AWS-baked sandbox image of the pinned EKS-optimized AMI** for the
dev node group, governed by this record instead of by ADR-0017's pin, mirror
and block rule.

**Rationale.**
- The image is baked into an immutable AMI and, on the build path shown by
  its source, is not pulled during node startup.
- `release_version` pins the exact AMI release, and with it the image.
- Its exact identity is measured, retrieved and evaluated before any node of
  the release runs.
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
platform operates on every node, so ADR-0015 governs it, unchanged. **This
record creates no new security exception path and narrows nothing in
ADR-0015.** Any fixable HIGH or CRITICAL finding holds by default and is
admissible only through ADR-0015's full exception contract, and never in the
Production Validation role.

**Release pin.** The node group's `release_version` is pinned to one exact
AMI release. A change of release is a reviewed code change. A release with no
measured identity starts with the pre-window identity below, and every release
keeps its recorded outcome, including BLOCKED.

**Pre-window identity, once per release.** Before the first node-bearing
window on a pinned release, with no node of that release running:
1. Record the release's exact immutable AMI ID for the region, from AWS's
   published parameter for that release.
2. Launch one probe instance from that AMI ID, outside any cluster, and read
   the baked sandbox image's record, its recorded source and its exported
   archive.
3. Record the index digest, the single `linux/amd64` manifest, its config and
   its layers, each re-hashed from the stored bytes.
4. Retrieve that exact index independently by digest from the AWS-owned EKS
   image registry, and confirm that it recomputes from its bytes, has exactly
   one `linux/amd64` entry, and that the entry, its config and its layers
   equal the probe's.

The retrieved identity is the admitted identity for the release. No node joins
a cluster during the probe, and the probe instance is terminated and censused
before any node-bearing window.

**Before every window.** The admitted identity is evaluated fresh under
ADR-0015's fixed gate, on a vulnerability database current for that window,
from bytes retrieved by digest. A prior evaluation, and a prior window's
disposition, are never evidence for a later window.

**Empty-scan disposition.** The fixed gate may find no analyzable component in
this image. The result is classified NOT-APPLICABLE-NO-ANALYZABLE-COMPONENTS
only when all five of these hold:
1. the scanned artifact is the admitted identity, by immutable digest;
2. its index, `linux/amd64` manifest, config and layers equal the probe's;
3. its provenance to the pinned AMI is measured;
4. the scan ran fresh for the window, with the fixed gate unchanged and a
   current database that did not change during the scan;
5. an independent inventory of its layers finds no package database, language
   manifest, archive or embedded dependency metadata.

NOT-APPLICABLE-NO-ANALYZABLE-COMPONENTS is a classification, not a gate pass. It
records that the gate had nothing to evaluate. It is never described as clean,
vulnerability-free or security-gate-passed, it is neither a gate admission nor
an ADR-0015 exception, and no claim that depends on the sandbox image says
otherwise. Whether a window may run with an image carrying
it is an owner disposition recorded for that window alone; this record does
not make that disposition and no window inherits it. Any other empty scan, an
unmet condition or a failed scan is a HOLD.

**In-window node checks.** Immediately after each node joins, and before any
workload or GitOps deployment:
- confirm that the node group's `releaseVersion` equals the pinned release;
- confirm that every node's `eks.amazonaws.com/nodegroup-image` label equals
  the recorded AMI ID;
- capture `node.status.images` as an observation.

The sandbox identity rests on the probe, the retrieval and the immutable AMI
each node is bound to. `node.status.images` is recorded but is not the sole
identity authority: if it reports no digest for the sandbox image, that is
recorded, never inferred. If it reports, for the sandbox image's tag, a digest
that is neither the admitted index nor its `linux/amd64` entry, that is a
mismatch.

Workload and GitOps validation does not start until those checks pass.

**Windows with no pod.** A node-bearing window in which no pod runs executes no
sandbox container. Its pre-window evaluation and in-window node checks still
apply, but the non-execution is evidence of nothing about the image: no runtime
admission, and no identity beyond each node's binding to the recorded AMI, is
inferred from it.

**No equivalence by analogy.** No other image and no other AMI is governed by
analogy. Pinning an AMI release is not mirroring, and this record creates no
general AMI-mirror equivalence.

**HOLD and BLOCKED.** Each of the following is a HOLD:
- the admitted identity cannot be retrieved, verified or evaluated before a
  window;
- the sandbox image holds under ADR-0015 without an approved exception, or an
  empty scan of it is not classified as above;
- the node group's `releaseVersion` differs from the pinned release, or a
  node's AMI label differs from the recorded AMI ID;
- `node.status.images` reports a mismatching digest for the sandbox image's
  tag.

A HOLD before a window keeps it closed. A HOLD inside a window stops workload
and GitOps validation, and the window continues only to capture evidence and
tear down. A release whose baked identity cannot be measured, or whose exact
bytes cannot be retrieved and verified, is BLOCKED. Every HOLD and BLOCKED
outcome is recorded, never waived, and never resolved by inference.

**Declared limitation.** For this image the project has no pull-time control
and no project-owned copy.
- The in-window identity control is detective and indirect. It binds each node
  to the AMI whose baked image was measured; it does not read the bytes the
  runtime uses.
- It is not established that `node.status.images` exposes a digest for the
  baked image.
- That node startup uses the baked image and pulls no other is source-derived,
  not measured.
- The scanner finds no analyzable component in this image, so the gate result
  carries no information about vulnerabilities in the `pause` binary.
- The kubelet reports a bounded number of images, largest first. That is why
  the capture is taken as each node joins.
- Pinning the release also freezes the node operating system and kubelet
  patch level until a reviewed change moves it.

## Consequences

Gained:
- node image selection that is fixed and reviewable, rather than whatever
  release AWS recommends on the day of the apply;
- no project-owned node bootstrap and no join-time registry dependency;
- a sandbox identity measured, retrieved and evaluated before any node of the
  release runs, instead of assumed.

Paid for:
- one probe instance per release before its first node-bearing window;
- a fresh evaluation of the admitted identity before every window;
- a release that cannot be used if its baked identity cannot be measured,
  retrieved and verified.

Not claimed:
- that the sandbox image is project-built, mirrored, or under pull-time
  project control;
- that the empty scan shows the image to be free of vulnerabilities, or that
  the gate passed;
- that `node.status.images` exposes the sandbox digest;
- that any node has run this AMI; no node-bearing runtime has happened under
  this record at proposal;
- that this image belongs to ADR-0019's AWS-delivered class.

## Evidence

Measurements retained as evidence:
- a read-only control-surface measurement on 2026-09-27, covering the pinned
  provider schema, AWS's published Kubernetes 1.36 Amazon Linux 2023 release
  parameters, the metadata of the AMI for release `1.36.4-20260923`, and the
  AMI's public build source at tag `v20260923`, with each file hash-matched to
  its Git blob;
- a pre-window probe on 2026-10-01: one instance launched from that AMI
  outside any cluster, read and terminated, with its security group and volume
  removed and a clean census;
- two independent retrievals of the probed identity from the AWS-owned EKS
  image registry on 2026-10-01, each followed by a fixed-gate scan on a fresh
  database.

No node joined a cluster. This record states the conclusions and does not
reproduce the evidence.

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
pre-window identity, the per-window evaluation and the in-window node checks in
the Decision.

**B**, the blocking clause that enforces A:

> An image identity that cannot be mirrored and pinned blocks the component
> that requires it

For the image in Scope, not being mirrored does not block on that ground
alone. HOLD and BLOCKED under this record take its place. The rest of that
sentence stands: "and that block is recorded rather than waived".

Between A and B sits one sentence that is **not** superseded: init-container
images are inside the rule. Nothing else in ADR-0017 is superseded, and every
other image class is unchanged by this record.

**ADR-0015.** ADR-0015 is not superseded, narrowed or reinterpreted by this
record. It applies to the image in Scope unchanged, to its exact admitted
identity, fresh before every window.

**ADR-0019.** ADR-0019 is not superseded. Its effect narrows for this one
image, because the ADR-0017 rule it keeps node/AMI images under is itself
narrowed here.
- The control-surface measurement found that the node/AMI mechanism exposes
  supported project control over this image: a custom AMI through
  `image_id`, or a containerd override through `user_data`.
- So, under ADR-0019's second condition, the image is outside the
  AWS-delivered class and would otherwise remain under ADR-0017.
- ADR-0019's measurement for any other node/AMI delivery remains owed and is
  not discharged by this record.

## Revisit Triggers

Revisit if:
- a node reports, for the sandbox image's tag, a digest different from the
  admitted identity, or runs an AMI other than the recorded one;
- the baked identity of a release cannot be measured, or its exact bytes
  cannot be retrieved and verified;
- AWS publishes authoritative per-release metadata for the baked sandbox
  digest, which would replace the probe;
- the AMI or node agent changes so that the sandbox image is pulled at node
  start rather than baked;
- AWS offers a supported sandbox override that needs no credentialed
  pre-pull, which would make option A cheap;
- a sandbox digest carries a fixable HIGH or CRITICAL finding and no newer
  release clears it;
- the scanner begins to report analyzable components for the image, or the
  gate definition changes;
- the node group changes AMI family, adopts a custom AMI, or adds a
  containerd override, any of which ends this record's scope;
- any other image is found delivered by the node/AMI mechanism.
