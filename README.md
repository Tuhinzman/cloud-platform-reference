# Cloud Platform Reference

A production-inspired cloud platform, designed and documented from first
principles, and implemented step by step with evidence.

## Why This Project Exists

Finished infrastructure rarely explains itself. Why each component exists,
which alternatives were rejected, what the operational tradeoffs were: that
reasoning usually disappears once something works.

This repository keeps the reasoning. Each architectural decision is written
down with its context, alternatives, and tradeoffs, and no implementation
claim stands without captured evidence.

## Who This Is For

- **Recruiters and hiring managers**: a quick read on scope, engineering
  decisions, and engineering quality.
- **Senior engineers**: architecture, decision records, and operational
  evidence as they are added, in enough depth to judge the work.
- **Engineers learning platform work**: the reasoning behind each choice,
  not just the commands.

## How This Repository Is Organized

The foundation documents are the place to start:

- [Project Charter](docs/project-charter.md): why the project exists and what governs it
- [Platform Capability Model](docs/capability-model.md): what the platform must be able to do
- [Requirements Baseline](docs/requirements-baseline.md): the measurable conditions the platform must satisfy
- [System Context](docs/system-context.md): who interacts with the platform and where its boundary sits
- [Logical Architecture](docs/logical-architecture.md): how the platform decomposes into logical responsibilities and how they interact
- [Architecture Baseline](docs/architecture-baseline.md): the two platform-wide facts no single decision owns, which are why the platform standardizes on one region and which resources survive environment teardown

### Diagrams

Four views render the same architecture at different depths. Every component carries a status
badge scoped to what current evidence supports, so a reader can tell accepted architecture from
exercised implementation without reading the records first. All four are exported from one
editable source, [aws-platform-reference-architecture.drawio](docs/diagrams/aws-platform-reference-architecture.drawio).

- [Full Flow, High Level](docs/diagrams/platform-high-level-flow.svg): the whole platform on one page, with the current implementation status stated plainly
- [Control, Delivery and GitOps](docs/diagrams/control-delivery-gitops.svg): source to runtime, the CI federation path, and human infrastructure control
- [AWS Platform and Request Flow](docs/diagrams/aws-platform-request-flow.svg): the account, the per-environment network, and what is retained across teardown
- [Identity, Secrets, Observability, Evidence and Lifecycle](docs/diagrams/identity-observability-evidence-lifecycle.svg): the four platform concerns and what each has proven

Every significant choice is recorded in [docs/decisions](docs/decisions/), one decision per
record, each with its alternatives, consequences, and a revisit trigger. All fifteen are
accepted.

| Record | Decision |
|---|---|
| [ADR-0001](docs/decisions/0001-adopt-an-architecture-first-evidence-backed-delivery-method.md) | Architecture-first, evidence-backed delivery method. The working method itself, decided before any technology. |
| [ADR-0002](docs/decisions/0002-select-aws-as-the-cloud-provider.md) | AWS as the cloud provider, deferring every service and implementation choice. |
| [ADR-0003](docs/decisions/0003-adopt-terraform-and-remote-state-management.md) | Terraform with per-environment remote state, and a reviewed plan on every change. |
| [ADR-0004](docs/decisions/0004-define-the-environment-and-account-topology.md) | One AWS account, three environment roles, and a declared promotion order. |
| [ADR-0005](docs/decisions/0005-adopt-centralized-identity-and-least-privilege-access.md) | Central federated sign-in and no long-lived human credential anywhere. |
| [ADR-0006](docs/decisions/0006-adopt-amazon-eks-as-the-workload-runtime.md) | Amazon EKS as the runtime, one cluster per active environment. |
| [ADR-0007](docs/decisions/0007-define-networking-and-traffic-boundaries.md) | One VPC per environment, private nodes, one managed public entry with TLS. |
| [ADR-0008](docs/decisions/0008-define-the-secrets-and-workload-identity-model.md) | Workload identity per service and one system of record for secrets. |
| [ADR-0009](docs/decisions/0009-define-the-software-delivery-model.md) | Build once, promote the same digest, and treat promotion and rollback as Git changes. |
| [ADR-0010](docs/decisions/0010-define-the-observability-model.md) | Per-environment telemetry with one correlation contract across platform and workload. |
| [ADR-0011](docs/decisions/0011-define-the-backup-and-recovery-model.md) | Rebuild first, back up only what has no other source, and prove recovery by exercise. |
| [ADR-0012](docs/decisions/0012-formalize-the-reference-workload.md) | The reference workload as an instrument for validating the platform, not a deliverable. |
| [ADR-0013](docs/decisions/0013-define-operations-and-cost-guardrails.md) | Who operates the platform and what it may cost. A three-level monthly budget, one create-to-cleanup lifecycle for every environment, and a development environment that is recreated on demand rather than left running. |
| [ADR-0014](docs/decisions/0014-expand-the-validated-implementation-workload-scope.md) | Widens the implemented workload to the complete justified application fleet, so that delivery, reconciliation, telemetry attribution, and teardown are exercised across breadth rather than a handful of services. Supersedes only the service-count limit in ADR-0012. |
| [ADR-0015](docs/decisions/0015-define-security-admission-and-exception-governance-for-platform-managed-runtime-components.md) | Security admission and exception governance for platform-managed runtime components. A fixed admission gate evaluated per component, per digest and per runtime window, with every exception written down, justified and expiring with the window that used it. |

