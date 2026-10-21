# ADR-0020: Control the AMI-baked Kubernetes sandbox image

Status: Accepted (2026-10-02); revised 2026-10-21, decision unchanged.

Narrowly replaces ADR-0017's pin/mirror and related blocking rules,
and ADR-0019's clauses preserving them, only for the image defined below.
ADR-0006 and ADR-0015 remain unchanged.

## Decision and scope

Keep the Kubernetes sandbox image baked into the EKS-optimized Amazon
Linux 2023 AMI used by the Dev node group.

Select the AMI through ami_type and an exact release_version, with no
custom AMI or containerd sandbox override. This keeps bootstrap with EKS.
A project-owned sandbox image would mean taking over node bootstrap through
a custom AMI or a containerd override with a credentialed pre-pull, adding a
new way for a node to fail to run pods, and nothing shows a mirrored pause
image would scan differently.

This decision covers only that sandbox image. It creates no general
equivalence between AMI pinning and image mirroring.

A release change requires a reviewed code change. Keep each release's
recorded outcome, including HOLD or BLOCKED.

ADR-0019's node/AMI control measurement remains required before the first
node-bearing window. The identity probe below does not discharge that
measurement or place this image in ADR-0019's AWS-delivered class.

## Establish identity once per release

Before the release's first node-bearing window:

1. Record the exact regional AMI ID from AWS's published parameter
   for the pinned release.
2. Launch one probe from that AMI outside any cluster. Read the baked
   image's records, recorded source and exported archive.
3. Record and re-hash the index, its single linux/amd64 manifest,
   config and layers from the stored bytes.
4. Retrieve the exact index by digest from the project region's AWS EKS
   image registry. Verify its hash and single linux/amd64 entry, and
   confirm that the manifest, config and layers match the probe.
5. Terminate the probe and verify cleanup before the runtime window.

The probe is valid only when all these conditions hold:

- The node agent's configuration step failed. No node configuration exists
  in user data or its drop-in directory; its run step and kubelet are inactive.
- That boot's containerd journal shows no pull and no creation or deletion
  of pause-named image records.
- The store contains exactly two pause-named records: the local tag and
  recorded source reference. Both point to the same index, with no
  @sha256: repository-digest record.
- The store and exported archive identify the same index.

No probe node joins a cluster. Recording identity does not grant security
admission. An invalid probe means HOLD; a release that cannot be probed
validly is BLOCKED.

## Evaluate before every node-bearing window

Retrieve the recorded artifact by digest and scan it fresh under
ADR-0015's unchanged gate with a current vulnerability database.
A previous scan or window decision cannot substitute for this evaluation.

Fixable HIGH or CRITICAL findings follow ADR-0015: HOLD by default,
with only its existing exception path and none in Production Validation.

An empty scan receives the classification
NOT-APPLICABLE-NO-ANALYZABLE-COMPONENTS only when all five conditions hold:

1. The scanned artifact matches the recorded immutable digest.
2. Its index, linux/amd64 manifest, config and layers match the probe.
3. Its connection to the pinned AMI is measured.
4. The scan is fresh for the window, uses the unchanged gate and a current
   database, and that database does not change during the scan.
5. An independent layer inventory finds no package database, language
   manifest, archive or embedded dependency metadata.

This classification means the scanner had nothing to evaluate. It is
neither a gate pass, security admission nor an ADR-0015 exception.

Running a window with this classification requires an explicit owner
disposition recorded before that particular Dev window opens. It cannot
carry into another window or apply to Production Validation. Without it,
the window stays closed.

Dependent public claims must carry the classification. Do not describe
the image as clean, vulnerability-free or security-gate-passed.
Any other empty scan, failed scan or unmet condition means HOLD.

## Check each node during the window

Immediately after each node joins, before workload or GitOps deployment:

- Confirm the node group's releaseVersion matches the pinned release.
- Bind each node to an instance belonging to that node group.
- Confirm the instance's EC2 image and the node's
  eks.amazonaws.com/nodegroup-image label both match the recorded AMI ID.
- Capture node.status.images as an observation.

Identity rests on the probe and each node's AMI binding.
node.status.images is not the identity authority. Record a missing digest
without inferring one. A reported digest for either probe-recorded name
must match the recorded index or linux/amd64 manifest; otherwise HOLD.

A plan containing no pods does not waive these checks. Measure whether
nodes joined and sandbox containers ran. If absence is not established,
treat the image as having run. Measured absence provides no security
admission or additional image-identity proof.

## HOLD, limitations and review

A failed required check means HOLD. Before a window, HOLD keeps it closed.
Inside a window, stop workload and GitOps validation; continue only to
capture evidence and tear down.

A release is BLOCKED when its baked identity cannot be measured or the
registry does not serve its exact digests. Record every outcome.

The project has no mirrored copy or pull-time control for this image.
Node checks bind the node to an AMI; they do not inspect the running
sandbox bytes. Registry retrieval supplies matching bytes for evaluation.
The no-pull startup behavior is source-derived, not runtime proof.

The probe does not establish a complete inventory of other AMI images.
An empty scan provides no vulnerability assessment of the pause binary.
Release pinning also freezes OS and kubelet patches until a reviewed update.

Revisit if identities differ, evidence cannot be reproduced, AWS provides
authoritative sandbox digests or a simpler supported override, startup
begins pulling the image, security findings or scanner coverage change,
or another AMI-delivered image is discovered. A custom AMI, different AMI
family or sandbox override ends this decision's scope.

Acceptance authorizes no probe, AWS mutation, runtime window or spending.
Existing owner authorization and cost controls remain required.
