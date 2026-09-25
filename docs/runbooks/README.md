# Runbooks

<a id="scope"></a>

## What these runbooks are

These runbooks are the operating procedures for the platform, written for an engineer who did not
build it. They cover steps 1 to 4 of
[Reproducing the Platform](../../README.md#reproducing-the-platform): the state backend, the
persistent foundations with the public DNS zone and the certificate, the Dev network's retained
baseline and the Dev datastore, and the operator access, cost and evidence operations around those
steps. Following them ends at a built datastore, not a running cluster. Later areas are added one
at a time ([Roadmap](#roadmap)).

The public repositories alone do not get that far. This project has not published the items below.
You supply each one yourself or, where a decision is missing, the owner takes it under explicit
approval. Until then the [Build order](#build-order) stops at the step named:

- **Cost setup, step 2.** The budget with its five notifications, Cost Explorer and the six
  cost-allocation tags have no published creation, enabling or activation procedure. On a new
  account the tag read-back passes only if resources carrying the six keys already exist, and no
  order for a new account is published: until the owner decides one, the read-back's STOP holds.
- **The bootstrap Stage 1 plan, step 3.** Stage 1 is published as step-level instructions without
  commands, and review and binding of its plan on local state have no published form. The binding
  check as written reports `backend.tf` missing from that plan, which is a STOP.
- **Evidence tooling, from step 3.** A redaction filter and a value-based, archive-aware sweep that
  fail closed. Every root change is a campaign whose evidence set is swept and sealed, and this
  suite defines no reduced capture without them
  ([Private working locations](#private-working-locations)).
- **The foundation's first build, step 4.** On a build from nothing, the certificate-stage plan has
  no reviewed shape and stops at its step 2. Steps 5 and 6 do not need step 4.
- **Binding a root's first apply, steps 4, 5 and 6.** The binding check reads the remote serial and
  lineage. What that read prints against a state object never yet written has not been recorded;
  if it prints nothing, the first apply stops at binding until a reviewed decision is taken under
  explicit approval ([Bind the saved plan](terraform-operations.md#bind-the-saved-plan-to-its-hash-and-to-state)).
- **The datastore after its Stage 1, step 6.** A placement tool qualified offline, a tool that
  implements the secret-absence proof, and a way to run the Stage 2 apply that closing or losing the
  terminal cannot end. Even with everything above, the datastore build stops after its Stage 1
  without these three.

These are outside the suite:

- Runtime windows. A runtime window is a bounded period that creates the EKS cluster, its nodes and
  the NAT gateway on top of the retained baseline, exercises them and destroys them at close. The
  retained baseline is what the Dev network root keeps in AWS between windows. The windows that
  ran, their teardown and their residual checks are summarized in
  [Runtime Validation](../validation/runtime-validation.md).
- Creating, operating and tearing down a runtime window has no published procedure, so public
  reproduction stops before README step 5, which needs a running cluster
  ([Known reproducibility gaps](#known-reproducibility-gaps)).
- Cluster bootstrap and GitOps reconciliation, README step 5:
  [GitOps Delivery](../implementation/gitops-delivery.md). Mirroring the platform images it needs
  has no published procedure ([Known reproducibility gaps](#known-reproducibility-gaps)).
- Workload build and publication, README step 6:
  [GitOps Delivery](../implementation/gitops-delivery.md#1-build-once-gitlab-ci-to-an-immutable-digest)
  and the workload repository's pipelines.

| Runbook | Covers |
|---|---|
| [operator-access.md](operator-access.md) | The workstation toolchain, Identity Center setup and CLI profiles, sign-in, the identity and account checks, session headroom and the exported shell, recovery from an expired session or a wrong account, legacy credential retirement |
| [terraform-operations.md](terraform-operations.md) | The workflow every root shares: static checks, initialization, the saved plan with its review and binding, apply, convergence, drift, moved blocks, locks, failed or interrupted applies, debug logging; the state backend's first build |
| [persistent-foundations.md](persistent-foundations.md) | Evidence-store read-back, registry repositories and the CI push scope, image verification by digest, the CI push identity and its GitLab side, a failed publication |
| [public-dns-and-certificate.md](public-dns-and-certificate.md) | The zone-first build, zone read-back, the checks before and after the registrar change, the certificate, delegation rollback and zone retirement |
| [dev-network.md](dev-network.md) | The zone check, the Dev retained baseline, the retained and runtime split, network and secret read-back, the network with the datastore inside it |
| [dev-datastore.md](dev-datastore.md) | The two-stage datastore build, master-value placement, the pre-apply gate, secret verification and CloudTrail accounting, the secret-absence proof, read-back, failed placements and applies, exposure containment |
| [cost-and-residue.md](cost-and-residue.md) | Budget, price and tag read-backs, the Cost Explorer breakdown, the CPU-credit check, the weekly review, the budget-level responses, the orphan census and cleanup |
| [evidence-handling.md](evidence-handling.md) | Capture, redaction, the sweep and its positive control, sealing, export before teardown, read-back after destruction, remediation |

Each procedure lives in exactly one runbook, and the others link to it. This index holds no
procedure. The root READMEs under [terraform/](../../terraform/) remain the authority for what each
root creates and why, its inputs, protections, lifecycle order, status and limitations, and the
records in [docs/decisions](../decisions/) for the decisions. The runbooks link both and restate
neither.

## Where to start

- **New to the project:** gather what [Before you start](#before-you-start) lists, then follow the
  [Build order](#build-order) from step 1.
- **Access already set up:** find the task in
  [Find the procedure for a task](#find-the-procedure-for-a-task).
- **Something failed or stopped:** go to [When something fails](#when-something-fails).

Every runbook has the same shape: **Normal path**, the procedures in the order a normal run uses
them; **Before you start**; **Procedures**, normal path first, then checks, then failure and
recovery; **Not yet exercised**; **Reproducibility gaps**; and **Background prerequisites**. Every
procedure opens with its validation label and then, where they apply, says what it does, what must
already exist, whether it is safe and who approves it, the steps, the expected result, PASS and
STOP, where to go on failure, the evidence to keep and the next step. Its **Engineering notes** hold
the audit detail.

Terms used across the suite:

- **Root:** a Terraform root directory under `terraform/`, not the AWS root user.
- **Saved plan:** a plan written to a file, reviewed, bound to its hash and to the state it was made
  from, and applied exactly as reviewed.
- **Account check:** compares the account the credentials resolve with the root's
  `allowed_account_id` and prints only `ACCOUNT_MATCH=PASS` or `ACCOUNT_MATCH=HOLD`
  ([Check the account before AWS commands](operator-access.md#check-the-account-before-aws-commands)).
- **Exported shell:** a clean shell that holds one role credential, exported once, and nothing else
  ([Export role credentials once](operator-access.md#export-role-credentials-once)).
- **Campaign:** one bounded operation whose evidence is kept together, for example an apply with
  its read-back.
- **Owner** and **grant:** the owner is the person accountable for the AWS account; a grant is the
  owner's written approval, given before the step it names ([Approvals](#approvals)).
- **STOP** and **HOLD:** a STOP halts the procedure where it occurs; a HOLD is a check that failed
  or could not be read, and it applies nothing ([When something fails](#when-something-fails)).

## Before you start

Everything below comes from outside these repositories and is listed by class, never by value. Each
runbook's own **Before you start** says what its procedures need.

### Account and identity

- [ ] A dedicated AWS account. Its ID goes only into each root's untracked `terraform.tfvars`, as
  `allowed_account_id`, and into local AWS CLI configuration
  ([operator-access.md](operator-access.md#before-you-start)).
- [ ] AWS Organizations and an IAM Identity Center organization instance, and on a new account an
  identity for the first setup; the only exercised path used a root-user session
  ([Enable Organizations and Identity Center](operator-access.md#enable-organizations-and-identity-center)).
  The root user's credentials and MFA device are held for recovery
  ([Background prerequisites](operator-access.md#background-prerequisites)).
- [ ] An Identity Center user per operator, with a readable email address and the operator's own
  MFA device, and the permission sets `ReadOnlyAccess` and `AdministratorAccess` assigned to the
  account ([Set up an operator in Identity Center](operator-access.md#set-up-an-operator-in-identity-center)).
  The start URL, its Region and the SSO session name stay in local CLI configuration, and a browser
  approves each sign-in.
- [ ] For legacy credential retirement only: the legacy IAM user's name and access key ID, kept out
  of every record.

### Root inputs

- [ ] Each root's untracked `backend.hcl`, naming the state bucket the bootstrap root creates, and
  `terraform.tfvars`, shaped like the tracked `.example` files
  ([terraform-operations.md](terraform-operations.md#before-you-start)).
- [ ] The foundation root's four [inputs](../../terraform/foundation/README.md#input), all needed
  by every plan of that root: the account ID, a globally unique evidence bucket name, the GitLab
  project's numeric ID and the registered domain.
- [ ] The Dev root's [inputs](../../terraform/dev/README.md#input), including your public IPv4
  address as a `/32` in `operator_cidr`, which every plan of that root needs and which changes with
  the network you work from. A changed value is no exception to the warning at step 5 of the
  [Build order](#build-order): a plain `terraform apply` in `terraform/dev` creates billable runtime.
- [ ] Your account's mapping of `us-east-1a` and `us-east-1b` to zone IDs, checked for EKS
  support, the `m6a.large` node type and PostgreSQL 17.11 on `db.t4g.micro` with gp3
  ([Check the zone mapping before the first build](dev-network.md#check-the-zone-mapping-before-the-first-build)).

### Toolchain

- [ ] Terraform 1.15.5, installed from HashiCorp's release archive and checked for provenance
  ([Prepare the workstation toolchain](operator-access.md#prepare-the-workstation-toolchain)).
  Roots accept `>= 1.11, < 2.0`, but only 1.15.5 has been exercised. The committed lock files pin
  `hashicorp/aws` 6.58.0.
- [ ] AWS CLI v2 with IAM Identity Center support; the version used was not recorded.
- [ ] `bash`, `python3`, `sed`, `git`, `jq`, `unzip`, `shasum` or `sha256sum`, `curl`, `gpg`, `dig`,
  TFLint (0.64.0 used), Trivy (0.74.0 used), and network access to the Terraform registry
  ([terraform-operations.md](terraform-operations.md#before-you-start)).
- [ ] A way to run the datastore's Stage 2 apply that closing or losing the terminal cannot end. The
  executed form is not published ([dev-datastore.md](dev-datastore.md#before-you-start)).

### Cost setup

- [ ] The monthly 200 USD budget `cloud-platform-reference` with its five notifications, created
  outside Terraform before the first billable resource, the state bucket, as
  [ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md) requires. No creation
  procedure is published; its shape is in
  [cost-and-residue.md](cost-and-residue.md#background-prerequisites).
- [ ] Cost Explorer enabled, a one-time console action the API cannot perform; its data appears
  about 24 hours later.
- [ ] The six cost-allocation tag keys activated by an identity with billing authority (in an
  organization, from the management account); they take up to 24 hours to apply, and no activation
  command is published. On a new account a key can be activated only after a resource carries it,
  and AWS can take up to 24 hours to list it. No order for a new account is published, and until
  the owner decides one, the tag read-back at step 2 of the [Build order](#build-order) STOPs
  ([Background prerequisites](cost-and-residue.md#background-prerequisites)).
- [ ] Read access for the cost reads and the orphan census, delete permission for one object's
  class for a cleanup, an environment-hour ledger kept by hand, and knowledge of the expected
  persistent set ([cost-and-residue.md](cost-and-residue.md#before-you-start)).

### Registrar and GitLab

- [ ] A registered apex domain you control at an external registrar, with a known renewal posture,
  and registrar access with multi-factor sign-in that can replace its name-server set. Know its lock
  status and whether the parent holds a DS record.
- [ ] Before the cutover: a private export of the zone the previous provider serves, with its
  sha256, and the previous name-server set, kept for rollback
  ([public-dns-and-certificate.md](public-dns-and-certificate.md#before-you-start)).
- [ ] A GitLab.com project that holds the workload source and pipelines, with API access that can
  change its project settings and access to its CI/CD variables. The setting and the two masked
  variables the push identity needs are produced by
  [Connect a GitLab project to the CI push identity](persistent-foundations.md#connect-a-gitlab-project-to-the-ci-push-identity).

### Out-of-band secret values

- [ ] The datastore master password: one plain `SecretString` within the RDS for PostgreSQL
  master-password constraints, placed once by the owner before the instance is planned, with a
  placement tool qualified offline and a client request token chosen in advance
  ([Place the master value](dev-datastore.md#place-the-master-value)). The reviewed placement tool
  is not published.
- [ ] A tool that implements the published
  [secret-absence proof](dev-datastore.md#prove-the-master-value-is-absent-from-plans-state-and-logs).
  The reviewed tool is not published.
- A runtime window, not this suite, needs a Dev workload secret value and the private key of a
  read-only deploy key, placed out of band, never through Terraform, with no public procedure
  ([dev-network.md](dev-network.md#background-prerequisites)). The datastore's application
  container stays empty; its value is deferred.

### Private working locations

- [ ] A new private directory for each plan, outside every Git working tree and created under
  `umask 077` ([terraform-operations.md](terraform-operations.md#before-you-start)).
- [ ] A private evidence root (mode 0700), a private record for manifest digests, export prefixes
  and counts, a private literal list and address allowlist, and a redaction filter and a
  value-based, archive-aware sweep that fail closed
  ([evidence-handling.md](evidence-handling.md#before-you-start)). The project's own filter and
  sweep are not published, so you supply your own before the first campaign; this suite defines no
  reduced capture without them.
- [ ] A private location for the budget, CPU-credit, weekly-review, census and cleanup records
  ([cost-and-residue.md](cost-and-residue.md#before-you-start)).

### Approvals

- [ ] An approver: the person accountable for the AWS account, who gives written approval before
  each mutating step and identifies a saved plan by its sha256. That covers every apply and
  refresh-only apply, destroy, decommission, force-unlock, recovery action, registrar change,
  delegation rollback, zone retirement, secret placement, IAM credential change, GitLab
  project-setting change, evidence export, remediation deletion, orphan cleanup and resume after a
  HOLD, and every run that reads the datastore master value. On `terraform/dev-datastore` that
  includes every plan of a configuration that contains `database.tf`, convergence plans included.
  The Stage 1 configuration, at commit `aeb1622`, does not contain it
  ([Stage 1](dev-datastore.md#stage-1-create-the-network-boundary-and-the-empty-secret-containers)).
- [ ] A list of everyone with access to the state backend, and a way to reach each of them, for the
  held-lock check ([terraform-operations.md](terraform-operations.md#background-prerequisites)).

<a id="task-list"></a>

## Build order

Follow these steps in order to build the platform: README steps 1 to 4, with the access, cost and
evidence steps placed where they first apply. Only steps 5 and 6 may run before step 4 (step 5 says
why). The build ends at a built datastore, not a running cluster. Before step 1, read the list in
[What these runbooks are](#scope) of what you supply or decide yourself: without it, the step it
names stops.

1. **Operator access**, once per workstation and operator. First create the file the account
   check reads: copy the tracked `terraform/bootstrap/terraform.tfvars.example` to
   `terraform.tfvars` in the bootstrap root's private `<inputs-dir>`
   ([terraform-operations.md](terraform-operations.md#before-you-start)), set
   `allowed_account_id` to the project account's ID, and give that file's path as
   `<root-tfvars>`. The rest of the file is needed from step 3. Every root pins the same account,
   so this file also serves the account check for work that targets no root, such as sign-in and
   the step 2 read-backs. Then run, in order,
   [Prepare the workstation toolchain](operator-access.md#prepare-the-workstation-toolchain),
   [Enable Organizations and Identity Center](operator-access.md#enable-organizations-and-identity-center)
   (a manual prerequisite, never exercised in this project),
   [Set up an operator in Identity Center](operator-access.md#set-up-an-operator-in-identity-center)
   and [Configure the local CLI profiles](operator-access.md#configure-the-local-cli-profiles),
   whose step 2 runs the first account check against that file. When each has met its
   **PASS when**, return here.
   Before AWS work after that: [Sign in](operator-access.md#sign-in),
   [Verify the resolved identity](operator-access.md#verify-the-resolved-identity) and
   [Check the account before AWS commands](operator-access.md#check-the-account-before-aws-commands).
   PASS: each linked procedure's **PASS when** holds; in particular the toolchain reports Terraform
   v1.15.5 after its signature and hash checks, and on the profile the next work uses the identity
   check prints `True` twice and the account check prints `ACCOUNT_MATCH=PASS`. Then continue at
   step 2.
2. **Cost controls, before the first billable resource.** Confirm the budget and its alerts
   ([Read back the budget and its alert states](cost-and-residue.md#read-back-the-budget-and-its-alert-states))
   and the six active cost-allocation tags
   ([Read back the cost-allocation tags](cost-and-residue.md#read-back-the-cost-allocation-tags)).
   Neither the budget nor the tags have a published creation procedure. Before each later billable
   change, read the budget back again and
   [re-check the prices](cost-and-residue.md#re-check-prices-before-billable-work) the change bills.
   PASS: one budget `cloud-platform-reference` of `200.0` `USD` with its five notifications, each
   `OK` and each with at least one subscriber, and the `UserDefined` cost-allocation keys exactly
   the six, each `Active`. Then continue at step 3.
   > **Warning:** On a new account the tag read-back passes only if resources carrying the six keys
   > already exist, because AWS lists a key for activation only after a resource carries it. No
   > order for a new account is published. Until the owner decides one, the read-back's STOP holds,
   > and step 3, which creates the first billable resource, does not start
   > ([Background prerequisites](cost-and-residue.md#background-prerequisites)).
3. **README step 1, the state backend.**
   [Build the state backend and migrate into it](terraform-operations.md#build-the-state-backend-and-migrate-into-it):
   Stage 1 on local state, then the migration, each under its own approval. The bucket is the
   first billable resource: before the Stage 1 apply, read the budget back and
   [re-check the prices](cost-and-residue.md#re-check-prices-before-billable-work) in the exported
   shell. The price table has no S3 storage rate, so that re-check stops, and the owner approves a
   re-estimate before the apply; no written re-estimation procedure exists. PASS: state lists
   exactly the five bootstrap resources, and Confirm convergence returns 0. Then continue at step 4,
   or at step 5 for the Dev roots.
   > **Warning:** From a fresh clone, review and binding of the Stage 1 plan on local state have no
   > published form ([Known reproducibility gaps](#known-reproducibility-gaps)). With `backend.tf`
   > moved aside, step 2 of
   > [Bind the saved plan to its hash and to state](terraform-operations.md#bind-the-saved-plan-to-its-hash-and-to-state)
   > as written reports `backend.tf` missing from the plan, and any mismatch is a STOP. Every root
   > change in this order is bound before it is applied, so work stays stopped here until a
   > reviewed decision is taken under explicit approval.
   >
   > **Warning:** From this step on, every root change is a campaign: its evidence set is redacted
   > at capture, swept and sealed, with a redaction filter and sweep that you supply yourself
   > ([Private working locations](#private-working-locations)).
4. **README step 2, the foundation, in two steps around the registrar change.** Follow steps 1 to
   8 of the [Normal path](public-dns-and-certificate.md#normal-path) of
   public-dns-and-certificate.md: build the zone on its own and read it back, run the pre-cutover
   checks and the registrar lock check, change the name servers at the registrar, verify
   delegation, run the CAA check, then plan and apply the rest of the root with the certificate and
   read the certificate back. The CAA check comes after delegation because until then the previous
   provider still answers for `<apex>`. Neither the lock check nor the CAA check has a reviewed
   procedure. PASS: the certificate apply reports 3 added, 0 changed, 0 destroyed, the certificate
   and hosted-zone read-backs pass, and the convergence plan exits 0. Then follow steps 1 and 2 of
   the [Normal path](persistent-foundations.md#normal-path) of persistent-foundations.md: read back
   the evidence-store controls, and connect the GitLab project to the CI push identity, with its
   trust and push-scope read-backs. PASS: all five evidence-store outputs equal their expected
   result, the sub-claim read-back is `["project_id", "ref_type", "ref"]`, the trust and push-scope
   read-backs pass, both masked variables exist, and no publish job declares `environment:`. Then
   continue at step 5, if it has not run yet.
   > **Warning:** On a build from nothing, the certificate-stage plan also creates the evidence
   > store, the registry repositories and the CI identity. That combined plan has never run and has
   > no reviewed shape, so Plan and apply the certificate stops at its step 2, and this step with
   > it. It can stop earlier, at the binding check of the zone build, the root's first apply
   > ([What these runbooks are](#scope)). Steps 5 and 6 do not need step 4.
   >
   > **Warning:** The Public DNS section of the foundation README gives the rebuild order only:
   > the zone, then the registrar change, then the rest of the root. Each stage runs through the
   > saved-plan procedures above, never as a direct `terraform apply`. The last stage is the
   > certificate stage, which on a build from nothing stops as the warning above says.
5. **README step 3, the Dev retained baseline.** Follow steps 1 to 4 of the
   [Normal path](dev-network.md#normal-path) of dev-network.md: check the zone mapping, build only
   the retained baseline in two targeted applies, confirm the retained and runtime split, and read
   back the network and the two Secrets Manager entries. PASS: state holds exactly the 21 retained
   addresses, the plan that is never applied shows exactly the 17 runtime creates with an empty
   drift list and both alerting variables `false`, and both read-backs pass. Then continue at
   step 6. Steps 5 and 6 need steps 1 to 3 only: neither Dev root's configuration reads anything
   from the foundation root, so they may run before step 4, or without it. The network stage is
   `terraform/dev`'s first apply, so it can stop at its binding check ([What these runbooks are](#scope)).
   > **Warning:** A plain `terraform apply` in `terraform/dev` creates billable runtime, whatever
   > the reason for it, an `operator_cidr` update included. Build only with the targeted stages,
   > steps 1 to 6 of
   > [Build only the retained baseline](dev-network.md#build-only-the-retained-baseline), whose
   > step 6 runs steps 3 and 4 of that Normal path (PASS: 14, then 7 `create` actions, each apply
   > reporting its plan's counts, and the three checks of its step 6 passing). Then continue at
   > step 6.
6. **README step 4, the Dev datastore.** Follow steps 1 to 8 of the
   [Normal path](dev-datastore.md#normal-path) of dev-datastore.md: Stage 1, the owner's one-time
   master placement, the Stage 2 plan with its secret-absence proof, the pre-apply gate, the Stage
   2 apply, read-back and convergence. PASS: its step 8, Confirm convergence, exits 0 with
   `No changes.` and all eight managed resources refreshed, the master opened and closed once, and
   the proof finds no occurrence. If you stop after Stage 1 and its read-backs, this step ends
   there, and the two checks below do not run: both need the instance. Otherwise take the first
   [CPU-credit reading](cost-and-residue.md#check-the-datastore-cpu-credits), steps 1 and 2 (PASS:
   every metric prints lines, `CPUSurplusCreditsCharged` is 0 in every period and
   `CPUSurplusCreditBalance` is 0 in the latest periods; a surplus balance with a documented cause,
   such as the start-up burst after a create, and nothing charged, is recorded as an explained
   review trigger, not a STOP). Then run
   [Verify the retained side with the datastore present](dev-network.md#verify-the-retained-side-with-the-datastore-present),
   steps 1 to 4 (PASS: exactly the security groups `cloud-platform-reference-dev-datastore` and
   `default`, the boundary and network read-backs pass, and the only network interface is the
   datastore's). Its PASS ends the Build order.
   > **Warning:** Reaching Stage 1 already needs what steps 2 and 3 and every campaign need from
   > you: the evidence tooling, the cost setup with, on a new account, the owner's decision on the
   > tag order, and a reviewed decision on binding the bootstrap Stage 1 plan ([What these runbooks
   > are](#scope)). Even with those, this step stops after Stage 1 and its read-backs, or earlier,
   > at the binding check of Stage 1, this root's first apply. The rest needs three things this
   > project has not published, which you supply yourself: a placement tool qualified offline,
   > without which the master value cannot be placed; a tool that implements the secret-absence
   > proof, without which the Stage 2 plan, the apply and the convergence plan do not start; and a
   > way to run the Stage 2 apply that closing or losing the terminal cannot end, without which that
   > apply does not run (dev-datastore.md, Reproducibility gaps).

The root builds in steps 3 to 6 run the shared Terraform procedures of terraform-operations.md
through their own runbook procedures, which name the steps to run, the PASS to reach and where to
return. In step 4 the zone stage skips convergence until the certificate apply. A later change to
a built root runs steps 1 to 13 of the [Normal path](terraform-operations.md#normal-path) of
terraform-operations.md: static checks, initialization, state inspection, debug logging off, a
saved plan with its review and binding, the owner's approval, one apply, the root's read-back,
convergence and the sealed evidence set. PASS: the step 12 convergence plan exits 0 with
`No changes.`, and step 13 has sealed the set. Then return to the work that needed the change.
From public material a later change currently stops before apply on every root; see the Normal
path's root table and [Known reproducibility gaps](#known-reproducibility-gaps). The targeted build
of `terraform/dev` is the exception to convergence: while no runtime exists, an untargeted plan
there shows the runtime still to add and exits 2, so Confirm convergence does not apply. Steps 4
and 6 of Build only the retained baseline hold the checks that replace it.

Open the campaign's evidence set before the change and seal it at the end: steps 1 to 7 of the
[Normal path](evidence-handling.md#normal-path) of evidence-handling.md, whose steps 4 to 7 seal
it. PASS: step 7's manifest check reports every entry OK, the set holds no file the manifest does
not list, and the manifest's full SHA-256 is in the private record outside the set. Then return to
the step of this list that sent you. In step 4, public-dns-and-certificate.md runs three
campaigns, the zone build, the cutover and the certificate, each sealed when it ends; in step 5,
Build only the retained baseline is one campaign, opened before its step 2 and sealed after its
step 6; in step 6, dev-datastore.md opens and closes its sets in its own steps. A long or
sensitive operation first checks session headroom and runs in an exported shell, where the task
runbook says so.

This path has not been run end to end from a fresh clone of the current configuration. The first
builds recorded for the bootstrap, foundation and Dev roots ran on earlier shapes of those roots.
The first-build forms for the current configuration are listed under Not yet exercised in
[terraform-operations.md](terraform-operations.md#not-yet-exercised),
[persistent-foundations.md](persistent-foundations.md#not-yet-exercised),
[public-dns-and-certificate.md](public-dns-and-certificate.md#not-yet-exercised) and
[dev-network.md](dev-network.md#not-yet-exercised), and the datastore's build order is in its
[README](../../terraform/dev-datastore/README.md#what-it-creates). That README's `-target` example
has never run; the published
[Stage 1](dev-datastore.md#stage-1-create-the-network-boundary-and-the-empty-secret-containers)
plans the root at commit `aeb1622` instead
([dev-datastore.md](dev-datastore.md#not-yet-exercised)).

## Routine operations

These recur during and after the build. Run only what the occasion calls for.

| When | Run |
|---|---|
| Before AWS work | [Sign in](operator-access.md#sign-in), [Verify the resolved identity](operator-access.md#verify-the-resolved-identity), [Check the account before AWS commands](operator-access.md#check-the-account-before-aws-commands) (PASS: `True` twice and `ACCOUNT_MATCH=PASS` on the profile the work uses; then return to the work) |
| Before a long or sensitive operation | [Check session headroom before long operations](operator-access.md#check-session-headroom-before-long-operations), then [Export role credentials once](operator-access.md#export-role-credentials-once) |
| Every change to a root | Steps 1 to 13 of the [Normal path](terraform-operations.md#normal-path) of terraform-operations.md, with the root's read-back. PASS: step 12 exits 0 with `No changes.` and step 13 has sealed the evidence set; then return to the work that needed the change. From public material a later change currently stops before apply on every root; see its root table and [Known reproducibility gaps](#known-reproducibility-gaps) |
| Before each billable change | [Read back the budget and its alert states](cost-and-residue.md#read-back-the-budget-and-its-alert-states), [Re-check prices before billable work](cost-and-residue.md#re-check-prices-before-billable-work) |
| Every campaign | Steps 1 to 7 of the [Normal path](evidence-handling.md#normal-path) of evidence-handling.md: capture with redaction, a sweep with its planted positive control, handling hits, sealing. Open the set before the operation and seal it when the operation ends. PASS: step 7's manifest check reports every entry OK, the set holds no file the manifest does not list, and the manifest's full SHA-256 is in the private record outside the set; then return to the work that opened the campaign. Steps 8 to 10 run only around a teardown (next row) |
| Around every teardown | [Export the sealed set before teardown](evidence-handling.md#export-the-sealed-set-before-teardown); after the teardown, [Run the orphan census](cost-and-residue.md#run-the-orphan-census), export the final set and [Read back exported evidence after destruction](evidence-handling.md#read-back-exported-evidence-after-destruction). The teardown itself belongs to runtime windows |
| Each operating session while the datastore exists | [Check the datastore CPU credits](cost-and-residue.md#check-the-datastore-cpu-credits) |
| Weekly, first due 2026-10-01 | [Record the weekly ADR-0013 review](cost-and-residue.md#record-the-weekly-adr-0013-review), after that week's budget read-back, CPU-credit check and [orphan census](cost-and-residue.md#run-the-orphan-census); [Break spend down with Cost Explorer](cost-and-residue.md#break-spend-down-with-cost-explorer) only when the budget figures cannot answer a cost question |
| When state may lag AWS | [Detect state drift](terraform-operations.md#detect-state-drift); reconcile only through [Reconcile explained state-only drift](terraform-operations.md#reconcile-explained-state-only-drift) |
| When a budget level is reached or projected | [Respond to the 100, 150 and 200 USD levels](cost-and-residue.md#respond-to-the-100-150-and-200-usd-levels) |

## Find the procedure for a task

| I need to... | Runbook | Procedure |
|---|---|---|
| Install Terraform and prove it is HashiCorp's release | [operator-access.md](operator-access.md) | [Prepare the workstation toolchain](operator-access.md#prepare-the-workstation-toolchain) |
| Enable Organizations and Identity Center on a new account | [operator-access.md](operator-access.md) | [Enable Organizations and Identity Center](operator-access.md#enable-organizations-and-identity-center) |
| Give a new operator access | [operator-access.md](operator-access.md) | [Set up an operator in Identity Center](operator-access.md#set-up-an-operator-in-identity-center), [Configure the local CLI profiles](operator-access.md#configure-the-local-cli-profiles) |
| Sign in and confirm the identity and the account | [operator-access.md](operator-access.md) | [Sign in](operator-access.md#sign-in), [Verify the resolved identity](operator-access.md#verify-the-resolved-identity), [Check the account before AWS commands](operator-access.md#check-the-account-before-aws-commands) |
| Prepare a shell for a long or sensitive operation | [operator-access.md](operator-access.md) | [Check session headroom before long operations](operator-access.md#check-session-headroom-before-long-operations), [Export role credentials once](operator-access.md#export-role-credentials-once) |
| Retire a human IAM user's access key or console password | [operator-access.md](operator-access.md) | [Retire legacy IAM user credentials](operator-access.md#retire-legacy-iam-user-credentials) |
| Build the state backend | [terraform-operations.md](terraform-operations.md) | [Build the state backend and migrate into it](terraform-operations.md#build-the-state-backend-and-migrate-into-it) |
| Change a Terraform root | [terraform-operations.md](terraform-operations.md) | [Normal path](terraform-operations.md#normal-path), steps 1 to 13, done when step 12 exits 0 with `No changes.` and step 13 has sealed the evidence set; then return to the work that needed the change (currently stops before apply on every root; see the path's root table) |
| Read state without writing it, or plan without taking the lock | [terraform-operations.md](terraform-operations.md) | [Inspect state without writing it](terraform-operations.md#inspect-state-without-writing-it), [Plan without taking the state lock](terraform-operations.md#plan-without-taking-the-state-lock) |
| Change resource addresses in a refactor | [terraform-operations.md](terraform-operations.md) | [Move resource addresses with moved blocks](terraform-operations.md#move-resource-addresses-with-moved-blocks) (stops as the Normal path's root table says; see [Known reproducibility gaps](#known-reproducibility-gaps)) |
| Find out whether state lags AWS, and reconcile it | [terraform-operations.md](terraform-operations.md) | [Detect state drift](terraform-operations.md#detect-state-drift), [Reconcile explained state-only drift](terraform-operations.md#reconcile-explained-state-only-drift) |
| Deal with a held state lock or a failed apply | [terraform-operations.md](terraform-operations.md) | [Handle a held state lock](terraform-operations.md#handle-a-held-state-lock), [Stop after a failed or interrupted apply](terraform-operations.md#stop-after-a-failed-or-interrupted-apply) |
| Build the public zone and delegate the domain to it | [public-dns-and-certificate.md](public-dns-and-certificate.md) | [Build the zone on its own](public-dns-and-certificate.md#build-the-zone-on-its-own), [Read back the hosted zone](public-dns-and-certificate.md#read-back-the-hosted-zone), [Pre-cutover checks](public-dns-and-certificate.md#pre-cutover-checks), [Registrar lock check](public-dns-and-certificate.md#registrar-lock-check), [Change the name servers at the registrar](public-dns-and-certificate.md#change-the-name-servers-at-the-registrar), [Verify delegation](public-dns-and-certificate.md#verify-delegation), [CAA check](public-dns-and-certificate.md#caa-check) |
| Issue the certificate and check it | [public-dns-and-certificate.md](public-dns-and-certificate.md) | [Plan and apply the certificate](public-dns-and-certificate.md#plan-and-apply-the-certificate), [Read back the certificate](public-dns-and-certificate.md#read-back-the-certificate) |
| Undo the registrar change, or retire the zone at project end | [public-dns-and-certificate.md](public-dns-and-certificate.md) | [Roll back the delegation](public-dns-and-certificate.md#roll-back-the-delegation), [Retire the hosted zone](public-dns-and-certificate.md#retire-the-hosted-zone) |
| Check the evidence store's protections | [persistent-foundations.md](persistent-foundations.md) | [Read back the evidence-store controls](persistent-foundations.md#read-back-the-evidence-store-controls) |
| Let a GitLab project's pipelines push images, and check the trust and push scope | [persistent-foundations.md](persistent-foundations.md) | [Connect a GitLab project to the CI push identity](persistent-foundations.md#connect-a-gitlab-project-to-the-ci-push-identity), [Read back the CI trust](persistent-foundations.md#read-back-the-ci-trust), [Read back the CI push scope](persistent-foundations.md#read-back-the-ci-push-scope) |
| Add a registry repository for a new service | [persistent-foundations.md](persistent-foundations.md) | [Add a registry repository and widen the CI push scope](persistent-foundations.md#add-a-registry-repository-and-widen-the-ci-push-scope) (stops at state inspection without the last apply's address list; see [Known reproducibility gaps](#known-reproducibility-gaps)) |
| Confirm an image digest in the registry | [persistent-foundations.md](persistent-foundations.md) | [Verify an image in the registry by digest](persistent-foundations.md#verify-an-image-in-the-registry-by-digest) |
| Find out why a publish job failed | [persistent-foundations.md](persistent-foundations.md) | [Diagnose a failed publication](persistent-foundations.md#diagnose-a-failed-publication) |
| Build the Dev network without a runtime | [dev-network.md](dev-network.md) | [Check the zone mapping before the first build](dev-network.md#check-the-zone-mapping-before-the-first-build), [Build only the retained baseline](dev-network.md#build-only-the-retained-baseline) |
| Confirm Dev state holds only the retained baseline | [dev-network.md](dev-network.md) | [Confirm the retained and runtime split](dev-network.md#confirm-the-retained-and-runtime-split) |
| Read the Dev network and its secrets back from AWS | [dev-network.md](dev-network.md) | [Read back the retained network](dev-network.md#read-back-the-retained-network), [Read back the two Secrets Manager entries](dev-network.md#read-back-the-two-secrets-manager-entries), [Verify the retained side with the datastore present](dev-network.md#verify-the-retained-side-with-the-datastore-present) |
| Build the Dev datastore | [dev-datastore.md](dev-datastore.md) | [Normal path](dev-datastore.md#normal-path), from [Stage 1](dev-datastore.md#stage-1-create-the-network-boundary-and-the-empty-secret-containers) to [Confirm convergence](dev-datastore.md#confirm-convergence) |
| Place the datastore master value | [dev-datastore.md](dev-datastore.md) | [Place the master value](dev-datastore.md#place-the-master-value) |
| Check the datastore's network and secrets without reading a value | [dev-datastore.md](dev-datastore.md) | [Read back the network boundary](dev-datastore.md#read-back-the-network-boundary), [Verify the secret containers without reading a value](dev-datastore.md#verify-the-secret-containers-without-reading-a-value), [Account for secret reads and writes in CloudTrail](dev-datastore.md#account-for-secret-reads-and-writes-in-cloudtrail) |
| Prove the master value is in no plan, state or log | [dev-datastore.md](dev-datastore.md) | [Prove the master value is absent from plans, state and logs](dev-datastore.md#prove-the-master-value-is-absent-from-plans-state-and-logs) |
| Check the budget, the prices or the cost-allocation tags | [cost-and-residue.md](cost-and-residue.md) | [Read back the budget and its alert states](cost-and-residue.md#read-back-the-budget-and-its-alert-states), [Re-check prices before billable work](cost-and-residue.md#re-check-prices-before-billable-work), [Read back the cost-allocation tags](cost-and-residue.md#read-back-the-cost-allocation-tags) |
| Explain where spend went | [cost-and-residue.md](cost-and-residue.md) | [Break spend down with Cost Explorer](cost-and-residue.md#break-spend-down-with-cost-explorer) |
| Check the datastore's CPU credits, or record the weekly review | [cost-and-residue.md](cost-and-residue.md) | [Check the datastore CPU credits](cost-and-residue.md#check-the-datastore-cpu-credits), [Record the weekly ADR-0013 review](cost-and-residue.md#record-the-weekly-adr-0013-review) |
| Respond to a budget alert | [cost-and-residue.md](cost-and-residue.md) | [Respond to the 100, 150 and 200 USD levels](cost-and-residue.md#respond-to-the-100-150-and-200-usd-levels) |
| Find and remove resources left behind | [cost-and-residue.md](cost-and-residue.md) | [Run the orphan census](cost-and-residue.md#run-the-orphan-census), [Clean up an orphan](cost-and-residue.md#clean-up-an-orphan) |
| Keep evidence of a campaign | [evidence-handling.md](evidence-handling.md) | [Capture a campaign evidence set](evidence-handling.md#capture-a-campaign-evidence-set), [Redact at capture](evidence-handling.md#redact-at-capture) |
| Check an evidence set for private values and seal it | [evidence-handling.md](evidence-handling.md) | [Sweep the set before sealing](evidence-handling.md#sweep-the-set-before-sealing), [Plant a positive control for the sweep](evidence-handling.md#plant-a-positive-control-for-the-sweep), [Handle sweep hits before sealing](evidence-handling.md#handle-sweep-hits-before-sealing), [Seal the set and verify the manifest](evidence-handling.md#seal-the-set-and-verify-the-manifest) |
| Export evidence before a teardown and check it afterwards | [evidence-handling.md](evidence-handling.md) | [Export the sealed set before teardown](evidence-handling.md#export-the-sealed-set-before-teardown), [Read back exported evidence after destruction](evidence-handling.md#read-back-exported-evidence-after-destruction) |
| Remove a prohibited value from retained or exported evidence | [evidence-handling.md](evidence-handling.md) | [Remediate a prohibited value in retained or exported evidence](evidence-handling.md#remediate-a-prohibited-value-in-retained-or-exported-evidence) |
| Recover from a failure or an exposure | See [When something fails](#when-something-fails) | |
| Create the budget, activate the tags, mirror a platform image, place a Dev secret value, recover state, or decommission a root | No published procedure | [Known reproducibility gaps](#known-reproducibility-gaps) |

## Known reproducibility gaps

What a new engineer cannot yet reproduce from the public repositories alone, grouped from each
runbook's **Reproducibility gaps** section, which has the detail. Separately, most published command
forms have not been executed as written; each procedure's Engineering notes say what its form is
derived from.

| Area | What cannot be reproduced | Public contract that exists | Needed later |
|---|---|---|---|
| Identity Center setup ([operator-access.md](operator-access.md#reproducibility-gaps)) | Enabling Organizations and Identity Center, which this project never did; the operator setup as it ran, in a root-user session with no output kept, or by any other identity; the `AdministratorAccess` contents, never recorded; a measured MFA check | [ADR-0005](../decisions/0005-adopt-centralized-identity-and-least-privilege-access.md); the console steps; the permission-set names and session durations | An exercised setup procedure; the deferred ADR-0005 decision on the contents, which is a decision, not a tool; a measured MFA check |
| Operator access after setup ([operator-access.md](operator-access.md#reproducibility-gaps)) | Revoking access, replacing a lost MFA device, break-glass recovery, verifying the root posture, access review, signing out; finding what an arbitrary command changed in another account | ADR-0005 for break-glass recovery; [Recover from a wrong account](operator-access.md#recover-from-a-wrong-account), part B | New public procedures |
| Runtime windows (outside the suite) | Creating, operating and tearing down a runtime window: the EKS cluster, its nodes and the NAT gateway on top of the retained baseline, which README step 5 needs | The windows that ran, summarized in [Runtime Validation](../validation/runtime-validation.md); the runtime design in the [Dev root README](../../terraform/dev/README.md) | A published runtime-window procedure |
| Access tooling ([operator-access.md](operator-access.md#reproducibility-gaps)) | The private export wrapper and account helper behind the recorded runs. The published export block reproduces none of the wrapper's controls, the published account check has never run against AWS, and refusals ran only offline against the private tools | The published export block, `account_check` function and expiry comparison; `allowed_account_ids` in each root's `providers.tf`; the documented HOLD and STOP conditions | A public tool, only if the wrapper's controls are to be reproduced; a recorded run and a public offline qualification of the published forms |
| Toolchain ([operator-access.md](operator-access.md#reproducibility-gaps), [terraform-operations.md](terraform-operations.md#reproducibility-gaps), [cost-and-residue.md](cost-and-residue.md#reproducibility-gaps)) | The AWS CLI version; the Terraform version of every earlier apply; platforms other than `darwin_arm64`; a direct archive install; a registry provider install; platforms the lock files do not cover; the binding check on any Terraform other than 1.15.5 | Terraform 1.15.5 with its provenance check; each root's `versions.tf`; the committed lock files pinning `hashicorp/aws` 6.58.0 | No new tool: runs of the published forms on other platforms and installs; a reviewed lock-file change for a new platform; a layout re-check after a Terraform upgrade; a run that records the CLI version |
| Executed forms ([terraform-operations.md](terraform-operations.md#reproducibility-gaps), [persistent-foundations.md](persistent-foundations.md#reproducibility-gaps), [dev-network.md](dev-network.md#reproducibility-gaps), [public-dns-and-certificate.md](public-dns-and-certificate.md#reproducibility-gaps)) | The private checkers, wrappers and tools behind the recorded Terraform, foundation, Dev network and DNS runs, including a push-scope read-back that allowed repeated reads; Dev network forms that have never run as written | The published command forms, labeled not executed as written, with their expected results, STOP conditions and the rules they implement | No new tool is named: each form rests on the private tooling's evidence until it runs as written with its output retained. A published checker only to reproduce the DNS offline qualification |
| First builds ([terraform-operations.md](terraform-operations.md#reproducibility-gaps), [persistent-foundations.md](persistent-foundations.md#reproducibility-gaps), [public-dns-and-certificate.md](public-dns-and-certificate.md#reproducibility-gaps)) | The backend's first build from a fresh clone, with review and binding of a Stage 1 plan on local state; the foundation's first build, whose combined plan with the certificate has never run; the zone build in its `-target` form; the binding check on a root's first apply, whose state read against a never-written state object is not recorded | The bootstrap README's Stage 1 and Stage 2, without commands; the foundation README's [Public DNS](../../terraform/foundation/README.md#public-dns) order; the certificate's three-address plan shape, which assumes the rest of the root exists | A Stage 1 form for local state; a reviewed plan shape for the foundation's first build; a first run of the targeted zone build; a recorded first-apply binding read and its PASS condition |
| Later changes to applied roots ([terraform-operations.md](terraform-operations.md#reproducibility-gaps)) | A later reviewed change reaching apply: `terraform/bootstrap` has no published read-back, `terraform/foundation` has no published expected address set (the list is in the last apply's private evidence), and `terraform/dev` and `terraform/dev-datastore` have no later-change procedure or gate | The Normal path of terraform-operations.md and its root table | A published read-back for the backend; an expected address set for the foundation; later-change procedures for the dev and datastore roots |
| Terraform recovery ([terraform-operations.md](terraform-operations.md#reproducibility-gaps)) | State recovery from a prior object version, mandatory under ADR-0011; recovery after a failed or interrupted apply; migrating state out and decommissioning the backend; releasing a lock found by listing | The bootstrap README's [Recovery](../../terraform/bootstrap/README.md#recovery) and [Final decommission](../../terraform/bootstrap/README.md#final-decommission) outlines; [Stop after a failed or interrupted apply](terraform-operations.md#stop-after-a-failed-or-interrupted-apply); [Handle a held state lock](terraform-operations.md#handle-a-held-state-lock) | Reviewed recovery procedures; decommission commands; a way to obtain a lock ID |
| Plan artifacts and scan decisions ([terraform-operations.md](terraform-operations.md#reproducibility-gaps)) | When saved plans, plan JSON, logs and working trees with filled inputs are deleted; the unpublished rationale for scan findings accepted after the 2026-09-21 scan | The `<private-dir>` and `<work-dir>` conventions; the class comparison in [Run the static checks](terraform-operations.md#run-the-static-checks) | A deletion rule. For the rationale, no procedure or tool |
| Budget, tags and Cost Explorer ([cost-and-residue.md](cost-and-residue.md#reproducibility-gaps)) | Creating the budget and its five notifications; activating the six cost-allocation tags, with an order for a new account, where a key can be activated only after a resource carries it; enabling Cost Explorer | ADR-0013; the budget's shape under [Background prerequisites](cost-and-residue.md#background-prerequisites); the budget and tag read-backs | Public creation and activation procedures, the activation with its place in the build order; a written console procedure for Cost Explorer, which the API cannot enable |
| Cost operations ([cost-and-residue.md](cost-and-residue.md#reproducibility-gaps)) | A written re-estimate for a rate the price table lacks, such as S3 storage; ledger reconciliation; resuming after an ADR-0013 stop condition, and investigating unexplained spend; the response to a CPU-credit REVIEW; ADR-0013's other weekly duties; cleanup beyond one SNS subscription | ADR-0013; the detecting procedures; the datastore [Decommission](../../terraform/dev-datastore/README.md#decommission) design; [Clean up an orphan](cost-and-residue.md#clean-up-an-orphan) | Public procedures for each; a cleanup procedure per class when it is first needed |
| Orphan census ([cost-and-residue.md](cost-and-residue.md#reproducibility-gaps)) | The private census tool behind the retained results, and the offline controls that exercised it | The published census, its fail-closed rule and its expected-class table | A live run and an offline-controlled run of the published helpers; no public harness for the controls exists |
| Registrar and domain ([public-dns-and-certificate.md](public-dns-and-certificate.md#reproducibility-gaps)) | The registrar change as made by hand; how the RDAP base URL was found; a registrar lock check, which never ran, and a CAA check, whose design-review lookup kept no output; DS handling and record migration; an apex under a multi-label public suffix; registration and renewal, attested only | The registrar-neutral steps, proven by [Verify delegation](public-dns-and-certificate.md#verify-delegation); IANA's RDAP bootstrap file; the lock, CAA and DS requirements; [ADR-0018](../decisions/0018-define-the-public-entry-implementation-dns-and-certificate-model.md), which defers renewal | No tool for the registrar change or RDAP. A reviewed lock check; CAA, DS, migration and multi-label forms for a reproducer who needs them; the deferred renewal procedure |
| DNS and certificate lifecycle ([public-dns-and-certificate.md](public-dns-and-certificate.md#reproducibility-gaps)) | Certificate renewal, replacement, retirement, a stalled validation and the `PENDING_VALIDATION` scan; the destroy step of zone retirement; zone recovery and re-adoption after state loss; periodic re-verification; the private rollback inputs | The ordering rule in Public DNS; the stop conditions and status check; the checks in [Retire the hosted zone](public-dns-and-certificate.md#retire-the-hosted-zone); ADR-0011's rebuild-first posture; [Roll back the delegation](public-dns-and-certificate.md#roll-back-the-delegation), never executed | Reviewed procedures and an ACM class in the orphan census; a targeted destroy; recovery and import procedures; a cadence. No tool for the rollback inputs: each reproducer takes their own |
| Registry and CI trust ([persistent-foundations.md](persistent-foundations.md#reproducibility-gaps)) | Mirroring a platform image into `platform/`, which must hold the pinned image by digest before any runtime uses it; revoking or rotating the CI push trust; rebuilding a lost repository or image, which yields a new digest | The repository outside the push scope; [Verify an image in the registry by digest](persistent-foundations.md#verify-an-image-in-the-registry-by-digest); ADR-0015, ADR-0017 and ADR-0009; the one trusted subject built from `gitlab_project_id` | A public mirroring procedure with its admission, with no tool named beyond `crane`; a trust revoke-and-rotate procedure; an exercised rebuild procedure |
| GitLab side of the CI identity ([persistent-foundations.md](persistent-foundations.md#reproducibility-gaps)) | The exact API call and the temporary token's role and scope; whether the UI exposes the setting; whether the two variables are protected | The required read-back, the trusted subject in `ci-identity.tf`, and the variables' shapes in [Connect a GitLab project to the CI push identity](persistent-foundations.md#connect-a-gitlab-project-to-the-ci-push-identity) | A recorded, published form of the GitLab change |
| Secret placement ([dev-datastore.md](dev-datastore.md#reproducibility-gaps), [dev-network.md](dev-network.md#reproducibility-gaps)) | Placing the master value as it ran: the tool is not published, and an equivalent tool has never run. Placing the Dev workload secret and the deploy key's private key | [Place the master value](dev-datastore.md#place-the-master-value) and [Respond to a failed or uncertain placement](dev-datastore.md#respond-to-a-failed-or-uncertain-placement); the two empty Dev containers and their metadata read-back | A public tool or runnable procedure for the master value; a public placement procedure for both Dev values before a runtime window uses them |
| Datastore tooling ([dev-datastore.md](dev-datastore.md#reproducibility-gaps)) | The secret-absence proof tool; the Stage 2 apply's hang-up protection; the allowlisted run environment; the 48-property plan review; the single-use pre-apply gate; the reads for the apply's other management events | The proof method; the hang-up requirement; the exported shell and the debug-logging check; the Stage 2 value checks; the gate checklist; the Secrets Manager CloudTrail check | A public proof tool; a published, exercised hang-up protection; an environment record, only if the allowlist is to be reproduced; checks for the extra plan properties, only if a reproducer needs them; a gate run as written, and one for later applies; a command for the other events |
| Dev network lifecycle ([dev-network.md](dev-network.md#reproducibility-gaps)) | Decommission; partial-apply recovery that keeps the 21 retained addresses; secret deletion and recovery, which ADR-0011 requires; AWS read-back of the Parameter Store entry and the Pod Identity roles; address, zone or `Name` changes after the first build | The decommission order; read-only inspection after a failed apply; the configured seven-day recovery window; the root README's configuration; a zone change before the first build | Reviewed procedures for each; a change procedure covering the datastore root's plan, only if a built environment must change |
| Evidence tooling ([evidence-handling.md](evidence-handling.md#reproducibility-gaps)) | The redaction filter and sweep; the literal list and allowlist values; export, read-back and remediation as runnable commands; the private record's format | The published methods and the positive control; the list's classes and ranges; what the record must hold | A public filter and sweep; a procedure that reads the cluster service range, while the list stays private by design; published command forms run as written; a record format, location and retention |
| Evidence operations ([evidence-handling.md](evidence-handling.md#reproducibility-gaps)) | The response to an export refusal, an unavailable destination or a failed read-back; when a campaign that destroyed nothing is exported (the 2026-09 applies have not been); the retention review; a temporary-directory check; clearing a set for publication; the destination's access model and retention | ADR-0013's stop condition and weekly review; the publication rule in [Public and private evidence](evidence-handling.md#public-and-private-evidence); the foundation README | A halt, continue and resume rule; an export rule; review, check and publication-scan procedures; an access definition and a retention rule |
| Retained evidence ([operator-access.md](operator-access.md#reproducibility-gaps), [evidence-handling.md](evidence-handling.md#reproducibility-gaps)) | The private evidence behind every label | The labels and evidence-basis rows, and small derived evidence in the public repository | None: raw evidence stays private by design |

## Not yet exercised

Each runbook ends with a **Not yet exercised** list: procedures, steps and operations that are
designed but have never run, or have no reviewed procedure at all. A procedure labeled
DESIGNED-NOT-EXECUTED or UNEXERCISED has never run. Read the list before relying on a procedure.

- [operator-access.md](operator-access.md#not-yet-exercised): Identity Center enablement, part A of
  the wrong-account response, recovery from credential expiry mid-run, and operator access after
  setup.
- [terraform-operations.md](terraform-operations.md#not-yet-exercised): state recovery, recovery
  after a failed apply, the backend's first build from a fresh clone and its decommission, and lock
  contention.
- [persistent-foundations.md](persistent-foundations.md#not-yet-exercised): the first build on the
  current root, trust rotation, and registry rebuild and decommission.
- [public-dns-and-certificate.md](public-dns-and-certificate.md#not-yet-exercised): the targeted zone
  build, rollback, zone retirement and the certificate after issuance.
- [dev-network.md](dev-network.md#not-yet-exercised): the targeted build as published,
  decommission, and secret deletion and recovery.
- [dev-datastore.md](dev-datastore.md#not-yet-exercised): the reusable pre-apply gate, rotation,
  restore, maintenance and decommission.
- [cost-and-residue.md](cost-and-residue.md#not-yet-exercised): budget creation and tag activation
  as procedures, the weekly review, the budget-level responses and most cleanup classes.
- [evidence-handling.md](evidence-handling.md#not-yet-exercised): export as published, the planted
  positive control, the remediation checks and the retention review.

## Validation labels

Each procedure opens with a **Validation** line: its label, and whether its **Published command
form** is the one that ran. Its Engineering notes table gives the validation status with its date,
the published form with what it is derived from, the evidence it rests on, the authority it needs
and its cost in absolute USD. Labels are assigned per procedure, never per resource, and
conservatively. A label is never upgraded without new retained evidence of that procedure. Each
label carries the date of the execution it rests on, or `never`; where parts of one procedure rest
on different evidence, each part carries its own label.

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

<a id="when-to-stop"></a>

## When something fails

A STOP halts the procedure where it occurs, and no mutating step is retried to make it go away. A
HOLD halts work the same way. The owning procedure's **STOP if** and **If it fails** say what to
inspect and where to go. Where it has no written resume procedure, work stays stopped until a
reviewed decision is taken under explicit approval.

| What happened | Go to |
|---|---|
| A read-only command fails on an expired or missing token | [Recover from session expiry](operator-access.md#recover-from-session-expiry) |
| Credentials expire during a run, or a command that could have written state fails on an expired or missing token | [Recover from credential expiry mid-run](operator-access.md#recover-from-credential-expiry-mid-run); do not re-run the command |
| The identity check errors or prints `False`, or the account check prints `ACCOUNT_MATCH=HOLD` | [Recover from a wrong account](operator-access.md#recover-from-a-wrong-account), part A |
| A mutating command already ran against another account | [Recover from a wrong account](operator-access.md#recover-from-a-wrong-account), part B |
| The credential's headroom is below what the operation needs | [Check session headroom before long operations](operator-access.md#check-session-headroom-before-long-operations) |
| A fingerprint, signature, checksum or binary hash differs | [Prepare the workstation toolchain](operator-access.md#prepare-the-workstation-toolchain) |
| A static check fails, `init` changes the lock file, or the scan adds a finding class | [Run the static checks](terraform-operations.md#run-the-static-checks) |
| `init` reports a backend change or a state migration, or Git does not ignore an input file | [Initialize a root against the state backend](terraform-operations.md#initialize-a-root-against-the-state-backend) |
| A `TF_*` variable is set in the shell | [Keep Terraform debug logging off](terraform-operations.md#keep-terraform-debug-logging-off) |
| The saved plan differs from the reviewed list, or its hash, configuration, lock file, serial or lineage no longer matches | [Review the saved plan](terraform-operations.md#review-the-saved-plan), [Bind the saved plan to its hash and to state](terraform-operations.md#bind-the-saved-plan-to-its-hash-and-to-state) |
| The state backend's Stage 1 apply or its migration fails or is interrupted | [Build the state backend and migrate into it](terraform-operations.md#build-the-state-backend-and-migrate-into-it), **If it fails**: run neither again, never pass `-force-copy`, and leave the local state and its backup where they are |
| Any other apply fails, is interrupted, loses its terminal or session, or reports a different summary | [Stop after a failed or interrupted apply](terraform-operations.md#stop-after-a-failed-or-interrupted-apply); on the datastore root, with [Read the datastore after a failed or interrupted apply](dev-datastore.md#read-the-datastore-after-a-failed-or-interrupted-apply) |
| `Error acquiring the state lock` | [Handle a held state lock](terraform-operations.md#handle-a-held-state-lock). If an apply reported it, the apply failed: first follow [Stop after a failed or interrupted apply](terraform-operations.md#stop-after-a-failed-or-interrupted-apply) through its step 7 and stop at its **Next step**, the owner's reviewed recovery decision. Return to Handle a held state lock, step 1, only if that decision says so; its step 7 is then already done |
| A convergence plan exits 1 or 2, or a refresh-only plan reports drift | [Confirm convergence](terraform-operations.md#confirm-convergence); [Detect state drift](terraform-operations.md#detect-state-drift), then [Reconcile explained state-only drift](terraform-operations.md#reconcile-explained-state-only-drift) |
| Before the registrar change: a DS record at the parent, a Route 53 server not answering authoritatively, or parent servers that disagree | [Pre-cutover checks](public-dns-and-certificate.md#pre-cutover-checks) |
| The registrar refuses the change, or asks to change anything besides the name servers | [Change the name servers at the registrar](public-dns-and-certificate.md#change-the-name-servers-at-the-registrar) |
| After it: a parent server's referral is MIXED or WRONG, or a Route 53 server stops answering authoritatively | [Verify delegation](public-dns-and-certificate.md#verify-delegation), then [Roll back the delegation](public-dns-and-certificate.md#roll-back-the-delegation) |
| The certificate plan differs from its shape, or DNS validation does not complete; a certificate check fails | [Plan and apply the certificate](public-dns-and-certificate.md#plan-and-apply-the-certificate), [Read back the certificate](public-dns-and-certificate.md#read-back-the-certificate) |
| An evidence-store control, the CI trust or the CI push scope differs from its expected result | [Read back the evidence-store controls](persistent-foundations.md#read-back-the-evidence-store-controls), [Read back the CI trust](persistent-foundations.md#read-back-the-ci-trust), [Read back the CI push scope](persistent-foundations.md#read-back-the-ci-push-scope) |
| A publish job fails, or a registry manifest does not hash to its digest | [Diagnose a failed publication](persistent-foundations.md#diagnose-a-failed-publication), [Verify an image in the registry by digest](persistent-foundations.md#verify-an-image-in-the-registry-by-digest) |
| A zone is unavailable or excluded by EKS, or the node type or the engine is not offered in both zones | [Check the zone mapping before the first build](dev-network.md#check-the-zone-mapping-before-the-first-build) |
| A Dev plan holds a runtime or alerting-campaign address, or Dev state holds an address outside the 21 retained addresses between windows | [Build only the retained baseline](dev-network.md#build-only-the-retained-baseline), [Confirm the retained and runtime split](dev-network.md#confirm-the-retained-and-runtime-split) |
| A Dev network or secret value differs, or an unexpected security group or network interface is in the Dev VPC between windows | [Read back the retained network](dev-network.md#read-back-the-retained-network), [Read back the two Secrets Manager entries](dev-network.md#read-back-the-two-secrets-manager-entries), [Verify the retained side with the datastore present](dev-network.md#verify-the-retained-side-with-the-datastore-present) |
| A datastore secret container holds an unexpected version, stage, key or deletion date, or CloudTrail shows an unexpected Secrets Manager read or write | [Verify the secret containers without reading a value](dev-datastore.md#verify-the-secret-containers-without-reading-a-value), [Account for secret reads and writes in CloudTrail](dev-datastore.md#account-for-secret-reads-and-writes-in-cloudtrail) |
| A placement ends in any outcome other than placed | [Respond to a failed or uncertain placement](dev-datastore.md#respond-to-a-failed-or-uncertain-placement) |
| A secret-absence proof finds the value or cannot complete, the value appears anywhere, or CloudTrail shows an unexplained read of the master | [Contain an exposed or unproven master value](dev-datastore.md#contain-an-exposed-or-unproven-master-value) |
| A pre-apply gate check fails or cannot be read, or an instance or parameter value differs | [Run the pre-apply gate](dev-datastore.md#run-the-pre-apply-gate), [Read back the instance and its endpoint parameter](dev-datastore.md#read-back-the-instance-and-its-endpoint-parameter) |
| The budget, a notification or a subscriber is missing or changed, or a cost-allocation tag key is missing or inactive | [Read back the budget and its alert states](cost-and-residue.md#read-back-the-budget-and-its-alert-states), [Read back the cost-allocation tags](cost-and-residue.md#read-back-the-cost-allocation-tags) |
| A notification in `ALARM`, or spend reaching or projected to reach 100, 150 or 200 USD | [Respond to the 100, 150 and 200 USD levels](cost-and-residue.md#respond-to-the-100-150-and-200-usd-levels) |
| A price differs from the table, or a spend line maps to no known resource | [Re-check prices before billable work](cost-and-residue.md#re-check-prices-before-billable-work), [Break spend down with Cost Explorer](cost-and-residue.md#break-spend-down-with-cost-explorer) |
| Surplus CPU credits charged, or a weekly review missed | [Check the datastore CPU credits](cost-and-residue.md#check-the-datastore-cpu-credits), [Record the weekly ADR-0013 review](cost-and-residue.md#record-the-weekly-adr-0013-review) |
| The census prints `UNKNOWN`, or a runtime class stays above 0 | [Run the orphan census](cost-and-residue.md#run-the-orphan-census), then [Clean up an orphan](cost-and-residue.md#clean-up-an-orphan) |
| A sweep hit, a file the sweep cannot inspect, or a planted control the sweep misses | [Sweep the set before sealing](evidence-handling.md#sweep-the-set-before-sealing), [Plant a positive control for the sweep](evidence-handling.md#plant-a-positive-control-for-the-sweep), [Handle sweep hits before sealing](evidence-handling.md#handle-sweep-hits-before-sealing) |
| A manifest entry fails, an export count or digest differs, or an exported object is mismatched, missing or extra at read-back | [Seal the set and verify the manifest](evidence-handling.md#seal-the-set-and-verify-the-manifest), [Export the sealed set before teardown](evidence-handling.md#export-the-sealed-set-before-teardown), [Read back exported evidence after destruction](evidence-handling.md#read-back-exported-evidence-after-destruction) |
| A prohibited value in a sealed or exported set | [Remediate a prohibited value in retained or exported evidence](evidence-handling.md#remediate-a-prohibited-value-in-retained-or-exported-evidence) |

## Conventions

- **Placeholders.** Angle brackets stand wherever a real value would go, for example `<profile>`,
  `<allowed-account-id>`, `<state-bucket>`, `<evidence-bucket>`, `<apex>`, `<private-dir>`,
  `<plan-file>` and `<commit>`. Each runbook defines the ones it uses; the Terraform placeholders
  are defined in [terraform-operations.md](terraform-operations.md#before-you-start).
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
  every plan and apply of a configuration that contains `database.tf`
  ([Keep Terraform debug logging off](terraform-operations.md#keep-terraform-debug-logging-off)).
- **Explicit owner approval before any mutation.** The owner is the person accountable for the AWS
  account. No AWS, IAM, state, registrar or GitLab setting is changed, and no secret value is
  placed, without the owner's written approval given before the step. An approval covers the step
  it names: an apply approval names the saved plan's sha256, and a refresh-only apply needs its own.
  Read-only procedures need none, except a run that reads the datastore master value, such as any
  plan of `terraform/dev-datastore` from a configuration that contains `database.tf`
  ([Approvals](#approvals)).
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
