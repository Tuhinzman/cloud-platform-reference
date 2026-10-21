# ADR-0009: Build and deploy workloads

Status: Accepted (2026-07-31); revised 2026-10-21, decision unchanged.

## What we will use

Keep three repositories with separate responsibilities:

- GitLab application repository: source, container definitions and CI.
- GitLab GitOps repository: environment configuration and image digests.
- GitHub reference repository: architecture, Terraform, documentation
  and sanitized evidence.

Use GitLab CI with shared pipeline definitions and per-service jobs.
Build changed services from source.

CI authenticates to AWS through OIDC and short-lived STS credentials.
Scope each role to its purpose, repository and branch. Do not use static
AWS keys or apply infrastructure changes from the delivery pipeline.

Use Amazon ECR with one Terraform-managed repository per owned service.
Use immutable tags derived from source commits and deploy by digest.
Build an image once and promote the same digest across environments,
with configuration supplied at runtime.

Use Helm with three values layers: base, environment and image digests.
Disable bundled observability in the base layer. Reuse the upstream
chart; fork only if required configuration or digest pinning cannot
be expressed.

Run one version-pinned Argo CD instance per environment cluster.
It pulls desired state only from the GitOps repository, continuously
reconciles it and corrects drift. Infrastructure, builds, promotion
decisions and secret values remain outside its responsibility.

## Rationale

Source, artifact production, desired state, reconciliation and evidence are
separate responsibilities that change at different rates; the tools can be
replaced without moving those boundaries. GitLab was chosen because the
owner's delivery practice already lives there, the credible platforms being
equivalent on OIDC federation and hosted runners. ECR keeps image pulls on
the account's existing access path instead of adding a third-party
dependency to every pod start. An image is built once and identified by
digest because a rebuild is a different artifact, and the checks that passed
belong to one binary image. Promotion is a Git change because approval,
audit trail and rollback are properties Git already has, and Argo CD runs
per cluster because a central instance would hold write access across the
environment boundaries ADR-0004 and ADR-0007 establish.

## Delivery and validation rules

Before publication, require linting, build, available service tests,
container startup and health checks. Record the coverage actually run.

Trivy blocks fixable HIGH and CRITICAL findings and generates an SBOM
for every published artifact. Report unfixed findings. Run separate
secret detection. Scanning exceptions need written justification
and expiry.

The intended promotion flow is:

- Dev: an application main-branch merge builds, verifies and publishes
  the image, then automatically updates the Dev digest reference.
- Validation: promote the same digest through a GitOps merge request.
- Production Validation: the owner approves and merges its promotion
  request, providing the recorded approval.

Use Kubernetes rolling updates. Rollback is a Git revert of the digest
reference followed by reconciliation, rather than Helm rollback.
Validate one rollback exercise before declaring this implementation
complete. The previous version must support the current data schema,
or a manual recovery path must be documented.

Infrastructure and data recovery follow ADR-0003 and ADR-0011.
Demonstrate Argo CD bootstrap and reconciliation in a fresh ephemeral
environment.

Retain the source commit, pipeline and test results, scans, SBOM,
registry digest, GitOps change, reconciliation revision and running-image
match. Include functional checks and the final browser-accessible check.
Capture required evidence before teardown.

ECR survives environment teardown. Scope pull access by environment,
bound retention with lifecycle policies and track storage and CI costs.
Document recovery by rebuilding from source and final removal once
no environment references the images. Declare retained ECR resources
in teardown reports.

Image signing, attestations and a progressive delivery controller remain
deferred. Rolling updates do not prove routing to a chosen version.

Revisit if chart limitations, bootstrap reliability, delivery costs,
provenance verification or traffic-routing needs require a change.