ADR-0013 also supersedes part of what came before it. The assumption that a development
environment runs continuously originates in ADR-0004 and is restated in ADR-0006 and
ADR-0007. Accepted records are never edited here, so ADR-0013 is the single place that
states how far that supersession reaches and what in those three records is untouched.

Infrastructure definitions live in [terraform/](terraform/), one directory per
configuration root. Each root has its own README covering what it creates, what it
deliberately does not, and what has been validated against AWS.

Each platform topic follows the same documentation flow:

Why → Requirements → Architecture → Decision → Diagram → Implementation →
Validation → Evidence → Lessons Learned

## Current Status

Architecture planning is complete: the foundation documents are in place and every
decision record listed above is accepted. Implementation is under way and has passed
first reconciliation. Four Dev runtime windows have been opened, validated, evidenced and
destroyed. In the most recent two, six Argo CD applications reconciled Synced and Healthy
across the workload and its observability stack, a deliberately induced fault was applied
and a governed restore returned the tree to its anchor, and each window closed with a
zero-residual resource census.

The platform the records describe is one AWS account in `us-east-1` running three
environment roles, each with its own VPC, its own EKS cluster, and its own telemetry,
built from version-controlled Terraform and reached through one managed HTTPS entry
point. Application change moves as an immutable artifact promoted by digest through Git,
and recovery is rebuilt from authoritative sources rather than restored, with backup
reserved for the four things that have no other source.

Two properties are worth knowing before reading further, because they shape everything
else. Cost is treated as an engineering constraint with a stated monthly target, a review
threshold, and a ceiling that stops work rather than a single number nobody honors. And
no environment runtime is left running between approved windows: for each of the three
roles the runtime is created for an approved window, validated, evidenced, destroyed, and
verified clean. Both are decided in
[ADR-0013](docs/decisions/0013-define-operations-and-cost-guardrails.md), and the second
is why the answer to what exists right now has two halves.

What persists is the Terraform state backend and the durable evidence destination, which
outlive every environment, together with the retained part of the Dev environment: its
network baseline and the identity, secret, and configuration resources scoped to that
environment. What is not running is the billable Dev runtime, meaning the EKS control
plane, the managed node group, and the NAT gateway. Those are declared in Terraform,
created inside an approved window, and destroyed when it closes. They have been built and
torn down more than once, and the definitions that rebuild them are in this repository.

The secrets and workload-identity path has been exercised, with two attributions left
open. A secret was rotated at its source and observed reaching a running consumer without
a restart, and the paired negative test confirmed that an ordinary pod could not obtain
node credentials through instance metadata. On the most recent runtime the controller that
reads the secret store started with the EKS Pod Identity credential path injected, and the
secret it was asked to synchronize arrived in the cluster. Neither of those observations
settles attribution. That the controller authenticated to AWS as its own Pod Identity role,
and that one identified read in the audit trail is the read that served that
synchronization, are unproven and are not claimed here.

