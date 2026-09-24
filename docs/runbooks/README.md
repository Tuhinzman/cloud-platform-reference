# Runbooks

## Scope

These runbooks are the operating procedures for the platform, written for an engineer who did not
build it. The suite grows in passes. This first pass covers steps 1 to 4 of
[Reproducing the Platform](../../README.md#reproducing-the-platform): the state backend, the
persistent foundations with the public DNS zone and the certificate, the Dev network's retained
baseline and the Dev datastore. It also covers the operator access, cost and evidence operations
around those steps.

Following this pass ends at a built datastore, not a running cluster. These are outside it:

- Runtime windows, which create the EKS cluster, its nodes and the NAT gateway on top of the
  retained baseline, exercise them and destroy them at close. The windows that ran, their teardown
  and their residual checks are summarized in [Runtime Validation](../validation/runtime-validation.md).
- Cluster bootstrap and GitOps reconciliation, README step 5:
  [GitOps Delivery](../implementation/gitops-delivery.md).
- Workload build and publication, README step 6:
  [GitOps Delivery](../implementation/gitops-delivery.md#1-build-once-gitlab-ci-to-an-immutable-digest)
  and the workload repository's pipelines.

| Runbook | Owns |
|---|---|
| [operator-access.md](operator-access.md) | The workstation toolchain, Identity Center setup and CLI profiles, sign-in, the identity and account checks, credential lifetime, the wrong-account response, legacy credential retirement |
| [terraform-operations.md](terraform-operations.md) | The workflow every root shares: static checks, initialization, the reviewed saved plan and its binding, apply, convergence, drift, locks, failed or interrupted applies, moved blocks, debug logging; the state backend's first build |
| [persistent-foundations.md](persistent-foundations.md) | Evidence-store read-back, registry repositories and the CI push scope, image verification by digest, the CI push identity and its GitLab side |
| [public-dns-and-certificate.md](public-dns-and-certificate.md) | The zone-first build, zone read-back, the checks before and after the registrar change, delegation rollback and zone retirement, the certificate |
| [dev-network.md](dev-network.md) | The zone check, the Dev retained baseline, the retained and runtime split, network and secret read-back, the network with the datastore inside it |
| [dev-datastore.md](dev-datastore.md) | The two-stage datastore build, master-value placement, secret verification and CloudTrail accounting, the secret-absence proof, read-back, exposure containment |
| [cost-and-residue.md](cost-and-residue.md) | Budget, tag and price read-backs, the Cost Explorer breakdown, the CPU-credit check, the weekly review, the budget-level responses, the orphan census and cleanup |
| [evidence-handling.md](evidence-handling.md) | Capture, redaction, the sweep and its positive control, sealing, export before teardown, read-back after destruction, remediation |

Each procedure lives in exactly one runbook, and the others link to that file. This index holds no
procedure. The root READMEs under [terraform/](../../terraform/) remain the authority for what each
root creates and why, its inputs, protections, lifecycle order, status and limitations, and the
records in [docs/decisions](../decisions/) for the decisions. The runbooks link both and restate
neither.

## Before you start

Everything below is obtained outside these repositories. It is listed by class, never by value.
The Hidden prerequisites section at the end of each runbook is the detailed list.

### Account, identity and root inputs

- A dedicated AWS account for the platform. Its ID goes only into each root's untracked
  `terraform.tfvars`, as `allowed_account_id`, and into local AWS CLI configuration.
- An AWS Organizations management account with an IAM Identity Center organization instance, and
  an identity for the first Identity Center setup. The reference setup ran in a root-user session,
  and no other path was exercised. The root user's credentials and MFA device are held for
  recovery ([operator-access.md](operator-access.md#hidden-prerequisites)).
- An Identity Center user for each operator, with an email address the operator can read and the
  operator's own MFA device, and two permission sets named exactly `ReadOnlyAccess` and
  `AdministratorAccess`, assigned to the account. The start URL, its Region and the SSO session
  name stay in local CLI configuration, and a browser on the workstation approves each sign-in.
- Each root's untracked `backend.hcl` and `terraform.tfvars`, whose shape the tracked `.example`
  files show. `backend.hcl` names the state bucket the bootstrap root creates. The foundation
  root's four [inputs](../../terraform/foundation/README.md#input) include a globally unique
  evidence bucket name, the GitLab project's numeric ID and the registered domain, and every plan of
  that root needs all four. The Dev root's [inputs](../../terraform/dev/README.md#input) include the
  operator's public IPv4 address as a `/32` in `operator_cidr`, which every plan of that root needs
  and which changes with the network the operator works from.
- The account's mapping of `us-east-1a` and `us-east-1b` to zone IDs, checked for EKS support, the
  `m6a.large` node type and PostgreSQL 17.11 on `db.t4g.micro` with gp3
  ([dev-network.md](dev-network.md#hidden-prerequisites),
  [dev-datastore.md](dev-datastore.md#hidden-prerequisites)).
- For legacy credential retirement only: the legacy IAM user's name and its access key ID, which
  stay out of every record.

### Registrar

- A registered apex domain at an external registrar, controlled by the operator, with a known
  renewal posture. Registration and renewal sit outside AWS and outside the AWS budget.
- Registrar access, with multi-factor sign-in, that can replace the domain's name-server set, and
  knowledge of the domain's lock status and of whether the parent holds a DS record.
- Before the cutover, a private export of the zone the previous provider serves, kept with its
  sha256, and the previous name-server set, both kept for rollback
  ([public-dns-and-certificate.md](public-dns-and-certificate.md#hidden-prerequisites)).

### GitLab

- A GitLab.com project that holds the workload source and its pipelines, with GitLab API access
  that can change its project settings, and access to its CI/CD variables. The reference change
  used a temporary project access token, revoked after use, whose role and scope were not recorded.
- The project attribute `ci_id_token_sub_claim_components` set to `project_id`, `ref_type`, `ref`,
  and two masked CI/CD variables, `AWS_ROLE_ARN` and `ECR_REGISTRY`
  ([persistent-foundations.md](persistent-foundations.md#hidden-prerequisites)).

### Toolchain

- Terraform 1.15.5, installed explicitly from HashiCorp's release archive. Every root accepts
  `>= 1.11, < 2.0`, but 1.15.5 is the only version exercised. The `hashicorp/aws` provider comes
  from the committed lock files (6.58.0), which carry hashes for two platforms.
- AWS CLI v2 with IAM Identity Center support. The version used was not recorded.
- `bash`, `python3`, `sed`, `git`, `jq`, `unzip`, `shasum` or `sha256sum`, `curl`, `gpg` and `dig`;
  TFLint (0.64.0 used) and Trivy (0.74.0 used) for the static checks; and network access to the
  Terraform registry for a provider install
  ([operator-access.md](operator-access.md#workstation-toolchain),
  [terraform-operations.md](terraform-operations.md#hidden-prerequisites)).
- `crane`, which the reference mirror of a platform image used. This suite publishes no mirroring
  procedure.
- A way to run the datastore's Stage 2 apply that closing or losing the terminal cannot end. The
  executed form is not published ([dev-datastore.md](dev-datastore.md#hidden-prerequisites)).

### Cost setup

- A monthly 200 USD cost budget named `cloud-platform-reference`, created outside Terraform and
  scoped to the project account, with five notifications: ACTUAL 100, 150 and 200 and FORECASTED
  150 and 200, each `GREATER_THAN` with an `ABSOLUTE_VALUE` threshold.
  [ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md) requires it before the
  first billable resource, which is the state bucket. No creation procedure is published. Its
  subscriber addresses are held privately.
- Cost Explorer enabled on the account, a one-time console action that the API cannot perform.
  Current-month data appears about 24 hours after enabling.
- The six cost-allocation tag keys activated by an identity with billing authority, from the
  management account in an organization. Activation takes up to 24 hours to apply, and no
  activation command is published.
- Read access for the budget, Cost Explorer, Price List and CloudWatch reads and for the list and
  describe calls of the orphan census, and, for an orphan cleanup, permission to delete that one
  object's class; an environment-hour ledger kept by hand; and knowledge of
  the expected persistent set, so that retained resources can be told from residue
  ([cost-and-residue.md](cost-and-residue.md#hidden-prerequisites)).

### Out-of-band secret values

- The datastore master password: one plain `SecretString` that meets the RDS for PostgreSQL
  master-password constraints, placed once by the owner into the master container before the
  instance is planned. Placement needs a tool that keeps the scope, metadata-only validation and
  STOP and no-retry rules in [dev-datastore.md](dev-datastore.md#place-the-master-value), qualified
  offline before use, and a fixed client request token chosen in advance and kept privately. The
  reviewed placement tool is not published.
- A secret-absence proof tool that implements the published method. The reviewed tool is not
  published.
- A value for the Dev workload secret, and the private key of a read-only deploy key for your own
  desired-state repository. Both are placed out of band after their containers exist, never through
  Terraform, and a runtime window needs them. No public placement procedure exists for either, and
  the master placement does not cover them
  ([dev-network.md](dev-network.md#hidden-prerequisites)).
- Nothing for the datastore's application container. Its value is deferred until the path that
  consumes it is designed and independently reviewed.

### Private working locations

- A new private directory for each plan, outside every Git working tree and created under
  `umask 077`, for saved plans, plan JSON, logs and any recovery copy of state. No deletion rule is
  defined for it.
- A private evidence root, mode 0700 and outside every Git working tree; a private record outside
  every sealed set for manifest digests, export prefixes and counts; and a private location for the
  budget, CPU-credit, weekly-review, census and cleanup records.
- A private literal list and address allowlist for redaction and sweeps, and a redaction filter and
  an archive-aware sweep that fail closed; the project's own are not published. For export and
  read-back, an operator session that can write to and read from the evidence destination
  ([evidence-handling.md](evidence-handling.md#hidden-prerequisites)).

### Approvals

- An approver: the person accountable for the AWS account, who gives written approval before each
  mutating step and identifies a saved plan by its sha256. That covers every apply and refresh-only
  apply, destroy, decommission, force-unlock, recovery action, registrar change, delegation
  rollback, zone retirement, secret placement, IAM credential change, GitLab project-setting
  change, evidence export, remediation deletion, orphan cleanup and resume after a HOLD, and, on
  `terraform/dev-datastore`, every plan and every other run that reads the master value.
- A list of everyone with access to the state backend, and a way to reach each of them, for the
  held-lock check ([terraform-operations.md](terraform-operations.md#hidden-prerequisites)).

## Validation labels

Each procedure opens with a table that gives its validation status, its published form, the
evidence it rests on, the authority it needs and its cost in absolute USD. Labels are assigned per
procedure, never per resource, and conservatively. A label is never upgraded without new retained
evidence of that procedure. Each label carries the date of the execution it rests on, or `never`;
where parts of one procedure rest on different evidence, each part carries its own label.

| Label | Meaning |
|---|---|
| AWS-VALIDATED | Executed against the real account, or verified on public DNS, with the result verified by retained evidence. |
| OFFLINE-VALIDATED | Exercised only offline: a qualification harness, mocks, dry runs or read-only gates. |
| DESIGNED-NOT-EXECUTED | A concrete, reviewed procedure that has never run. |
| UNEXERCISED | Never exercised, and no reviewed concrete procedure exists. |
| EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE | Executed in the past and recorded, with no retained evidence of the execution. |
| COMPOSED FROM AWS-VALIDATED STEPS; END-TO-END COMMAND FORM NOT YET EXERCISED | The ordered composition of validated steps, never run end to end as published. Any part that rests on weaker evidence carries its own label in the owning runbook. |

**Published form** is one of two values:

- **executed as written**: this exact command form, placeholders aside, appears as executed in
  retained evidence;
- **not executed as written**: anything else, with a short note on what the published form is
  derived from, for example a run through private tooling that is not published, the same call
  without a projection, or a method with no runnable command.

The two fields are read together. Validation status says what ran and what verified it; published
form says whether the command on the page is the one that ran. A procedure can be AWS-VALIDATED
while its published form is not executed as written.

What never raises a label:

- A resource that exists, or a read-back of it, does not validate the procedure that would rotate,
  restore, roll back or decommission it.
- A read-only gate, a dry run or an offline qualification is OFFLINE-VALIDATED at most.
- A registrar action attested by the person who made it is not AWS evidence. Only its public-DNS
  outcome is, verified by a separate procedure.
- An execution recorded without retained evidence is never AWS-VALIDATED.
- A snapshot or an automated backup is not restore proof.

The evidence basis names public anchors, meaning ADRs, repository files and sections, and commits,
and describes retained private evidence generically. Raw evidence stays private
([Public and private evidence](evidence-handling.md#public-and-private-evidence)).

## Task list

The order follows README steps 1 to 4, with the access, cost and evidence operations placed where
they first apply. Each row points at the sections that hold the procedure and its status.

| # | When | Task | Runbook sections |
|---|---|---|---|
| 1 | Before any AWS work | Install Terraform and verify its provenance | [Workstation toolchain](operator-access.md#workstation-toolchain) |
| 2 | Before any AWS work | Put AWS Organizations and the Identity Center instance in place, a manual prerequisite | [First-time Identity Center prerequisites](operator-access.md#first-time-identity-center-prerequisites) |
| 3 | Before any AWS work | Set up each operator's user, MFA and permission sets, and one local profile per permission set | [Operator setup in Identity Center](operator-access.md#operator-setup-in-identity-center), [Local CLI profiles](operator-access.md#local-cli-profiles) |
| 4 | Before every AWS command | Sign in, confirm the resolved identity and check the account | [Sign in](operator-access.md#sign-in), [Verify the resolved identity](operator-access.md#verify-the-resolved-identity), [Account check before AWS commands](operator-access.md#account-check-before-aws-commands) |
| 5 | Before a long or sensitive operation | Check session headroom, and run the operation on role credentials exported once | [Session headroom before long operations](operator-access.md#session-headroom-before-long-operations), [Export role credentials once](operator-access.md#export-role-credentials-once) |
| 6 | Before the first billable resource, and again before each billable change | Before the first: confirm the budget and its alerts and the six active cost-allocation tags. Before each change: read the budget back again and re-check the prices the change bills | [Read back the budget and its alert states](cost-and-residue.md#read-back-the-budget-and-its-alert-states), [Read back the cost-allocation tags](cost-and-residue.md#read-back-the-cost-allocation-tags), [Re-check prices before billable work](cost-and-residue.md#re-check-prices-before-billable-work) |
| 7 | Every campaign | Capture its evidence set, redacting at capture | [Capture a campaign evidence set](evidence-handling.md#capture-a-campaign-evidence-set), [Redact at capture](evidence-handling.md#redact-at-capture) |
| 8 | README step 1 | Build the state backend on local state and migrate into it | [Build the state backend and migrate into it](terraform-operations.md#build-the-state-backend-and-migrate-into-it) |
| 9 | Every change to a root | Run the static checks, initialize the root at the reviewed commit, inspect its state, and keep debug logging off | [Run the static checks](terraform-operations.md#run-the-static-checks), [Initialize a root against the state backend](terraform-operations.md#initialize-a-root-against-the-state-backend), [Inspect state without writing it](terraform-operations.md#inspect-state-without-writing-it), [Keep Terraform debug logging off](terraform-operations.md#keep-terraform-debug-logging-off) |
| 10 | Every change to a root | Plan to a saved file, review it, and bind it to its hash and to state | [Plan to a saved file](terraform-operations.md#plan-to-a-saved-file), [Plan without taking the state lock](terraform-operations.md#plan-without-taking-the-state-lock), [Review the saved plan](terraform-operations.md#review-the-saved-plan), [Bind the saved plan to its hash and to state](terraform-operations.md#bind-the-saved-plan-to-its-hash-and-to-state) |
| 11 | Every change to a root | With approval, apply exactly that plan, read the changed resources back through the root's runbook, and confirm convergence | [Apply the reviewed saved plan](terraform-operations.md#apply-the-reviewed-saved-plan), [Confirm convergence](terraform-operations.md#confirm-convergence) |
| 12 | README step 2 | Build the hosted zone on its own and read it back | [Build the zone on its own](public-dns-and-certificate.md#build-the-zone-on-its-own), [Read back the hosted zone](public-dns-and-certificate.md#read-back-the-hosted-zone) |
| 13 | README step 2 | Before the registrar change, check the current delegation, DS, the Route 53 servers, the registrar lock and CAA | [Pre-cutover checks](public-dns-and-certificate.md#pre-cutover-checks), [Registrar lock check](public-dns-and-certificate.md#registrar-lock-check), [CAA check](public-dns-and-certificate.md#caa-check) |
| 14 | README step 2 | Change the name servers at the registrar, then verify delegation on public DNS | [Change the name servers at the registrar](public-dns-and-certificate.md#change-the-name-servers-at-the-registrar), [Verify delegation](public-dns-and-certificate.md#verify-delegation) |
| 15 | README step 2 | Plan and apply the rest of the foundation root with the certificate, then read the certificate back | [Plan and apply the certificate](public-dns-and-certificate.md#plan-and-apply-the-certificate), [Read back the certificate](public-dns-and-certificate.md#read-back-the-certificate) |
| 16 | README step 2 | Read back the evidence store's controls | [Read back the evidence-store controls](persistent-foundations.md#read-back-the-evidence-store-controls) |
| 17 | README step 2 | Connect the GitLab project to the CI push identity, and read back its trust and push scope | [Connect a GitLab project to the CI push identity](persistent-foundations.md#connect-a-gitlab-project-to-the-ci-push-identity), [Read back the CI trust](persistent-foundations.md#read-back-the-ci-trust), [Read back the CI push scope](persistent-foundations.md#read-back-the-ci-push-scope) |
| 18 | README step 3 | Check the zone mapping, then build only the Dev retained baseline | [Check the zone mapping before the first build](dev-network.md#check-the-zone-mapping-before-the-first-build), [Build only the retained baseline](dev-network.md#build-only-the-retained-baseline) |
| 19 | README step 3 | Confirm the retained and runtime split, and read the network and the two Secrets Manager entries back | [Confirm the retained and runtime split](dev-network.md#confirm-the-retained-and-runtime-split), [Read back the retained network](dev-network.md#read-back-the-retained-network), [Read back the two Secrets Manager entries](dev-network.md#read-back-the-two-secrets-manager-entries) |
| 20 | README step 4 | Stage 1: create the datastore's network boundary and empty secret containers, and read both back | [Stage 1: create the network boundary and the empty secret containers](dev-datastore.md#stage-1-create-the-network-boundary-and-the-empty-secret-containers), [Read back the network boundary](dev-datastore.md#read-back-the-network-boundary), [Verify the secret containers without reading a value](dev-datastore.md#verify-the-secret-containers-without-reading-a-value) |
| 21 | README step 4 | Place the master value once, and account for the write in CloudTrail | [Place the master value](dev-datastore.md#place-the-master-value), [Account for secret reads and writes in CloudTrail](dev-datastore.md#account-for-secret-reads-and-writes-in-cloudtrail) |
| 22 | README step 4 | Stage 2: plan the instance and its endpoint parameter, prove the master value absent, and run the pre-apply gate | [Stage 2: plan the instance and its endpoint parameter](dev-datastore.md#stage-2-plan-the-instance-and-its-endpoint-parameter), [Prove the master value is absent from plans, state and logs](dev-datastore.md#prove-the-master-value-is-absent-from-plans-state-and-logs), [Run the pre-apply gate](dev-datastore.md#run-the-pre-apply-gate) |
| 23 | README step 4 | Apply, read back the instance and its endpoint parameter, confirm convergence, and take the first CPU-credit reading | [Stage 2: apply the reviewed saved plan](dev-datastore.md#stage-2-apply-the-reviewed-saved-plan), [Read back the instance and its endpoint parameter](dev-datastore.md#read-back-the-instance-and-its-endpoint-parameter), [Confirm convergence](dev-datastore.md#confirm-convergence), [Check the datastore CPU credits](cost-and-residue.md#check-the-datastore-cpu-credits) |
| 24 | README step 4 | Check the Dev network with the datastore inside it | [Verify the retained side with the datastore present](dev-network.md#verify-the-retained-side-with-the-datastore-present) |
| 25 | Closing every campaign | Sweep the evidence set with a planted positive control, handle any hit, and seal it | [Sweep the set before sealing](evidence-handling.md#sweep-the-set-before-sealing), [Plant a positive control for the sweep](evidence-handling.md#plant-a-positive-control-for-the-sweep), [Handle sweep hits before sealing](evidence-handling.md#handle-sweep-hits-before-sealing), [Seal the set and verify the manifest](evidence-handling.md#seal-the-set-and-verify-the-manifest) |
| 26 | Around every teardown | Export the sealed set before the teardown, and read it back after the environment is destroyed | [Export the sealed set before teardown](evidence-handling.md#export-the-sealed-set-before-teardown), [Read back exported evidence after destruction](evidence-handling.md#read-back-exported-evidence-after-destruction) |
| 27 | Each operating session while the datastore exists | Check the datastore's CPU credits | [Check the datastore CPU credits](cost-and-residue.md#check-the-datastore-cpu-credits) |
| 28 | Weekly | Record the ADR-0013 review, with the budget read-back, the orphan census and, where the budget figures cannot explain spend, a Cost Explorer breakdown | [Record the weekly ADR-0013 review](cost-and-residue.md#record-the-weekly-adr-0013-review), [Run the orphan census](cost-and-residue.md#run-the-orphan-census), [Break spend down with Cost Explorer](cost-and-residue.md#break-spend-down-with-cost-explorer) |
| 29 | When state may lag AWS | Detect drift, and reconcile only state-only drift whose cause is explained | [Detect state drift](terraform-operations.md#detect-state-drift), [Reconcile explained state-only drift](terraform-operations.md#reconcile-explained-state-only-drift) |

This path has not been run end to end from a fresh clone of the current configuration. The first
builds recorded for the bootstrap, foundation and Dev roots ran on earlier shapes of those roots.
The first-build forms for the current configuration are listed under Not yet exercised in
[terraform-operations.md](terraform-operations.md#not-yet-exercised),
[persistent-foundations.md](persistent-foundations.md#not-yet-exercised),
[public-dns-and-certificate.md](public-dns-and-certificate.md#not-yet-exercised) and
[dev-network.md](dev-network.md#not-yet-exercised), and the datastore's build order is in its
[README](../../terraform/dev-datastore/README.md#what-it-creates).

Procedures run when their trigger occurs, rather than in order:

| Trigger | Runbook section |
|---|---|
| A service enters the delivery path and needs its own registry repository | [Add a registry repository and widen the CI push scope](persistent-foundations.md#add-a-registry-repository-and-widen-the-ci-push-scope) |
| A pin or a pipeline artifact names an image digest to confirm | [Verify an image in the registry by digest](persistent-foundations.md#verify-an-image-in-the-registry-by-digest) |
| A refactor changes resource addresses | [Move resource addresses with moved blocks](terraform-operations.md#move-resource-addresses-with-moved-blocks) |
| A human IAM user still holds an access key or a console password | [Retire legacy IAM user credentials](operator-access.md#retire-legacy-iam-user-credentials) |
| The hosted zone is retired at project end | [Retire the hosted zone](public-dns-and-certificate.md#retire-the-hosted-zone) |

## When to stop

A STOP halts the procedure where it occurs, and no mutating step is retried to make it go away. The
owning section says what to inspect and how work resumes. Where it has no written resume
procedure, work stays stopped until a reviewed decision is taken under explicit approval.

| Trigger | Owning section |
|---|---|
| The identity check errors or prints `False`, or the account check prints `ACCOUNT_MATCH=HOLD` | [Wrong-account response](operator-access.md#wrong-account-response), part A |
| A mutating command already ran against another account | [Wrong-account response](operator-access.md#wrong-account-response), part B |
| The credential's headroom is below what the operation needs | [Session headroom before long operations](operator-access.md#session-headroom-before-long-operations) |
| A command fails on an expired or missing token | [Session expiry](operator-access.md#session-expiry) |
| Credentials expire during a run | [Credential expiry mid-run](operator-access.md#credential-expiry-mid-run) |
| A fingerprint, signature, checksum or binary hash differs | [Workstation toolchain](operator-access.md#workstation-toolchain) |
| A static check fails, `init` changes the lock file, or the scan adds a finding class | [Run the static checks](terraform-operations.md#run-the-static-checks) |
| `init` reports a backend change or a state migration, or Git does not ignore an input file | [Initialize a root against the state backend](terraform-operations.md#initialize-a-root-against-the-state-backend) |
| A `TF_*` variable is set in the shell | [Keep Terraform debug logging off](terraform-operations.md#keep-terraform-debug-logging-off) |
| The saved plan differs from the reviewed list, or carries drift without a written cause | [Review the saved plan](terraform-operations.md#review-the-saved-plan) |
| The plan's hash, configuration, lock file, serial or lineage does not match before apply | [Bind the saved plan to its hash and to state](terraform-operations.md#bind-the-saved-plan-to-its-hash-and-to-state) |
| An apply fails, is interrupted, loses its terminal or session, or reports a different summary | [Stop after a failed or interrupted apply](terraform-operations.md#stop-after-a-failed-or-interrupted-apply); on the datastore root, with [Read the datastore after a failed or interrupted apply](dev-datastore.md#read-the-datastore-after-a-failed-or-interrupted-apply) |
| A convergence plan exits 1 or 2 | [Confirm convergence](terraform-operations.md#confirm-convergence) |
| A refresh-only plan reports drift | [Detect state drift](terraform-operations.md#detect-state-drift), then [Reconcile explained state-only drift](terraform-operations.md#reconcile-explained-state-only-drift) |
| `Error acquiring the state lock` | [Handle a held state lock](terraform-operations.md#handle-a-held-state-lock) |
| An evidence-store control differs from its expected value | [Read back the evidence-store controls](persistent-foundations.md#read-back-the-evidence-store-controls) |
| The CI trust or the CI push scope differs from its expected result | [Read back the CI trust](persistent-foundations.md#read-back-the-ci-trust), [Read back the CI push scope](persistent-foundations.md#read-back-the-ci-push-scope) |
| A publish job fails | [Diagnose a failed publication](persistent-foundations.md#diagnose-a-failed-publication) |
| A registry manifest does not hash to its digest | [Verify an image in the registry by digest](persistent-foundations.md#verify-an-image-in-the-registry-by-digest) |
| A DS record at the parent, a Route 53 server not answering authoritatively, or parent servers that disagree | [Pre-cutover checks](public-dns-and-certificate.md#pre-cutover-checks) |
| The registrar refuses the change, or asks to change anything besides the name servers | [Change the name servers at the registrar](public-dns-and-certificate.md#change-the-name-servers-at-the-registrar) |
| A parent server's referral is MIXED or WRONG, or a Route 53 server stops answering authoritatively | [Verify delegation](public-dns-and-certificate.md#verify-delegation), then [Roll back the delegation](public-dns-and-certificate.md#roll-back-the-delegation) |
| The certificate plan differs from its shape, delegation fails the check before the apply, or DNS validation does not complete | [Plan and apply the certificate](public-dns-and-certificate.md#plan-and-apply-the-certificate) |
| An asserted certificate check fails | [Read back the certificate](public-dns-and-certificate.md#read-back-the-certificate) |
| A zone is unavailable or excluded by EKS, or the node type or the engine is not offered in both zones | [Check the zone mapping before the first build](dev-network.md#check-the-zone-mapping-before-the-first-build) |
| A Dev plan holds a runtime or alerting-campaign address, or an alerting variable is `true` | [Build only the retained baseline](dev-network.md#build-only-the-retained-baseline), [Confirm the retained and runtime split](dev-network.md#confirm-the-retained-and-runtime-split) |
| Dev state holds an address outside the 21 retained addresses between windows | [Confirm the retained and runtime split](dev-network.md#confirm-the-retained-and-runtime-split) |
| A `0.0.0.0/0` route in the private route table outside a window, or another network value that differs | [Read back the retained network](dev-network.md#read-back-the-retained-network) |
| An unexpected security group or network interface in the Dev VPC between windows | [Verify the retained side with the datastore present](dev-network.md#verify-the-retained-side-with-the-datastore-present) |
| A Dev secret shows a deletion date or an unexplained version count | [Read back the two Secrets Manager entries](dev-network.md#read-back-the-two-secrets-manager-entries) |
| A datastore secret container holds an unexpected version, stage, key or deletion date | [Verify the secret containers without reading a value](dev-datastore.md#verify-the-secret-containers-without-reading-a-value) |
| A placement ends in any outcome other than placed | [Respond to a failed or uncertain placement](dev-datastore.md#respond-to-a-failed-or-uncertain-placement) |
| An unexpected Secrets Manager read or write in CloudTrail | [Account for secret reads and writes in CloudTrail](dev-datastore.md#account-for-secret-reads-and-writes-in-cloudtrail), then [Contain an exposed or unproven master value](dev-datastore.md#contain-an-exposed-or-unproven-master-value) |
| A secret-absence proof finds the value or cannot complete | [Contain an exposed or unproven master value](dev-datastore.md#contain-an-exposed-or-unproven-master-value) |
| Any pre-apply gate check fails or cannot be read | [Run the pre-apply gate](dev-datastore.md#run-the-pre-apply-gate) |
| An instance or parameter value differs, or the endpoint check prints `MISMATCH` | [Read back the instance and its endpoint parameter](dev-datastore.md#read-back-the-instance-and-its-endpoint-parameter) |
| The budget, a notification or a subscriber is missing or changed | [Read back the budget and its alert states](cost-and-residue.md#read-back-the-budget-and-its-alert-states) |
| A notification in `ALARM`, or spend reaching or projected to reach 100, 150 or 200 USD | [Respond to the 100, 150 and 200 USD levels](cost-and-residue.md#respond-to-the-100-150-and-200-usd-levels) |
| A cost-allocation tag key is missing or inactive | [Read back the cost-allocation tags](cost-and-residue.md#read-back-the-cost-allocation-tags) |
| A price differs from the table, or a rate the change bills is not in it | [Re-check prices before billable work](cost-and-residue.md#re-check-prices-before-billable-work) |
| A spend line maps to no known resource | [Break spend down with Cost Explorer](cost-and-residue.md#break-spend-down-with-cost-explorer) |
| Surplus CPU credits charged, or a surplus balance without a documented cause | [Check the datastore CPU credits](cost-and-residue.md#check-the-datastore-cpu-credits) |
| A weekly review is missed | [Record the weekly ADR-0013 review](cost-and-residue.md#record-the-weekly-adr-0013-review) |
| The census prints `UNKNOWN`, or a runtime class stays above 0 | [Run the orphan census](cost-and-residue.md#run-the-orphan-census), then [Clean up an orphan](cost-and-residue.md#clean-up-an-orphan) |
| A sweep hit, a file the sweep cannot inspect, or a planted control the sweep misses | [Sweep the set before sealing](evidence-handling.md#sweep-the-set-before-sealing), [Plant a positive control for the sweep](evidence-handling.md#plant-a-positive-control-for-the-sweep), [Handle sweep hits before sealing](evidence-handling.md#handle-sweep-hits-before-sealing) |
| A manifest entry fails, or the set holds a file the manifest does not list | [Seal the set and verify the manifest](evidence-handling.md#seal-the-set-and-verify-the-manifest) |
| The destination does not resolve to exactly one bucket, the prefix is not empty, or a count or the manifest digest differs | [Export the sealed set before teardown](evidence-handling.md#export-the-sealed-set-before-teardown) |
| An exported object is mismatched, missing or extra at read-back | [Read back exported evidence after destruction](evidence-handling.md#read-back-exported-evidence-after-destruction) |
| A prohibited value in a sealed or exported set | [Remediate a prohibited value in retained or exported evidence](evidence-handling.md#remediate-a-prohibited-value-in-retained-or-exported-evidence) |

## Conventions

- **Placeholders.** Angle brackets stand wherever a real value would go, for example `<profile>`,
  `<allowed-account-id>`, `<state-bucket>`, `<evidence-bucket>`, `<apex>`, `<private-dir>`,
  `<plan-file>` and `<commit>`. Each runbook defines the ones it uses; the Terraform placeholders
  are defined in [terraform-operations.md](terraform-operations.md).
- **Identifiers are never printed.** Commands project their output with `--query` or `jq`, so that
  successful output carries no ARN, account number, secret version ID or email address. Account
  checks print a verdict, never the account ID, and a hash of an account ID is not anonymous. Error
  output is not projected, because an AWS error can carry the caller's ARN and the account number;
  it is kept out of evidence or redacted at capture, as each runbook states.
- **Saved plans and plan JSON stay private.** Saved plans, plan JSON and state pulls stay in the
  private directory, outside every Git working tree, and are never published or exported as
  evidence: they carry private inputs and account identifiers in clear text. Plan text and apply
  logs stay private too. `.gitignore` excludes `*.tfplan` but not plan JSON.
- **Debug logging stays off.** No `TF_*` variable, `TF_LOG` above all, is set in a shell that runs
  a plan or an apply: on `terraform/dev-datastore` the master value passes through the provider on
  every plan and apply
  ([Keep Terraform debug logging off](terraform-operations.md#keep-terraform-debug-logging-off)).
- **Explicit owner approval before any mutation.** The owner is the person accountable for the AWS
  account. No AWS, IAM, state, registrar or GitLab setting is changed, and no secret value is
  placed, without the owner's written approval given before the step. An approval covers the step
  it names: an apply approval names the saved plan's sha256, and a refresh-only apply needs its own.
  Read-only procedures need none, except on `terraform/dev-datastore`, where every plan reads the
  master value.
- **Neutral executor wording.** Statuses and records say when a step ran and what it showed, for
  example "executed 2026-09-24", and never name an executor. The private capture template has an
  Executed by field ([Capture a campaign evidence set](evidence-handling.md#capture-a-campaign-evidence-set)).
- **Region, time and shell.** Regional commands target `us-east-1`, and the orphan census covers
  that region only. Dates and times are UTC. Commands are written for `bash`.
- **Permission sets.** Inspection is meant for the ReadOnly profile, but every recorded plan and
  apply, and the retained operator read-only checks, ran on the `AdministratorAccess` permission
  set. Running them on `ReadOnlyAccess` has not been exercised.

## Roadmap

### Recovery obligations

[ADR-0011](../decisions/0011-define-the-backup-and-recovery-model.md) sets these obligations. None is
claimed complete without evidence, and a snapshot's existence is not restore proof. Where each
stands is recorded in the runbook linked beside it.

- The Terraform-state recovery exercise is mandatory before ADR-0011 is complete
  ([terraform-operations.md](terraform-operations.md#not-yet-exercised)).
- The workload-data restore exercise is mandatory now that the datastore exists, and runs only
  under a separately reviewed recovery package ([dev-datastore.md](dev-datastore.md#not-yet-exercised)).
- Secret accidental-deletion recovery must be verified
  ([dev-datastore.md](dev-datastore.md#not-yet-exercised),
  [dev-network.md](dev-network.md#not-yet-exercised)).
- Exported evidence must be read back after environment destruction
  ([evidence-handling.md](evidence-handling.md#read-back-exported-evidence-after-destruction)).

Evidence that must survive a teardown is exported before it, and its read-back after the
environment is destroyed is a required verification in every runtime window.

### Later passes

Runbooks accompany validated implementation and never replace it. Later passes add one area at a
time, each only after its milestone has been validated:

- CI/CD operations
- image build and publication
- security admission under
  [ADR-0015](../decisions/0015-define-security-admission-and-exception-governance-for-platform-managed-runtime-components.md)
- GitOps
- EKS and runtime windows
- node and AMI image controls
- workload identity
- External Secrets
- public ingress and the Application Load Balancer
- observability
- alerting
- fault validation
- teardown and the residual census
- backup, restore and recovery

After full runtime validation, a final end-to-end reconciliation of the whole suite and a
clean-room reproducibility review close the series.