The build and delivery path is validated for the services that carry it, checkout first
and since then others in the fleet. A service's pipeline runs on
hosted runners, executes the service's own tests, builds the image, scans it before
anything is published, generates a software bill of materials, and starts the built
container to confirm it comes up and accepts a connection on its port. The pipeline
holds no cloud credential: it exchanges a short-lived identity token for temporary
credentials at the moment it needs them, and the image is published to the registry by
digest. That digest was read back from the registry
independently to confirm the published artifact is the one the pipeline built. The image
carries no fixable high or critical findings, and that was reached by updating the
toolchain and dependencies rather than by adding exceptions to the security gate. That
artifact is the one the platform later deployed.

The workload scope the platform is built toward is the complete justified application
fleet rather than a handful of services, so that one delivery pipeline, one reconciliation
model, and one teardown are exercised across breadth. That is decided in
[ADR-0014](docs/decisions/0014-expand-the-validated-implementation-workload-scope.md),
which changed no requirement and no other accepted record. It sets the approved scope. It
is not a description of what has been deployed.

What has been deployed is a slice of that scope. On the most recent Dev runtime windows,
Argo CD reconciled against the private GitOps repository and applied six applications: a
workload slice of three services and the four-component observability stack that observes
them, each reaching Synced and Healthy. Pods ran and stayed ready, and the image
identifier read back from each running container matched by digest the artifact its
pipeline had published, which is what joins the build path to the runtime. The rest of the
fleet was not deployed, so nothing here says how the platform behaves under the full
application.

Those runtimes are gone. Terraform created the runtime resources to open each window and
destroyed the same set to close it, the plan taken afterwards converged on rebuilding
exactly those resources, and a resource census confirmed nothing of the runtime class was
left behind. No environment runtime is live as this is written.

Reconciliation working is easy to read as more than it is, so the boundary is worth
stating plainly, in the vocabulary this repository uses throughout: IMPLEMENTED, PROVEN,
PARTIALLY PROVEN, NOT PROVEN, DECLARED LIMITATION.

Observability is IMPLEMENTED and PARTIALLY PROVEN at runtime. The collector gateway, the
metric, log and trace stores, the operational views, the alert rules, the notification
destination and the retention configuration all run from version-controlled desired state.
PROVEN on EKS: Kubernetes identity survives the full collection path on metrics, logs and
traces; for one service the deployed digest reconciles across four independent signals,
with a wrong-digest control that fires; and one deliberately induced workload fault was
followed from its alert through workload and platform signals to root cause, to a governed
restore, to verified recovery. That is the standing investigation exercise ADR-0010
requires, and it is discharged.

Two facts about alert delivery are kept separate because they are separate. The delivery
mechanism is PROVEN end to end: an alert reached the engineer through the declared
channel, using workload identity to publish to the notification service, with receipt
attested. Separately, a refinement added after the criterion was frozen asserted an exact
notification cardinality that runtime measurement then falsified; that assumption is
withdrawn. The path worked. The over-specific assumption about what it would emit did not.

DECLARED LIMITATIONS, stated rather than smoothed over: the trace-store selection ADR-0010
defers to implementation evidence is still open, and the trace-to-logs traversal through
the operational view is NOT PROVEN, because the log-store datasource plugin unregistered
itself at runtime and the correlation evidence was collected through the store APIs
instead; telemetry enrichment is not uniform, so one service's logs do not carry the
container-level identity the digest reconciliation needs and another was not on the
exercised request path; retention is proven as combined evidence, meaning the deletion
mechanism was measured and the running configuration was read back, not that object
deletion was observed on EKS; and during one continuous fault the alert transitioned
several times and produced six notifications in roughly nineteen minutes, with the exact
mechanism not conclusively isolated.

Still NOT PROVEN, each an obligation its own decision record carries: the full application
fleet has not been deployed, rollback has not been exercised, promotion between
environments has not been performed, and the Validation and Production-Validation
environments have not been built at all.

Evidence exists for what has been validated, and it is not published here. Raw evidence
is retained outside this repository, and the sanitized subset that will support the
claims in these pages goes through its own review rather than accumulating as
implementation proceeds. Read every implementation statement in this repository as scoped
to what its own stated validation covers. None of it is a production-readiness claim: the
[Project Charter](docs/project-charter.md) defines this as a production-inspired platform
rather than a hosted service, and the limitations each decision record states still
stand.

## License

Apache License 2.0. See [LICENSE](LICENSE).
