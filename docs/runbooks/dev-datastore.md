# Dev Datastore Runbook

This runbook operates [terraform/dev-datastore](../../terraform/dev-datastore/README.md): its two
secret containers, the one-time placement of the master value, and the two-stage build of the
PostgreSQL instance and its endpoint parameter, with the checks that show each step did what it
should and nothing more. It does not cover runtime windows, the bounded periods that create the EKS
cluster, its nodes and the NAT gateway on top of the retained baseline (what the Dev network root
keeps in AWS between windows, [dev-network.md](dev-network.md)) and destroy them at close, or any
workload use of the datastore: both are in [Runtime validation](../validation/runtime-validation.md). Rotation,
restore, maintenance and decommission have no exercised procedure here
([Not yet exercised](#not-yet-exercised)).

The root README stays the authority for what the root creates and why
([What it creates](../../terraform/dev-datastore/README.md#what-it-creates)), what it leaves out
([What this root does not create](../../terraform/dev-datastore/README.md#what-this-root-does-not-create)),
the network [Boundary](../../terraform/dev-datastore/README.md#boundary), the
[Debug logging](../../terraform/dev-datastore/README.md#debug-logging) rule,
[Decommission](../../terraform/dev-datastore/README.md#decommission) with the cost figures, and the
measured [Status](../../terraform/dev-datastore/README.md#status). The reasoning is in
[ADR-0008](../decisions/0008-define-the-secrets-and-workload-identity-model.md) (secrets),
[ADR-0011](../decisions/0011-define-the-backup-and-recovery-model.md) (recovery),
[ADR-0012](../decisions/0012-formalize-the-reference-workload.md) (workload data) and
[ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md) (cost and operations).
Build this root only through this page's [Normal path](#normal-path).

## Normal path

Follow these in order. Each link opens the full procedure.

1. [Stage 1: create the network boundary and the empty secret containers](#stage-1-create-the-network-boundary-and-the-empty-secret-containers).
   Apply the subnet group, the security group with its two rules, and the two secret containers,
   with no value in either.
2. Check what Stage 1 built: [Read back the network boundary](#read-back-the-network-boundary) and
   [Verify the secret containers without reading a value](#verify-the-secret-containers-without-reading-a-value).
   Both containers must hold zero versions. With everything the index lists as supplied by you
   ([What these runbooks are](README.md#what-these-runbooks-are)), and if Stage 1's first-apply binding passes, the
   path stops here unless you also supply the three things steps 3 to 8 need
   ([Stopping after Stage 1](#stopping-after-stage-1)).
3. [Place the master value](#place-the-master-value). An owner-only step with exactly one write
   attempt, never retried. Confirm it with the container check and
   [Account for secret reads and writes in CloudTrail](#account-for-secret-reads-and-writes-in-cloudtrail).
4. [Stage 2: plan the instance and its endpoint parameter](#stage-2-plan-the-instance-and-its-endpoint-parameter).
   One saved plan, checked value by value, then the secret-absence proof, then binding.
5. [Run the pre-apply gate](#run-the-pre-apply-gate), once the owner's grant names the plan hash,
   immediately before the apply.
6. [Stage 2: apply the reviewed saved plan](#stage-2-apply-the-reviewed-saved-plan), once, under a
   grant naming the plan hash.
7. [Read back the instance and its endpoint parameter](#read-back-the-instance-and-its-endpoint-parameter).
8. [Confirm convergence](#confirm-convergence).

The [secret-absence proof](#prove-the-master-value-is-absent-from-plans-state-and-logs) runs inside
steps 4, 6 and 8: after the Stage 2 plan, after the apply, and after the read-back and convergence
plan.

Steps 4 to 8 are one pass through the shared [Normal path](terraform-operations.md#normal-path)
of terraform-operations.md, as one campaign. The Stage 2 plan runs shared steps 1 to 8 and opens
the campaign's evidence set; the owner's grant is shared step 9; the pre-apply gate and the apply
are shared step 10; the read-back is shared step 11; and Confirm convergence runs shared step 12,
then closes the set (shared step 13). Placement, step 3, is not a Terraform run: it keeps its own
evidence ([Place the master value](#place-the-master-value)) before that set opens.

<a id="stopping-after-stage-1"></a>

**Stopping after Stage 1.** From the public repositories alone, the path does not reach Stage 1:
the items the index lists under [What these runbooks are](README.md#what-these-runbooks-are) come first, and Stage 1,
this root's first apply, can still stop at its binding check: it stops if the state read in step 3
of the bind procedure prints nothing, while serial 0 with an empty or `null` lineage is the
first-apply match. Past that, the path ends after step 2. Steps 3 to 8 need three things this
project has not published, which you supply yourself: a placement tool qualified offline, without
which the master value cannot be placed; a tool that implements the secret-absence proof, without
which the Stage 2 plan, the apply and the convergence plan do not start; and a way to run the
Stage 2 apply that closing or losing the terminal cannot end
([Before you start](#before-you-start), [Reproducibility gaps](#reproducibility-gaps)). If you stop
here:

- **What stays in AWS.** The subnet group, the security group with its two rules, and the two empty
  secret containers. The containers bill about 0.80 USD a month from creation; the rest carries no
  charge.
- **Removing it.** No procedure here removes Stage 1: decommission is
  [not yet exercised](#not-yet-exercised) and needs a separate owner grant. Do not delete a
  container as a retry: its name stays reserved through the recovery window.
- **Checks that still apply.** The
  [weekly ADR-0013 review](cost-and-residue.md#record-the-weekly-adr-0013-review), weekly, first
  due 2026-10-01, after that week's budget read-back and orphan census (PASS: one dated private
  record with all seven entries, identifiers redacted, stating the decision and why). In that
  census `DATASTORE_SG` reads 1 while this root is applied, and no datastore instance or interface
  is counted, as on 2026-09-22. With only Stage 1 applied no instance exists, so the review's
  CPU-credit input and entry 5, the instance status in entry 4, and the first period's start,
  which the review takes from the instance's creation, have no published form here: how they are
  recorded is the owner's decision, stated in entry 7. Stopping here ends the path; repeat this
  review weekly.
- **Checks that do not apply yet.** Check the datastore CPU credits, in cost-and-residue.md, and
  Verify the retained side with the datastore present, in dev-network.md, both need the instance.
  Step 6 of the index's Build order runs them after the full path, after step 8 here, not after
  Stage 1.

This path is the first build of the root. This page has no procedure for a later apply of this
root, and no gate exists for one ([Not yet exercised](#not-yet-exercised)). A later apply waits for
a reviewed decision under explicit approval. Whatever that decision adds, the rules this page sets
for every plan and apply of this root still hold: debug logging stays off, every run that reads the
master value needs an owner grant, and each plan uses a new `<private-dir>`.

When something goes wrong:

- A Stage 1 apply fails: the stop rule, as in
  [Stage 1](#stage-1-create-the-network-boundary-and-the-empty-secret-containers), **If it fails**.
- A placement ends in any outcome other than placed:
  [Respond to a failed or uncertain placement](#respond-to-a-failed-or-uncertain-placement).
- A Stage 2 apply fails, is interrupted or loses its terminal:
  [Read the datastore after a failed or interrupted apply](#read-the-datastore-after-a-failed-or-interrupted-apply).
- A proof finds the value or cannot complete, the value appears anywhere, or CloudTrail shows an
  unexplained read of the master:
  [Contain an exposed or unproven master value](#contain-an-exposed-or-unproven-master-value).

> **Warning: the master value never enters a log, a record or evidence.** It is never displayed or
> recorded. It passes through the Terraform provider on every plan and apply of this root, so debug
> logging stays off for every one of them
> ([Debug logging](../../terraform/dev-datastore/README.md#debug-logging)). The placement's evidence
> also never holds the placement token or an ARN.

> **Warning: the master placement has one write attempt.** It is never retried, and a value is
> never placed by other means. A wrong value cannot be corrected by placing again
> ([Place the master value](#place-the-master-value)).

> **Warning: the Stage 2 apply's hang-up protection has no exercised published form.** The
> executed apply was shielded from a terminal hangup by private tooling that is not published. In
> offline qualification, an unshielded terminal hangup during an RDS create killed Terraform
> mid-create ([Stage 2: apply the reviewed saved plan](#stage-2-apply-the-reviewed-saved-plan)).

<a id="hidden-prerequisites"></a>

## Before you start

The runbook as a whole needs the following. Each procedure lists again what it needs.

- [ ] The suite-wide setup in [Background prerequisites](#background-prerequisites): your own AWS
  account, an operator identity with a CLI profile, and the toolchain.
- [ ] **Network.** The Dev network baseline applied:
  [Build only the retained baseline](dev-network.md#build-only-the-retained-baseline), steps 1 to
  6 (PASS: every step 6 check passes; Confirm the retained and runtime split shows the 21 retained
  addresses in state, 17 to add and no drift). Then return to this list.
- [ ] **Capacity.** PostgreSQL 17.11 orderable on `db.t4g.micro` with gp3 in both zones of your
  private subnets. Zone names map to different physical zones in each account. The zone mapping
  check in dev-network.md tested this at step 5 of the index's Build order, before the network
  existed; step 2 of the [pre-apply gate](#run-the-pre-apply-gate) checks it again.
- [ ] **Root inputs.** The account's 12-digit ID in the untracked `terraform.tfvars`
  ([terraform.tfvars.example](../../terraform/dev-datastore/terraform.tfvars.example)), and the
  state bucket from the bootstrap root in the untracked `backend.hcl`
  ([backend.hcl.example](../../terraform/dev-datastore/backend.hcl.example)).
- [ ] **Cost controls.** The budget and its alerts, and a price re-check before each billable
  apply, Stage 1 and Stage 2. Both run in the exported shell after the owner's grant for that
  apply: for Stage 1 in its step 8, before step 3 of the bind procedure; for Stage 2 in the
  [pre-apply gate](#run-the-pre-apply-gate). Both must pass:
  [Read back the budget and its alert states](cost-and-residue.md#read-back-the-budget-and-its-alert-states)
  (PASS: one budget `cloud-platform-reference` of `200.0` `USD` with exactly its five
  notifications, each with a subscriber; an `ALARM` is a STOP there), then
  [Re-check prices before billable work](cost-and-residue.md#re-check-prices-before-billable-work)
  (PASS: every rate the apply bills is in its price table and reads equal to it). Then return to
  Stage 1 step 8 or to the gate.
- [ ] **Private directories.** A new `<private-dir>` per plan, outside every Git working tree,
  created under `umask 077`, and a private evidence location with everything the
  [Before you start](evidence-handling.md#before-you-start) of evidence-handling.md lists for every
  campaign: an evidence root of mode 0700 outside every Git working tree, the literal list, the
  address allowlist, and your own redaction filter and sweep. Then return to this list.
- [ ] **Approvals.** A written owner grant for each mutation (the Stage 1 apply, placement, the
  Stage 2 apply, any recovery, decommission) and for every run that reads the master value.
- [ ] **Session time.** The executed runs required this much session time remaining: 30 minutes
  for placement, 45 for a plan with its proof, 50 for the pre-apply gate and the apply, and 5 for
  the read-back with its convergence plan and for each secret-absence proof after a plan or apply.
  This page states no figure for the Stage 1 plan and apply; set one as step 1 of the headroom
  check describes. Before each of these operations, run
  [Check session headroom before long operations](operator-access.md#check-session-headroom-before-long-operations),
  steps 1 to 3, with that figure as `<required-minutes>` (PASS: the headroom line prints and the
  exit status is 0). Then return to the operation.
- [ ] **Placement token.** A fixed client request token (a UUID) chosen before placement and
  recorded privately.
- [ ] **Placement tool.** A tool that keeps the scope, validation and STOP rules in
  [Place the master value](#place-the-master-value), qualified offline before use, and places a
  value with the interface stated there. The reviewed tool used here is not published.
- [ ] **Absence proof.** A tool that implements the
  [method](#prove-the-master-value-is-absent-from-plans-state-and-logs). The reviewed tool used here
  is not published.
- [ ] **Hangup protection.** A way to run the Stage 2 apply that closing or losing the terminal
  cannot end. The executed form is not published, and no published form has been exercised.

**Terms used on this page.**

- **Owner.** The person accountable for the AWS account, who gives each grant this runbook names.
- **Grant.** The owner's written approval, given before the step it names. An apply grant names
  the saved plan's hash.
- **Saved plan.** A plan written to a file, reviewed, bound to its hash and to the state it was
  made from, and then applied exactly
  ([Bind the saved plan to its hash and to state](terraform-operations.md#bind-the-saved-plan-to-its-hash-and-to-state)).
- **Exported shell.** A clean shell that runs on one role credential exported once, with no
  operator configuration, no stray `AWS_*` or `TF_*` variable and no default profile
  ([Export role credentials once](operator-access.md#export-role-credentials-once)).
- **Placement token.** The client request token of the one placement write. It becomes the master
  version's ID and is never published.
- **Secret-absence proof.** The check that no artifact of a run holds the master value
  ([Prove the master value is absent from plans, state and logs](#prove-the-master-value-is-absent-from-plans-state-and-logs)).
- **Stop rule.** [Stop after a failed or interrupted apply](terraform-operations.md#stop-after-a-failed-or-interrupted-apply):
  record the state as unknown, never apply again, read back and classify every planned address.
- **HOLD.** A check that failed or could not be read. A HOLD applies nothing.
- **Retained baseline.** What the Dev network root keeps in AWS between runtime windows.
- **Reviewed commit.** `<commit>` in the terraform-operations.md conventions: the full SHA of the
  commit whose configuration was reviewed. For Stage 2 it must contain `database.tf`.
- **Preflight.** A check the placement tool makes before the write. A failed one is a refusal
  before the write, and nothing is written
  ([Respond to a failed or uncertain placement](#respond-to-a-failed-or-uncertain-placement)).
- **Master opened and closed once.** The run's log holds exactly one line beginning
  `ephemeral.aws_secretsmanager_secret_version.master: Opening complete` and one beginning
  `ephemeral.aws_secretsmanager_secret_version.master: Closing complete`.
- **Orphan census and runtime class.** The census shows that no runtime residue remains: no
  resource in its runtime classes, the categories it counts as residue, exists outside an approved
  runtime window. It counts the persistent datastore in separate exception classes
  ([Run the orphan census](cost-and-residue.md#run-the-orphan-census)).

**Conventions.**

- Validation labels are defined in the [runbook index](README.md#validation-labels).
- Terraform steps follow the conventions of [terraform-operations.md](terraform-operations.md),
  including `<profile>`, `<work-dir>`, `<private-dir>`, `<plan-file>` and `<plan-json>`; use a new
  `<private-dir>` for each plan.
- AWS CLI reads run with `--profile <profile> --region us-east-1` and are projected so that they
  print no ARN, account number or secret version ID.
- The executed Stage 2 plan, pre-apply gate, apply, read-back with its convergence plan, and every
  secret-absence proof ran in an exported shell. Run them that way, and drop `--profile <profile>`
  and `AWS_PROFILE=<profile>` inside that shell.

**Shared workflows this page links rather than repeats.**

- terraform-operations.md: initializing a working tree, keeping debug logging off, planning to a
  saved file, reviewing and binding it, applying it, convergence, and the stop rule after a failed
  or interrupted apply. This runbook adds what this root's plans must contain and how its
  resources are read back.
- operator-access.md: signing in, confirming the account, and session lifetime.
- dev-network.md: the Dev network this root depends on.
- cost-and-residue.md: the price re-check, the budget, the CPU-credit check, the weekly ADR-0013
  review and the orphan census.
- evidence-handling.md: capture, redaction, sealing and remediation.

## Procedures

Normal-path procedures come first, then the checks they call, then the failure and recovery
procedures.

### Stage 1: create the network boundary and the empty secret containers

**Validation:** AWS-VALIDATED (2026-09-22) · **Published command form:** not executed as written

**What this does.** Creates what must exist before the master value can be placed: the DB subnet
group, the security group with its two ingress rules, and the two secret containers, with no value
in either.

Planning `database.tf` reads the master value, so this stage plans a configuration that does not
contain that file: the root at commit `aeb1622`. That commit's Terraform configuration differs
from the current root only by the absence of `database.tf`; its README is an older version.

**Before you start.**

- [ ] The Dev network exists, with the VPC and private subnets `a` and `b` carrying their `Name`
  tags: [Read back the retained network](dev-network.md#read-back-the-retained-network), steps 1
  to 5 (PASS: every row of its expected-result table matches). Then return to this list.
- [ ] The budget read-back and the price re-check for the Secrets Manager rate pass in step 8,
  after the grant and before step 3 of the bind procedure, as **Cost controls** in
  [Before you start](#before-you-start) describes.
- [ ] The [account check](operator-access.md#check-the-account-before-aws-commands), steps 1 and
  2, passes for `<profile>` (PASS: `ACCOUNT_MATCH=PASS`). Nothing else checks the account for the
  AWS CLI reads in step 2. Then return to this list.
- [ ] This is the root's first apply: if the binding check's state read in step 8 prints nothing,
  Stage 1 stops before its apply, and no published procedure resolves that
  ([Bind the saved plan](terraform-operations.md#bind-the-saved-plan-to-its-hash-and-to-state),
  **If it fails**).

**Safety and authority.** Mutating, owner-authorized, billable; steps 1, 3, 11 and 12 are
local-only. The apply in step 8 needs an explicit owner grant naming the saved plan's hash. The
containers bill from creation. At commit `aeb1622` the configuration does not read the master
value.

**Steps.** These are the steps of the shared Normal path of terraform-operations.md, in its order,
with what differs for Stage 1. `<commit>` is the full SHA of commit `aeb1622`.

1. Open the campaign's evidence set:
   [Capture a campaign evidence set](evidence-handling.md#capture-a-campaign-evidence-set), steps 1
   and 2 (PASS: one campaign directory under the evidence root, mode 0700); capture needs your own
   redaction filter and sweep. Then continue with this step. Write the reviewed list, the addresses
   and actions the change intends, before the plan is made, and record it as the **Expected** field
   of the campaign record: the six creates in the expected result below. Put the root's filled
   inputs in its `<inputs-dir>`, and create a new `<private-dir>` (shared step 1).
2. Confirm that no resource with these names exists, and that no secret with either container name
   is pending deletion. The counts below must print `0`, and
   [Verify the secret containers](#verify-the-secret-containers-without-reading-a-value) step 4
   must print `[]`.
   > **Warning:** A failed read prints an error, never a count, and is not absence.
   ```
   aws ec2 describe-security-groups --profile <profile> --region us-east-1 \
     --filters Name=group-name,Values=cloud-platform-reference-dev-datastore \
     --query 'length(SecurityGroups)'
   aws rds describe-db-subnet-groups --profile <profile> --region us-east-1 \
     --query "length(DBSubnetGroups[?DBSubnetGroupName=='cloud-platform-reference-dev-datastore'])"
   ```
3. Run the static checks on `<commit>`
   ([Run the static checks](terraform-operations.md#run-the-static-checks); shared step 2).
   They need a clean working tree at `<commit>` that holds no filled inputs, and the step 4 tree
   does not exist yet. Create one for them in a new directory `<scan-tree>`, outside every
   existing Git working tree, run the checks from it, then remove it:
   ```
   git worktree add --detach <scan-tree> <commit>
   ```
   ```
   git worktree remove --force <scan-tree>
   ```
   > **Warning:** `--force` deletes the working tree and every untracked file in it. Confirm that
   > `<scan-tree>` is the scan tree.

   `<main-commit>` is the full SHA of the current `main`, whose root also holds `database.tf`.
   This overrides the first-build rule in terraform-operations.md, where `<main-commit>` is
   `<commit>`. In the scan comparison, a line beginning `<` is a class only `main` has, not a new
   class; a line beginning `>` is a new class, and a STOP. Here the check passes when `diff`
   prints no line beginning `>`, in place of the shared condition that `diff` prints nothing.
   Then continue at step 4.
4. Initialize the root in its own working tree at `<commit>`
   ([Initialize a root against the state backend](terraform-operations.md#initialize-a-root-against-the-state-backend),
   steps 1 to 3; shared step 3). PASS: `git check-ignore` lists both inputs, `init` reports the
   backend configured and Terraform initialized, and `git status` prints nothing. Then continue at
   step 5.
5. Inspect state
   ([Inspect state without writing it](terraform-operations.md#inspect-state-without-writing-it),
   steps 1 to 3; shared step 4). This root has never been applied, so the expected address set is
   none. Record the serial, lineage and address digest. Then continue at step 6.
6. Keep debug logging off
   ([Keep Terraform debug logging off](terraform-operations.md#keep-terraform-debug-logging-off);
   PASS: the check prints nothing), plan to a saved file
   ([Plan to a saved file](terraform-operations.md#plan-to-a-saved-file); PASS: exit 2 with the
   saved plan at `<plan-file>`), review the plan
   ([Review the saved plan](terraform-operations.md#review-the-saved-plan), steps 1 to 5) and
   bind it
   ([Bind the saved plan to its hash and to state](terraform-operations.md#bind-the-saved-plan-to-its-hash-and-to-state),
   steps 1 and 2 now; step 8 runs its step 3; PASS: `same` for every file and the lock file,
   `diff` prints nothing, and serial 0 with no lineage, empty or `null`) (shared steps 5 to 8).
   The review must match the expected result below. Then continue at step 7.
7. Obtain the owner's written grant for this plan, identified by its sha256 (shared step 9). There
   is no command for this step.
8. Under the grant, run the budget read-back and the price re-check for the Secrets Manager rate in
   the exported shell, as **Cost controls** in [Before you start](#before-you-start) describes,
   then step 3 of the bind procedure immediately before the apply. Once all three pass, apply the
   reviewed saved plan
   ([Apply the reviewed saved plan](terraform-operations.md#apply-the-reviewed-saved-plan), steps
   1 and 2; shared step 10). PASS: exit 0 with the summary in the expected result below. Then
   continue at step 9, which is that procedure's step 3 read-back.
   > **Warning:** Never re-apply. A non-zero exit, an interrupt or a summary that differs is a
   > STOP; go to **If it fails**. Deleting a container is not a clean retry: its name stays
   > reserved through the recovery window.
9. Read back (shared step 11): run [Read back the network boundary](#read-back-the-network-boundary)
   and [Verify the secret containers](#verify-the-secret-containers-without-reading-a-value).
10. Confirm convergence from the Stage 1 working tree, before step 11 removes it
    ([Confirm convergence](terraform-operations.md#confirm-convergence); shared step 12). PASS:
    exit 0 with `No changes. Your infrastructure matches the configuration.` At that commit the
    configuration does not read the master value. Convergence has not yet been run after Stage 1.
    Then continue at step 11.
11. Remove the Stage 1 working tree, which holds copies of the untracked inputs. Stage 2 is planned
    from a new working tree at the reviewed commit that contains `database.tf`.
    > **Warning:** `--force` deletes the working tree and every untracked file in it. Confirm that
    > `<work-dir>` is the Stage 1 tree, and that the saved plan, its JSON and their logs are in
    > `<private-dir>`, outside it.
    ```
    git worktree remove --force <work-dir>
    ```
12. Close the evidence set (shared step 13): steps 4 to 7 of the
    [Normal path](evidence-handling.md#normal-path) of evidence-handling.md. PASS: the sweep
    detects every planted instance, with zero value hits and every pattern hit explained, and
    every manifest entry reports OK. Then return here for the **Next step**.

**Expected result.**

- Step 2 prints `0`, `0`, and `[]` from the container check.
- The static checks pass with no `diff` line beginning `>`; lines beginning `<` may appear. State
  inspection lists no address.
- The review lists exactly six `create` actions, on `aws_db_subnet_group.datastore`,
  `aws_security_group.datastore`, `aws_vpc_security_group_ingress_rule.postgres["a"]` and `["b"]`,
  `aws_secretsmanager_secret.master` and `aws_secretsmanager_secret.app`, with no drift and no
  outputs.
- The apply ends with `Apply complete! Resources: 6 added, 0 changed, 0 destroyed.`
- Both read-backs pass, and both containers hold zero versions.
- The convergence plan exits 0 with `No changes. Your infrastructure matches the configuration.`,
  as step 10 expects.

**PASS when.**

- [ ] Nothing with these names existed or was pending deletion before the plan.
- [ ] The static checks passed with no `diff` line beginning `>`, and state inspection listed no
  address.
- [ ] The review listed exactly the six creates, with no drift and no outputs.
- [ ] The apply printed the expected summary.
- [ ] Both read-backs passed, with zero versions in each container.
- [ ] The convergence plan exited 0 before the working tree was removed.

**STOP if.**

- Step 2 prints anything other than `0`, `0` and `[]` from the container check: a resource or a
  pending-deletion secret with these names exists, or a read failed. A failed read is not absence.
- A STOP in a linked shared procedure, including a new finding class in the static checks, any
  address in state inspection, or a convergence plan that exits 2 or 1.
- Any action other than the six creates.
- A failed network lookup (a missing or duplicated `Name` tag fails the plan).
- Any apply outcome other than the expected summary
  ([terraform-operations.md](terraform-operations.md)).
- The binding check's state read prints nothing. This is the root's first apply, and what that read
  prints against a state object never yet written has not been recorded, so an empty result is a
  mismatch no published procedure resolves ([Bind the saved plan](terraform-operations.md#bind-the-saved-plan-to-its-hash-and-to-state)).

**If it fails.** An apply that fails, is interrupted or prints a different summary: follow the stop
rule
([Stop after a failed or interrupted apply](terraform-operations.md#stop-after-a-failed-or-interrupted-apply)).
Its read-back for this stage is [Read back the network boundary](#read-back-the-network-boundary)
and [Verify the secret containers](#verify-the-secret-containers-without-reading-a-value), recording
each of the six addresses as that rule classifies it. No secret-absence proof runs, because no
value exists yet;
[Read the datastore after a failed or interrupted apply](#read-the-datastore-after-a-failed-or-interrupted-apply)
covers Stage 2 only. This path has never been exercised. Deleting a container is not a clean retry:
its name stays reserved through the recovery window. A failed static check, state inspection or
convergence plan: follow that procedure's **If it fails** in
[terraform-operations.md](terraform-operations.md).

**Evidence to keep.** The plan hash, the reviewed action list, the apply summary line and both
read-backs, privately.

**Next step.** [Place the master value](#place-the-master-value), if you have the three things the
rest of the path needs. From the public repositories alone, the path stops here
([Stopping after Stage 1](#stopping-after-stage-1)).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22) |
| Published form | not executed as written (the 2026-09-22 apply planned this root from public main at `2604e6c`, whose `terraform/dev-datastore` tree is identical to the tree at `aeb1622`, through private tooling; the linked workflow has not run for this stage) |
| Evidence basis | [What it creates](../../terraform/dev-datastore/README.md#what-it-creates), [Status](../../terraform/dev-datastore/README.md#status); retained private evidence of the 2026-09-22 plan, apply and read-back |
| Authority | Explicit owner grant naming the saved plan's hash |
| Cost | About 0.80 USD a month for the two containers from creation; the subnet group, security group and rules carry no charge ([cost](../../terraform/dev-datastore/README.md#decommission)) |

- The two reads in step 2 are derived from the executed check for pre-existing resources and have
  not run in this form.
- Convergence has not been run after Stage 1.
- The README's other option, a `-target` plan of these six addresses from the current checkout,
  has never run.

### Place the master value

**Validation:** AWS-VALIDATED (2026-09-24) for the one run of the reviewed tool; DESIGNED-NOT-EXECUTED (never) with an equivalent tool · **Published command form:** not executed as written

**What this does.** Puts the master password into the master container as its first and only
version, before `database.tf` is planned. Terraform never writes it, and it is never displayed or
recorded. It is read only by the provider during each plan and apply of this root, and once by
each run of the [secret-absence proof](#prove-the-master-value-is-absent-from-plans-state-and-logs).

This page gives the placement's scope, validation and STOP rules, and no runnable placement
command. The placement runs through a placement tool; the reviewed one used here is not published.

**Before you start.**

- [ ] Stage 1 is applied
  ([Stage 1](#stage-1-create-the-network-boundary-and-the-empty-secret-containers)).
- [ ] A written owner grant for this placement: the master container only, one write attempt, and
  whether a refusal before the write uses that attempt up.
- [ ] A signed-in session on the intended account with at least 30 minutes remaining:
  [Sign in](operator-access.md#sign-in), steps 1 and 2 (PASS: the identity check prints `True`
  twice and the account check prints `ACCOUNT_MATCH=PASS`), then the headroom check with 30 as
  `<required-minutes>`, as **Session time** in [Before you start](#before-you-start) describes.
  Then return to this list.
- [ ] A fixed client request token, a UUID chosen in advance and recorded privately. It becomes
  the version ID. It is never published.
- [ ] A value with the right interface: one plain `SecretString`, not a key/value JSON document
  and not `SecretBinary`. [database.tf](../../terraform/dev-datastore/database.tf) passes it
  unchanged as the instance's master password, so it must also meet the RDS for PostgreSQL
  master-password constraints (`MasterUserPassword` in the Amazon RDS `CreateDBInstance` API
  reference). Choose the value so that it meets them before the write, because nothing on this
  page checks it: the placement is validated from metadata and CloudTrail without reading the
  value, and write-only handling keeps it out of the Stage 2 plan.
  > **Warning:** A value that does not meet them cannot be corrected by placing again: a
  > placement never writes to a container that already holds a value, and replacing it is
  > rotation, which is [not yet exercised](#not-yet-exercised).
- [ ] The value's format, chosen now and kept privately; it is never published. The proof's
  cross-check sweeps retained evidence for strings in this format
  ([secret-absence proof](#prove-the-master-value-is-absent-from-plans-state-and-logs), step 6).
- [ ] A placement tool that keeps the scope, validation and STOP rules on this page, qualified
  offline before use. Qualification runs against mocked AWS responses and shows at least that the
  tool:
  - writes only to the master container, with exactly one write attempt;
  - refuses before the write on a wrong account and on a container that already holds a value;
  - reports each outcome class in
    [Respond to a failed or uncertain placement](#respond-to-a-failed-or-uncertain-placement) when
    that failure is mocked, and never writes a second time;
  - never shows the value in its output or on a command line.

**Safety and authority.** Mutating, owner-authorized. Placement is an owner step, run only by the
owner in the owner's own signed-in administrator permission-set session, never as the account root
user. No pipeline, scheduled job or other process runs it, and nobody else receives the value. It
targets the master container only; a placement never targets another container. The application
container's value is DEFERRED: that container stays empty until the path that consumes it is
designed and independently reviewed.

> **Warning: one write attempt, never retried.** The no-retry rule applies to write attempts.
> There is exactly one write attempt, and it is never retried. The placement token makes it
> idempotent, so a repeated attempt cannot add a second version; even so, a placement is never
> rerun after the write has been attempted.

> **Warning: the value is never displayed or recorded, including on the way in.** The
> [secret-absence proof](#prove-the-master-value-is-absent-from-plans-state-and-logs) does not
> search terminal scrollback, the clipboard or shell history, so a copy left there is never
> detected. The tool never takes the value on a command line, which shell history records and other
> local processes can read, never echoes it, and never sends it through an AWS CLI that records
> command history: `aws configure get cli_history --profile <profile>` must print nothing or
> `disabled`, and so must `aws configure get cli_history` for the default profile.

**Steps.**

1. Run [Verify the secret containers](#verify-the-secret-containers-without-reading-a-value) and
   confirm the before-placement values.
2. Record the UTC start time.
3. Run the placement tool once, for the master container only, with the placement token.
   > **Warning:** This is the single write attempt. Never rerun the tool after the write has been
   > attempted, and never place a value by other means.
4. Record the UTC end time and the tool's outcome line. Any outcome other than placed is a STOP.
5. Run [Verify the secret containers](#verify-the-secret-containers-without-reading-a-value) with
   the token check.
6. Run [Account for secret reads and writes in CloudTrail](#account-for-secret-reads-and-writes-in-cloudtrail)
   from the start time, after the event-history delay; the executed check ran about ten minutes
   after the write. Before then, a missing `PutSecretValue` is not yet a finding: repeat the
   read-only lookup, never the placement.

**Expected result.** The outcome is placed for the master, with the application container
untouched. The metadata shows the after-placement values. CloudTrail shows one successful
`PutSecretValue` on the master with the placement token inside the window, and no
`GetSecretValue`. Validation uses metadata and CloudTrail only, before and after the write; the
value is not read to validate the placement.

**PASS when.**

- [ ] The outcome line says placed.
- [ ] The metadata shows the after-placement values, and the token check prints `1`.
- [ ] CloudTrail shows the one successful `PutSecretValue` with the placement token inside the
  window, and no `GetSecretValue`.

**STOP if.**

- Any preflight failure.
- Any outcome other than placed.
- Any unexpected CloudTrail event.
- The value appearing anywhere.

**If it fails.** Never rerun the tool and never place a value by other means. Follow
[Respond to a failed or uncertain placement](#respond-to-a-failed-or-uncertain-placement). If the
value appears anywhere, follow
[Contain an exposed or unproven master value](#contain-an-exposed-or-unproven-master-value). No
recovery or rollback is exercised. A placement never writes to a container that already holds a
value, so replacing a placed value is rotation ([Not yet exercised](#not-yet-exercised)).

**Evidence to keep.** The start and end times, the outcome line, and the metadata and CloudTrail
outputs; never the value, the token or an ARN ([evidence-handling.md](evidence-handling.md)).

**Next step.** [Stage 2: plan the instance and its endpoint parameter](#stage-2-plan-the-instance-and-its-endpoint-parameter).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-24) for the single run of the reviewed placement tool; DESIGNED-NOT-EXECUTED (never) for this step-level procedure with an equivalent tool |
| Published form | not executed as written (executed once through a reviewed placement tool, qualified offline before use, not published; this section gives the placement's scope, validation and STOP rules and no runnable placement command) |
| Evidence basis | [What this root does not create](../../terraform/dev-datastore/README.md#what-this-root-does-not-create), [Status](../../terraform/dev-datastore/README.md#status); retained private evidence of the tool's offline qualification and of the independent metadata and CloudTrail verification after the 2026-09-24 placement |
| Authority | Explicit owner grant naming the master container only and a single write attempt |
| Cost | No new resource; one API request |

- **Tooling.** A reviewed placement tool, qualified offline before use, not published.
- **Evidence status.** Executed once, 2026-09-24. The result rests on the independent metadata and
  CloudTrail verification retained as private evidence; the terminal output of the placement run
  itself was not retained.
- **Known limitations.** The tool is not published, so a reproducer supplies an equivalent that
  keeps the scope, validation and STOP rules above and qualifies it offline before use; that path
  has never run. The offline qualification before the executed placement ran against mocked AWS
  responses only.

### Stage 2: plan the instance and its endpoint parameter

**Validation:** AWS-VALIDATED (2026-09-24) · **Published command form:** not executed as written

**What this does.** Produces one saved plan that creates the instance and its endpoint parameter
and nothing else, and checks it against the expected values before anyone approves an apply.

Every plan of this root reads the master value through the provider. The plan's output therefore
goes to a log in `<private-dir>`, and the secret-absence proof must find no occurrence before the
plan is bound.

**Before you start.**

- [ ] The master is placed and the application container is empty
  ([Verify the secret containers](#verify-the-secret-containers-without-reading-a-value)).
- [ ] Stage 1 is applied to the same state
  ([Stage 1](#stage-1-create-the-network-boundary-and-the-empty-secret-containers)).
- [ ] Prices will be re-checked before the instance is created, in the Prices row of the
  [pre-apply gate](#run-the-pre-apply-gate), step 3, as **Cost controls** in
  [Before you start](#before-you-start) says; nothing to run before this plan.
- [ ] A session with at least 45 minutes remaining, the margin the executed plan and its proof
  used.
- [ ] An exported shell:
  [Export role credentials once](operator-access.md#export-role-credentials-once), steps 1 to 4,
  with 45 as `<required-minutes>` (PASS: `ACCOUNT_MATCH=PASS` with no HOLD line, and the headroom
  line with exit 0). Then return to this list.
- [ ] An explicit owner grant: the plan reads the master value once, and the proof in step 9 reads
  it once.
- [ ] A tool that implements the
  [secret-absence proof](#prove-the-master-value-is-absent-from-plans-state-and-logs), for step 9;
  the reviewed tool used here is not published. Without one, do not start: the plan reads the
  master value before the proof runs. The apply after this plan also needs the
  **Hangup protection** item of [Before you start](#before-you-start).

**Safety and authority.** Secret-reading, owner-authorized: the plan in step 6 and the proof in
step 9 read the master value. Steps 1 and 2 are local-only, and steps 3 and 4 are read-only against
AWS. Nothing writes state.

> **Warning:** Debug logging stays off. The master value passes through the provider on every plan
> of this root.

**Steps.** These are shared steps 1 to 8 of the
[Normal path](terraform-operations.md#normal-path) of terraform-operations.md, in its order, with
what differs for Stage 2. `<commit>` is the full SHA of the reviewed commit whose root holds
`database.tf`, for example the current `main`.

1. Open the campaign's evidence set:
   [Capture a campaign evidence set](evidence-handling.md#capture-a-campaign-evidence-set), steps 1
   and 2 (PASS: one campaign directory under the evidence root, mode 0700). Then continue with this
   step: record the reviewed list, the actions in the expected result below, as its **Expected**
   field (shared step 1). The set stays open through the apply and the read-back, and
   [Confirm convergence](#confirm-convergence) closes it.
2. Run the static checks on `<commit>`
   ([Run the static checks](terraform-operations.md#run-the-static-checks), steps 1 to 3; shared
   step 2), in a clean working tree created and removed as in
   [Stage 1](#stage-1-create-the-network-boundary-and-the-empty-secret-containers), step 3. As a
   first build, `<main-commit>` is `<commit>`, as terraform-operations.md sets. PASS: `fmt`,
   `validate`, `tflint` and every `trivy config` exit 0, `git status` prints nothing, and `diff`
   prints nothing. Then continue at step 3.
3. Initialize the root in a new working tree at `<commit>`
   ([Initialize a root against the state backend](terraform-operations.md#initialize-a-root-against-the-state-backend),
   steps 1 to 3; shared step 3). PASS: `git check-ignore` lists both inputs, `init` reports the
   backend configured and Terraform initialized, and `git status` prints nothing. Then continue at
   step 4.
4. Inspect state
   ([Inspect state without writing it](terraform-operations.md#inspect-state-without-writing-it),
   steps 1 to 3; shared step 4). Expect the six Stage 1 addresses and the root's data sources, as
   that procedure sets for the datastore before Stage 2. Record the serial, lineage and address
   digest. Then continue at step 5.
5. Keep debug logging off
   ([Keep Terraform debug logging off](terraform-operations.md#keep-terraform-debug-logging-off);
   shared step 5). PASS: the check prints nothing. Then continue at step 6.
6. Record the UTC time, then plan to a saved file in a new `<private-dir>`
   ([Plan to a saved file](terraform-operations.md#plan-to-a-saved-file), step 1; shared step 6),
   redirecting the plan's output to `<private-dir>/plan.log` so that the proof covers it. PASS:
   exit 2 with the saved plan at `<plan-file>`, and the master opened and closed once in
   `plan.log`. Then continue at step 7.
7. Review the saved plan
   ([Review the saved plan](terraform-operations.md#review-the-saved-plan), steps 1 to 5; shared
   step 7) against the expected result below. Then continue at step 8.
8. Check the planned values of the instance and the parameter, as part of that review:
   ```
   jq '.resource_changes[] | select(.address == "aws_db_instance.datastore") | .change.after
       | {identifier, engine_version, instance_class, allocated_storage, storage_type,
          storage_encrypted, publicly_accessible, multi_az, backup_retention_period,
          deletion_protection, skip_final_snapshot, final_snapshot_identifier,
          manage_master_user_password, password, password_wo_version, tags_all}' <plan-json>
   jq '.resource_changes[] | select(.address == "aws_ssm_parameter.endpoint")
       | {name: .change.after.name, type: .change.after.type, tier: .change.after.tier,
          value_known_after_apply: .change.after_unknown.value}' <plan-json>
   ```
9. Run the [secret-absence proof](#prove-the-master-value-is-absent-from-plans-state-and-logs).
10. Only after the proof finds no occurrence, bind the saved plan
    ([Bind the saved plan to its hash and to state](terraform-operations.md#bind-the-saved-plan-to-its-hash-and-to-state),
    steps 1 and 2 now; its step 3 runs in the [pre-apply gate](#run-the-pre-apply-gate); shared
    step 8). PASS: step 2 prints `same` for every file and the lock file, and `diff` prints
    nothing. The apply grant, shared step 9, names its hash. Then go to the **Next step**.

**Expected result.**

- The static checks pass. State inspection lists the six Stage 1 addresses and the root's data
  sources.
- The plan exits 2. `plan.log` shows `ephemeral.aws_secretsmanager_secret_version.master` opening
  and closing once.
- The review lists exactly two actions, `create` on `aws_db_instance.datastore` and on
  `aws_ssm_parameter.endpoint`; the six Stage 1 addresses are `no-op`. No outputs.
- Drift, if listed, is limited to `tags` on `aws_db_subnet_group.datastore`,
  `aws_secretsmanager_secret.master` and `aws_secretsmanager_secret.app`, and `ingress` on
  `aws_security_group.datastore`. The 2026-09-24 plan showed exactly these four: the refresh
  recorded empty tag maps where Stage 1 stored none, and the security group mirrors the two ingress
  rules managed as separate resources. Each was planned `no-op`.
- The instance values equal [database.tf](../../terraform/dev-datastore/database.tf);
  `password` and `manage_master_user_password` are `null`, `password_wo_version` is `1`, and
  `tags_all` holds the six tags in [providers.tf](../../terraform/dev-datastore/providers.tf).
- The parameter is `cloud-platform-reference-dev-datastore-endpoint`, `String`, `Standard`, with
  `value_known_after_apply` `true`.
- The proof finds no occurrence.

**PASS when.**

- [ ] The static checks passed, and state inspection listed the six Stage 1 addresses and the
  root's data sources, with the serial, lineage and address digest recorded.
- [ ] Exit 2, with the master opened and closed once in `plan.log`.
- [ ] Exactly the two creates, the six Stage 1 addresses `no-op`, no outputs, and no drift beyond
  the four listed.
- [ ] Every instance and parameter value as expected.
- [ ] The proof found no occurrence, and the plan is bound.

**STOP if.**

- A STOP in a linked shared procedure, including a failed static check or a state address set
  that differs.
- An exit code other than 2.
- Any other action, address, drift or output.
- Any value that differs from the configuration.
- The master opened more than once.
- A proof that finds the value or cannot complete.

**If it fails.** A proof that finds the value or cannot complete:
[Contain an exposed or unproven master value](#contain-an-exposed-or-unproven-master-value). Any
other failure: do not bind or approve the plan, and follow the STOP conditions in
[Review the saved plan](terraform-operations.md#review-the-saved-plan). A new plan needs a new
`<private-dir>`, and it reads the master value again, so it needs its own grant. A failed static
check or state inspection: follow that procedure's **If it fails** in
[terraform-operations.md](terraform-operations.md).

**Evidence to keep.** In the campaign's evidence set: the serial, lineage and address digest, the
UTC time the plan started, the exit code, the review lists, both value checks, the plan hash and
the proof's counts. The saved plan and `plan.log` stay in `<private-dir>`.

**Next step.** An owner grant naming the plan hash, then
[Run the pre-apply gate](#run-the-pre-apply-gate), then the apply.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-24) |
| Published form | not executed as written (the executed plan used the linked plan command through private tooling, from an extracted copy of the committed root, with credentials exported instead of `AWS_PROFILE`, a local provider directory and an allowlisted environment; its review ran as a 48-property check that is not published, from which the `jq` filters below are derived) |
| Evidence basis | [What it creates](../../terraform/dev-datastore/README.md#what-it-creates), [database.tf](../../terraform/dev-datastore/database.tf); retained private evidence of the 2026-09-24 plan, its expected-value check and its secret-absence proof |
| Authority | Explicit owner grant: the plan reads the master value once |
| Cost | None beyond per-request API charges |

- The executed check also proved that the configuration held no module, provisioner or other
  secret read; the published review covers actions, drift, outputs and the principal values.
- The executed runs reduced Terraform's environment to an allowlist and recorded what each run
  received; the published form relies on the debug-logging check.

### Run the pre-apply gate

**Validation:** DESIGNED-NOT-EXECUTED (never) · **Published command form:** not executed as written

**What this does.** Immediately before the Stage 2 apply, confirms that nothing the saved plan
assumed has changed. It opens shared step 10; the apply follows. This checklist covers the first
creation of the instance; no gate exists for a later apply of this root.

**Before you start.**

- [ ] A bound saved plan from
  [Stage 2: plan the instance and its endpoint parameter](#stage-2-plan-the-instance-and-its-endpoint-parameter),
  with its recorded start time, its `<plan-json>` and the bind step's lock-file result.
- [ ] The owner's grant naming the plan hash, which the Saved plan check compares.
- [ ] An exported shell on the intended account, with at least 50 minutes remaining.
- [ ] Everything the apply needs, so that it can start straight after a full pass
  ([Stage 2: apply the reviewed saved plan](#stage-2-apply-the-reviewed-saved-plan)).

**Safety and authority.** Read-only; never reads a secret value. Any failed or unreadable check is
a HOLD, and a HOLD applies nothing.

**Steps.**

1. Confirm each absence by its error code, never by an empty or failed read. Each command prints
   the value it reads, or only the error code:
   ```
   aws rds describe-db-instances --profile <profile> --region us-east-1 \
     --db-instance-identifier cloud-platform-reference-dev-datastore \
     --query 'DBInstances[0].[DBInstanceStatus,DeletionProtection]' --output text 2>&1 \
     | sed -E 's/^.*An error occurred \(([A-Za-z]+)\).*$/error: \1/'
   aws rds describe-db-snapshots --profile <profile> --region us-east-1 \
     --db-snapshot-identifier cloud-platform-reference-dev-datastore-final \
     --query 'DBSnapshots[0].Status' --output text 2>&1 \
     | sed -E 's/^.*An error occurred \(([A-Za-z]+)\).*$/error: \1/'
   aws ssm get-parameter --profile <profile> --region us-east-1 \
     --name cloud-platform-reference-dev-datastore-endpoint \
     --query 'Parameter.Type' --output text 2>&1 \
     | sed -E 's/^.*An error occurred \(([A-Za-z]+)\).*$/error: \1/'
   ```
   > **Warning:** Any other error code, for example `AccessDenied`, is not an absence.
2. Confirm that the engine can be ordered in both subnet zones:
   ```
   aws rds describe-orderable-db-instance-options --profile <profile> --region us-east-1 \
     --engine postgres --engine-version 17.11 --db-instance-class db.t4g.micro \
     --query 'OrderableDBInstanceOptions[?StorageType==`"gp3"`].AvailabilityZones[].Name'
   ```
3. Work through the checklist. Any failed or unreadable check is a HOLD.

   | Check | Pass condition |
   |---|---|
   | Plan age | No more than 72 hours after the recorded plan start, the maximum the executed gate allowed, with at least 30 minutes of that left |
   | Saved plan | Bound as in [Bind the saved plan to its hash and to state](terraform-operations.md#bind-the-saved-plan-to-its-hash-and-to-state); its hash equals the hash in the grant; it has never been applied (the bind procedure's step 3: the serial and lineage still equal the plan's) |
   | Terraform and provider | `terraform version -json \| jq -r .terraform_version` prints the `terraform_version` in `<plan-json>`, and the lock-file line of the bind procedure's step 2, recorded at step 10 of the Stage 2 plan, printed `same` |
   | Session | On the intended account, with at least 50 minutes remaining |
   | Master container | Exactly the placed version, `AWSCURRENT` only, rotation off ([Verify the secret containers](#verify-the-secret-containers-without-reading-a-value)) |
   | Application container | Empty |
   | Instance | `error: DBInstanceNotFound` |
   | Final snapshot name | `error: DBSnapshotNotFound` |
   | Endpoint parameter | `error: ParameterNotFound` |
   | Network boundary | Unchanged ([Read back the network boundary](#read-back-the-network-boundary)) |
   | Engine | Step 2 lists both subnet zones |
   | Prices | Every rate the instance bills equal to the price table in [Re-check prices before billable work](cost-and-residue.md#re-check-prices-before-billable-work) |
   | Budget | The budget and its alerts intact, each alert with a subscriber, and no alert in `ALARM` unless an owner decision recorded this month allows that level, as the read-back's **Next step** and **Cost controls** in [Before you start](#before-you-start) state ([Read back the budget and its alert states](cost-and-residue.md#read-back-the-budget-and-its-alert-states)) |
   | Runtime | Every runtime class of the census is zero ([Run the orphan census](cost-and-residue.md#run-the-orphan-census)) |

4. Start the apply straight after a full pass.

**Expected result.** Every check passes. Step 1 prints `error: DBInstanceNotFound`,
`error: DBSnapshotNotFound` and `error: ParameterNotFound`, and step 2 lists both subnet zones.
Any other error code, for example `AccessDenied`, is not an absence.

**PASS when.**

- [ ] Every row of the checklist passes.

**STOP if.**

- Any HOLD. A HOLD applies nothing; a new plan needs a new `<private-dir>`.

**If it fails.** Do not apply. Any failure that needs a new plan, such as a plan past its age
limit, is replaced only by a new plan from
[Stage 2: plan the instance and its endpoint parameter](#stage-2-plan-the-instance-and-its-endpoint-parameter),
in a new `<private-dir>` and under its own grant, because a new plan reads the master value again.
A saved-plan or lock-file mismatch is diagnosed with
[Bind the saved plan to its hash and to state](terraform-operations.md#bind-the-saved-plan-to-its-hash-and-to-state);
its replacement plan still comes only from the Stage 2 plan procedure. The procedure that owns any
other failed check handles it: the session in
[Check session headroom before long operations](operator-access.md#check-session-headroom-before-long-operations);
the containers in
[Verify the secret containers](#verify-the-secret-containers-without-reading-a-value); the boundary
in [Read back the network boundary](#read-back-the-network-boundary); prices, budget and runtime
classes in [Re-check prices before billable work](cost-and-residue.md#re-check-prices-before-billable-work),
[Read back the budget and its alert states](cost-and-residue.md#read-back-the-budget-and-its-alert-states)
and [Run the orphan census](cost-and-residue.md#run-the-orphan-census). A Terraform version that
differs from the plan's, an engine that cannot be ordered in both subnet zones, or an instance,
final snapshot or parameter that already exists has no procedure in this runbook; work stays
stopped until a reviewed decision is taken under explicit approval
([When to stop](README.md#when-to-stop)).

**Evidence to keep.** In the campaign's evidence set: the UTC time of the full pass, a pass or
fail for each row, with the `ACCOUNT_MATCH` verdict of the
[account check](operator-access.md#check-the-account-before-aws-commands) for the Session row, and
the output of steps 1 and 2.

**Next step.** [Stage 2: apply the reviewed saved plan](#stage-2-apply-the-reviewed-saved-plan),
straight after a full pass.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | DESIGNED-NOT-EXECUTED (never) |
| Published form | not executed as written (a checklist derived from a single-use read-only gate that ran once, 2026-09-24, immediately before the apply, and passed every check; that gate was bound to one commit, one saved plan and one expiry and cannot be reused) |
| Evidence basis | Retained private evidence of the single-use gate, its offline qualification and its 2026-09-24 run |
| Authority | None (read-only; never reads a secret value) |
| Cost | None beyond per-request API charges |

- The executed gate ran as one command that checked all of these and pinned the plan's expiry. It
  compared the Terraform and provider binaries by hash and the prices against the reviewed cost
  package; this checklist compares the Terraform version, the lock file and the price table
  instead. This checklist has never run as written.

### Stage 2: apply the reviewed saved plan

**Validation:** AWS-VALIDATED (2026-09-24) · **Published command form:** not executed as written

**What this does.** Creates the instance and its endpoint parameter from the reviewed saved plan,
once. Billing starts at creation, whatever follows; the rates are under Cost in the engineering
notes.

**Before you start.**

- [ ] The pre-apply gate passed just now ([Run the pre-apply gate](#run-the-pre-apply-gate)).
- [ ] An owner grant naming the plan hash.
- [ ] A session with at least 50 minutes remaining. The executed create took 6 minutes 10
  seconds.
- [ ] The exported shell the pre-apply gate ran in.
- [ ] Debug logging is off:
  [Keep Terraform debug logging off](terraform-operations.md#keep-terraform-debug-logging-off),
  step 1 (PASS: the check prints nothing). Then return to this list.
- [ ] A tool that implements the
  [secret-absence proof](#prove-the-master-value-is-absent-from-plans-state-and-logs), for step 2;
  the reviewed tool used here is not published. Without one, do not start: the apply reads the
  master value before the proof runs.
- [ ] The apply runs so that closing or losing the terminal cannot end Terraform. That property is
  the requirement. No mechanism for it is published or exercised here, and this page has no check
  that a mechanism meets it.
  > **Warning:** The executed apply was shielded from a terminal hangup by private tooling that is
  > not published; no published form of that shielding has been exercised. In offline
  > qualification, a terminal hangup during an RDS create killed Terraform mid-create unless it
  > was shielded from the hangup; the linked command is not shielded.

**Safety and authority.** Mutating, owner-authorized, billable, secret-reading. The apply passes
the master value through the provider, and the proof in step 2 reads it once.

**Steps.**

1. Apply the reviewed saved plan
   ([Apply the reviewed saved plan](terraform-operations.md#apply-the-reviewed-saved-plan), steps
   1 and 2; shared step 10), redirecting its output to `<private-dir>/apply.log`. Its step 3
   read-back is step 7 of this page's [Normal path](#normal-path). PASS: exit 0 with
   `Apply complete! Resources: 2 added, 0 changed, 0 destroyed.`, the serial advanced, the lineage
   unchanged, and both creates in the address list. Then continue at step 2.
   > **Warning:** Never re-apply. A non-zero exit, an interrupt, a terminal hangup or a summary
   > that differs is a STOP; go to **If it fails**. The linked command is not shielded from a
   > terminal hangup. Run it only under the hangup protection in **Before you start**; without
   > it, do not apply.
2. Run the [secret-absence proof](#prove-the-master-value-is-absent-from-plans-state-and-logs).
3. Take the first CPU-credit reading:
   [Check the datastore CPU credits](cost-and-residue.md#check-the-datastore-cpu-credits), steps 1
   and 2 (PASS: every metric prints lines, `CPUSurplusCreditsCharged` is 0 in every period and
   `CPUSurplusCreditBalance` is 0 in the latest periods; a surplus balance with a documented cause,
   such as the start-up burst after a create, and nothing charged, is recorded as an explained
   review trigger, not a STOP). Then continue at step 4.
4. After the event-history delay, account for the apply's Secrets Manager events with
   [Account for secret reads and writes in CloudTrail](#account-for-secret-reads-and-writes-in-cloudtrail).
   Use as `<utc-start>` the UTC time printed before the apply in step 1 above; an earlier time also
   counts the plan's reads. Before the delay has passed, a missing read is not yet a finding:
   repeat the read-only lookup, never the apply.

**Expected result.** Exit 0. `apply.log` shows the master opened and closed once,
`aws_db_instance.datastore: Creation complete`, `aws_ssm_parameter.endpoint: Creation complete` and
`Apply complete! Resources: 2 added, 0 changed, 0 destroyed.` The proof finds no occurrence.
[Account for secret reads and writes in CloudTrail](#account-for-secret-reads-and-writes-in-cloudtrail)
shows one provider read of the master for the apply, one proof read and no secret write.

**PASS when.**

- [ ] Exit 0 and the expected summary line.
- [ ] The master opened and closed once in `apply.log`.
- [ ] The proof found no occurrence.
- [ ] CloudTrail shows one provider read, one proof read and no secret write.

**STOP if.**

- A non-zero exit, an interrupt, a terminal hangup or a summary that differs. Never re-apply.
- A proof that finds the value or cannot complete.

**If it fails.** Follow the stop rule in
[Stop after a failed or interrupted apply](terraform-operations.md#stop-after-a-failed-or-interrupted-apply),
with [Read the datastore after a failed or interrupted apply](#read-the-datastore-after-a-failed-or-interrupted-apply)
as its read-back for this root. A proof that finds the value or cannot complete:
[Contain an exposed or unproven master value](#contain-an-exposed-or-unproven-master-value).

**Evidence to keep.** The hash check, the exit code, the summary line, the proof's counts and the
Secrets Manager accounting.

**Next step.** [Read back the instance and its endpoint parameter](#read-back-the-instance-and-its-endpoint-parameter)
and [Confirm convergence](#confirm-convergence).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-24) |
| Published form | not executed as written (the executed apply used the linked apply command through private tooling, with credentials exported instead of `AWS_PROFILE`, an allowlisted environment, a 50-minute session margin and Terraform shielded from a terminal hangup) |
| Evidence basis | [Status](../../terraform/dev-datastore/README.md#status); retained private evidence of the 2026-09-24 gate, apply, post-apply proof and CloudTrail accounting |
| Authority | Explicit owner grant naming the saved plan's hash |
| Cost | Billing starts at creation, whatever follows: about 0.0192 USD an hour for the instance and storage, plus CPU-credit charges with no cap, up to about 0.15 USD an hour at full load ([cost](../../terraform/dev-datastore/README.md#decommission)) |

- Only the Secrets Manager events have a published accounting command. On 2026-09-24 the apply's
  other management events were also accounted, by reads that are not published: exactly the two
  creates (`CreateDBInstance` and `PutParameter`) and, as AWS service side effects of the create,
  KMS grants and the instance's network interface. A reproducer has no published command for that
  check.
- **Teardown / decommission.** Not exercised; see
  [Decommission](../../terraform/dev-datastore/README.md#decommission), which gives an order only:
  no command-level procedure exists, and each of its state changes runs only as a reviewed saved
  plan under a separate explicit owner grant.

### Read back the instance and its endpoint parameter

**Validation:** AWS-VALIDATED (2026-09-24) · **Published command form:** not executed as written

**What this does.** Confirms that the instance and the parameter in AWS match the configuration,
and that the state keeps the protections and holds no password. It is shared step 11 for Stage 2.

**Before you start.**

- [ ] The Stage 2 apply ended with the expected summary
  ([Stage 2: apply the reviewed saved plan](#stage-2-apply-the-reviewed-saved-plan)).
- [ ] The Stage 2 working tree, for step 5.
- [ ] An exported shell with at least 5 minutes remaining for the read-back with its convergence
  plan.

**Safety and authority.** Read-only. Step 4 compares the parameter's value with the instance
address without printing either.

**Steps.**

1. Run [Read back the network boundary](#read-back-the-network-boundary) in this shell. Its step 1
   sets `$sg`, which step 3 below uses.
2. Read the instance:
   ```
   aws rds describe-db-instances --profile <profile> --region us-east-1 \
     --db-instance-identifier cloud-platform-reference-dev-datastore \
     --query 'DBInstances[0].{status:DBInstanceStatus,engine:Engine,version:EngineVersion,class:DBInstanceClass,storage:AllocatedStorage,storageType:StorageType,encrypted:StorageEncrypted,public:PubliclyAccessible,multiAZ:MultiAZ,network:NetworkType,port:Endpoint.Port,backupDays:BackupRetentionPeriod,backupWindow:PreferredBackupWindow,maintenanceWindow:PreferredMaintenanceWindow,deletionProtection:DeletionProtection,copyTags:CopyTagsToSnapshot,autoMinorUpgrade:AutoMinorVersionUpgrade,iamAuth:IAMDatabaseAuthenticationEnabled,managedSecret:MasterUserSecret && `true` || `false`,user:MasterUsername,dbName:DBName,ca:CACertificateIdentifier,lifecycle:EngineLifecycleSupport,parameterGroups:DBParameterGroups[].[DBParameterGroupName,ParameterApplyStatus],subnetGroup:DBSubnetGroup.DBSubnetGroupName,subnetZones:DBSubnetGroup.Subnets[].SubnetAvailabilityZone.Name,maxStorage:MaxAllocatedStorage,performanceInsights:PerformanceInsightsEnabled,monitoring:MonitoringInterval,logExports:EnabledCloudwatchLogsExports,tags:TagList}'
   ```
3. Confirm that the instance sits behind the datastore security group alone, using `$sg` from
   step 1, and that its storage key is AWS-managed:
   ```
   aws rds describe-db-instances --profile <profile> --region us-east-1 \
     --db-instance-identifier cloud-platform-reference-dev-datastore \
     --query "DBInstances[0].{groups:length(VpcSecurityGroups),datastoreGroup:VpcSecurityGroups[?VpcSecurityGroupId=='$sg'].Status}"
   aws kms describe-key --profile <profile> --region us-east-1 \
     --key-id "$(aws rds describe-db-instances --profile <profile> --region us-east-1 \
       --db-instance-identifier cloud-platform-reference-dev-datastore \
       --query 'DBInstances[0].KmsKeyId' --output text)" \
     --query 'KeyMetadata.[KeyManager,KeyState]' --output text
   ```
4. Read the endpoint parameter and its tags, and compare its value with the instance address
   without printing either. A failed or empty read prints `MISMATCH`:
   ```
   aws ssm describe-parameters --profile <profile> --region us-east-1 \
     --parameter-filters Key=Name,Values=cloud-platform-reference-dev-datastore-endpoint \
     --query 'Parameters[].[Name,Type,Tier,Version]' --output text
   aws ssm list-tags-for-resource --profile <profile> --region us-east-1 \
     --resource-type Parameter --resource-id cloud-platform-reference-dev-datastore-endpoint \
     --query 'TagList'
   p=$(aws ssm get-parameter --profile <profile> --region us-east-1 \
       --name cloud-platform-reference-dev-datastore-endpoint --query 'Parameter.Value' --output text) &&
   d=$(aws rds describe-db-instances --profile <profile> --region us-east-1 \
       --db-instance-identifier cloud-platform-reference-dev-datastore \
       --query 'DBInstances[0].Endpoint.Address' --output text) &&
   [ -n "$p" ] && [ "$p" = "$d" ] && echo MATCH || echo MISMATCH
   unset p d
   ```
5. From `terraform/dev-datastore` in the working tree, read the protections and the password
   fields from the state:
   ```
   AWS_PROFILE=<profile> terraform show -json \
     | jq '.values.root_module.resources[] | select(.address == "aws_db_instance.datastore") | .values
         | {deletion_protection, skip_final_snapshot, final_snapshot_identifier,
            password, password_wo, password_wo_version}'
   ```
6. Run [Verify the secret containers](#verify-the-secret-containers-without-reading-a-value).

**Expected result.**

| Read | Expected |
|---|---|
| Instance | `available`; `postgres` `17.11`; `db.t4g.micro`; `20` GiB `gp3`, encrypted; not public; not Multi-AZ; `IPV4`; port `5432` |
| Backups and maintenance | `7` days, `04:00-04:30`; `sun:05:00-sun:05:30`; automatic minor upgrades off; tags copied to snapshots |
| Protection and access | Deletion protection `true`; IAM authentication `false`; `managedSecret` `false`; user `otel_admin`, database `otel` |
| Engine settings | CA `rds-ca-rsa2048-g1`; `default.postgres17`, `in-sync`; lifecycle `open-source-rds-extended-support-disabled` |
| Extras | `maxStorage`, `logExports` `null`; Performance Insights `false`; monitoring `0` |
| Placement | Subnet group `cloud-platform-reference-dev-datastore` over two different zones; `groups` `1`, `datastoreGroup` `["active"]` |
| Storage key | `AWS Enabled` |
| Tags | The six tags in [providers.tf](../../terraform/dev-datastore/providers.tf) on the instance and the parameter |
| Parameter | One line, `String Standard 1`; `MATCH` |
| State | `true`, `false`, `cloud-platform-reference-dev-datastore-final`; `password` and `password_wo` `null`; `password_wo_version` `1` |

**PASS when.**

- [ ] Every row of the table matches.
- [ ] Step 4 prints `MATCH`.
- [ ] The checks in steps 1 and 6 pass.

**STOP if.**

- Any value that differs, `MISMATCH`, a failed read, or a public or open path.

**If it fails.** This runbook has no recovery procedure for a value that differs. Work stays
stopped until a reviewed decision is taken under explicit approval
([When to stop](README.md#when-to-stop)).

**Evidence to keep.** The output of every step, projected as above.

**Next step.** [Confirm convergence](#confirm-convergence).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-24) |
| Published form | not executed as written (derived from the executed read-back, whose `describe` output and Terraform state were compared in memory against the expected values; `--query` and `jq` projections added) |
| Evidence basis | [Status](../../terraform/dev-datastore/README.md#status); retained private evidence of the 2026-09-24 read-back and of an independent read-only read the same day |
| Authority | None (read-only) |
| Cost | None |

- The final-snapshot settings and `prevent_destroy` are visible only in Terraform state and
  configuration; AWS applies the snapshot settings at deletion. A configured final snapshot does
  not exist until deletion, and an automated backup is not proof that data can be restored.
- The executed read-back also counted the account's DB instances and snapshots; that census
  belongs to [cost-and-residue.md](cost-and-residue.md).

### Confirm convergence

**Validation:** AWS-VALIDATED (2026-09-24) · **Published command form:** not executed as written

**What this does.** Shows that the configuration and the account agree after the apply, and that
the check itself left no copy of the value.

**Before you start.**

- [ ] The Stage 2 apply is complete, and you work from the Stage 2 working tree.
- [ ] An exported shell with at least 5 minutes remaining for the read-back with its convergence
  plan.
- [ ] An explicit owner grant: the plan reads the master value once, and the proof in step 2
  reads it once.
- [ ] A tool that implements the
  [secret-absence proof](#prove-the-master-value-is-absent-from-plans-state-and-logs), for step 2;
  the reviewed tool used here is not published. Without one, do not start: the plan reads the
  master value before the proof runs.

**Safety and authority.** Secret-reading, owner-authorized. The plan writes no state. Step 3 is
local-only.

> **Warning:** Like the Stage 1 tree, the Stage 2 working tree holds copies of the untracked
> inputs. No rule for removing it has been defined or exercised; it stays private, and nothing
> from it is shared before a proof over it has found no occurrence.

**Steps.**

1. Keep debug logging off and confirm convergence
   ([Confirm convergence](terraform-operations.md#confirm-convergence), step 1; shared step 12),
   redirecting the plan's output to `converge.log` in a new `<private-dir>`, as for every plan.
   PASS: exit 0 with `No changes. Your infrastructure matches the configuration.`, eight
   `Refreshing state...` lines in `converge.log`, and the master opened and closed once. Then
   continue at step 2.
2. Run the [secret-absence proof](#prove-the-master-value-is-absent-from-plans-state-and-logs),
   which covers `converge.log`.
3. Close the campaign's evidence set, opened in step 1 of
   [Stage 2: plan the instance and its endpoint parameter](#stage-2-plan-the-instance-and-its-endpoint-parameter)
   (shared step 13): steps 4 to 7 of the [Normal path](evidence-handling.md#normal-path) of
   evidence-handling.md. PASS: the sweep detects every planted instance, with zero value hits and
   every pattern hit explained, and every manifest entry reports OK. Then return here for the
   **Next step**.

**Expected result.** Exit 0 and `No changes. Your infrastructure matches the configuration.`, with
all eight managed resources refreshed and the master opened and closed once. The eight are eight
`Refreshing state...` lines in `converge.log`: the six Stage 1 addresses,
`aws_db_instance.datastore` and `aws_ssm_parameter.endpoint`. The proof finds no occurrence.

**PASS when.**

- [ ] Exit 0 and `No changes.`, with all eight managed resources refreshed.
- [ ] The master opened and closed once.
- [ ] The proof found no occurrence.

**STOP if.**

- Exit 2 or 1: find the cause as in [terraform-operations.md](terraform-operations.md) before
  anything else runs.
- A proof that finds the value or cannot complete.

**If it fails.** Exit 2 or 1: follow the STOP conditions of
[Confirm convergence](terraform-operations.md#confirm-convergence) in terraform-operations.md. A
proof that finds the value or cannot complete:
[Contain an exposed or unproven master value](#contain-an-exposed-or-unproven-master-value).

**Evidence to keep.** In the campaign's evidence set, before step 3 closes it: the exit code and
the `No changes.` line as verdicts, the count of `Refreshing state...` lines, the master's
opening and closing count, and the proof's counts. `converge.log` stays in its `<private-dir>`;
plan text never goes into the set ([Normal path](terraform-operations.md#normal-path) of
terraform-operations.md).

**Next step.** The normal path ends here. While the instance exists, the weekly ADR-0013 review
follows: [Record the weekly ADR-0013 review](cost-and-residue.md#record-the-weekly-adr-0013-review),
weekly, first due 2026-10-01, after that week's budget read-back, CPU-credit check and orphan
census (PASS: one dated private record with all seven entries, identifiers redacted, stating the
decision and why).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-24) |
| Published form | not executed as written (the executed convergence plan used the linked command through private tooling, with credentials exported instead of `AWS_PROFILE`, an allowlisted environment and its output captured for the proof) |
| Evidence basis | [Status](../../terraform/dev-datastore/README.md#status); retained private evidence of the 2026-09-24 convergence plan and its proof |
| Authority | Explicit owner grant: the plan reads the master value once |
| Cost | None beyond per-request API charges |

### Read back the network boundary

**Validation:** AWS-VALIDATED (2026-09-22, 2026-09-24) · **Published command form:** not executed as written

**What this does.** Confirms that the security group admits TCP 5432 from the two private subnet
ranges and nothing else, has no egress rule, and that the subnet group spans the two private
subnets. Step 1 also sets `$sg`, which
[Read back the instance and its endpoint parameter](#read-back-the-instance-and-its-endpoint-parameter)
reuses.

**Before you start.**

- [ ] Stage 1 is applied
  ([Stage 1](#stage-1-create-the-network-boundary-and-the-empty-secret-containers)).
- [ ] A signed-in session: [Sign in](operator-access.md#sign-in), steps 1 and 2 (PASS: the
  identity check prints `True` twice and the account check prints `ACCOUNT_MATCH=PASS`). Then
  return to this list.

**Safety and authority.** Read-only.

**Steps.**

1. Find the security group by name:
   ```
   sg=$(aws ec2 describe-security-groups --profile <profile> --region us-east-1 \
     --filters Name=group-name,Values=cloud-platform-reference-dev-datastore \
     --query 'SecurityGroups[].GroupId' --output text)
   echo "$sg" | wc -w
   ```
2. Read its rules and tags:
   ```
   aws ec2 describe-security-group-rules --profile <profile> --region us-east-1 \
     --filters Name=group-id,Values="$sg" \
     --query 'SecurityGroupRules[].[IsEgress,IpProtocol,FromPort,ToPort,CidrIpv4]' --output text
   aws ec2 describe-security-groups --profile <profile> --region us-east-1 \
     --group-ids "$sg" --query 'SecurityGroups[0].Tags'
   ```
3. Read the subnet group and its tags:
   ```
   aws rds describe-db-subnet-groups --profile <profile> --region us-east-1 \
     --db-subnet-group-name cloud-platform-reference-dev-datastore \
     --query 'DBSubnetGroups[0].{status:SubnetGroupStatus,zones:Subnets[].SubnetAvailabilityZone.Name}'
   aws rds list-tags-for-resource --profile <profile> --region us-east-1 \
     --resource-name "$(aws rds describe-db-subnet-groups --profile <profile> --region us-east-1 \
       --db-subnet-group-name cloud-platform-reference-dev-datastore \
       --query 'DBSubnetGroups[0].DBSubnetGroupArn' --output text)" \
     --query 'TagList'
   ```

**Expected result.**

| Read | Expected |
|---|---|
| Security groups with the name | 1 |
| Rules | Exactly two lines, `False tcp 5432 5432` from `10.20.0.0/20` and from `10.20.16.0/20`, the private ranges in the [address plan](../../terraform/dev/README.md#address-plan); no line beginning `True` |
| Tags | The six tags in [providers.tf](../../terraform/dev-datastore/providers.tf) on both; the security group also carries `Name` |
| Subnet group | `Complete`, over two different zones |

**PASS when.**

- [ ] Every row of the table matches.

**STOP if.**

- Any other rule, any egress rule, more than one group with the name, or a failed read. A failed
  read is never read as absence.

**If it fails.** This runbook has no recovery procedure for a boundary that differs. Work stays
stopped until a reviewed decision is taken under explicit approval
([When to stop](README.md#when-to-stop)).

**Evidence to keep.** The output, kept with the evidence of the procedure that ran this check:
Stage 1 keeps both read-backs, and the instance read-back keeps the output of every step.

**Next step.** Return to the procedure that called this check.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22, 2026-09-24) |
| Published form | not executed as written (derived from the reads of the two executed read-backs, whose output was compared in memory; `--query` projections added) |
| Evidence basis | [Boundary](../../terraform/dev-datastore/README.md#boundary), [network.tf](../../terraform/dev-datastore/network.tf); retained private evidence of the 2026-09-22 and 2026-09-24 read-backs |
| Authority | None (read-only) |
| Cost | None |

- The boundary is a network position, not least privilege
  ([Boundary](../../terraform/dev-datastore/README.md#boundary)). It has been read back with the
  instance absent and present, never during a runtime window.
- The 2026-09-24 read-back covered only the rules, the absence of egress and the subnet group's
  membership; the tags and the subnet group's `Complete` status were last read back on 2026-09-22.
- The VPC-wide view with the datastore present is in [dev-network.md](dev-network.md).

### Verify the secret containers without reading a value

**Validation:** AWS-VALIDATED (2026-09-22, 2026-09-24) · **Published command form:** not executed as written

**What this does.** Establishes each container's state from metadata alone: both empty before
placement, the master holding exactly one version after it, and, before every plan or apply of this
root, the master unchanged and the application container still empty.

**Before you start.**

- [ ] A signed-in session: [Sign in](operator-access.md#sign-in), steps 1 and 2 (PASS: the
  identity check prints `True` twice and the account check prints `ACCOUNT_MATCH=PASS`). Then
  return to this list.
- [ ] After placement, the placement token, kept privately, for step 3.

**Safety and authority.** Read-only; never calls `GetSecretValue`.

**Steps.**

The commands set `TZ=UTC` because the CLI renders some timestamps in the host's local offset,
which the executed reads had to correct.

1. Describe each container. `<container>` is `cloud-platform-reference-dev-datastore-master` or
   `cloud-platform-reference-dev-datastore-app`:
   ```
   TZ=UTC aws secretsmanager describe-secret --profile <profile> --region us-east-1 \
     --secret-id <container> \
     --query '{name:Name,deleted:DeletedDate,rotation:RotationEnabled,key:KmsKeyId && `"customer-managed"` || `"default"`,lastChanged:LastChangedDate,lastAccessed:LastAccessedDate,stages:values(VersionIdsToStages || `{}`),tags:Tags}'
   ```
2. List each container's versions, including deprecated ones:
   ```
   TZ=UTC aws secretsmanager list-secret-version-ids --profile <profile> --region us-east-1 \
     --secret-id <container> --include-deprecated \
     --query '{versions:length(Versions),stages:Versions[].VersionStages,created:Versions[].CreatedDate}'
   ```
3. After placement, confirm that the master's only version is the placement token, without
   printing it:
   ```
   aws secretsmanager list-secret-version-ids --profile <profile> --region us-east-1 \
     --secret-id cloud-platform-reference-dev-datastore-master --include-deprecated \
     --query "length(Versions[?VersionId=='<placement-token>'])"
   ```
4. Confirm that these are the only datastore secrets and that neither is scheduled for deletion:
   ```
   aws secretsmanager list-secrets --profile <profile> --region us-east-1 --include-planned-deletion \
     --filters Key=name,Values=cloud-platform-reference-dev-datastore \
     --query 'SecretList[].{name:Name,deleted:DeletedDate}'
   ```

**Expected result.**

| Field | Master, before placement | Master, after placement | Application container |
|---|---|---|---|
| `deleted` | `null` | `null` | `null` |
| `rotation` | `null` or `false` | `null` or `false` | `null` or `false` |
| `key` | `default` | `default` | `default` |
| `versions`, `stages` | `0`, `[]` | `1`, `[["AWSCURRENT"]]`, created inside the placement window | `0`, `[]` |
| Token check (step 3) | not applicable | `1` | not applicable |
| `lastAccessed` | `null` | `null` until the first plan reads the value, then that day | `null` |
| `tags` | the six tags in [providers.tf](../../terraform/dev-datastore/providers.tf) | unchanged | unchanged |
| Step 4 | the two names, `deleted` `null` | same | same |

**PASS when.**

- [ ] Every field matches the column for the current point: before placement, after placement,
  and the application container at all times.

**STOP if.**

- The application container holds any version or staging label.
- The master holds more than one version, a stage other than `AWSCURRENT`, a version other than
  the placement token, rotation, a customer-managed key or a deletion date.
- Any other datastore-named secret exists.
- Any read fails.

Nothing is planned, applied or placed until the cause is understood.

**If it fails.** During a placement, follow
[Respond to a failed or uncertain placement](#respond-to-a-failed-or-uncertain-placement).
Otherwise no recovery procedure exists: removing a stray version or placing again needs its own
reviewed decision and grant ([Not yet exercised](#not-yet-exercised)).

**Evidence to keep.** The output, kept with the evidence of the procedure that ran this check:
Stage 1 keeps both read-backs, the placement keeps the metadata outputs, and the instance
read-back keeps the output of every step.

**Next step.** Return to the procedure that called this check.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22, 2026-09-24) |
| Published form | not executed as written (derived from the read-only commands executed after Stage 1, after placement and after the Stage 2 apply; `--query` projections added so no ARN or version ID prints) |
| Evidence basis | [What this root does not create](../../terraform/dev-datastore/README.md#what-this-root-does-not-create), [Status](../../terraform/dev-datastore/README.md#status); retained private evidence of the three verifications |
| Authority | None (read-only; never calls `GetSecretValue`) |
| Cost | None beyond per-request API charges |

- `LastAccessedDate` is truncated to the day, so retrieval within a day is accounted for only in
  CloudTrail.
- The seven-day recovery window is a Terraform argument used at deletion; no read shows it.
- These reads do not include the containers' resource policies.
- The executed reads used the administrator profile; the read-only profile has not been tried for
  them.

### Account for secret reads and writes in CloudTrail

**Validation:** AWS-VALIDATED (2026-09-24) · **Published command form:** not executed as written

**What this does.** Shows that every read and write of the datastore secrets since a given time was
an authorized one, without printing an ARN, account number, principal, source address or version
ID.

**Before you start.**

- [ ] `<utc-start>`, the time from which to account, for example the start of a placement or a
  plan.
- [ ] `<placement-token>`, kept privately.
- [ ] A signed-in session: [Sign in](operator-access.md#sign-in), steps 1 and 2 (PASS: the
  identity check prints `True` twice and the account check prints `ACCOUNT_MATCH=PASS`). Then
  return to this list.

**Safety and authority.** Read-only.

**Steps.**

1. List every Secrets Manager event since `<utc-start>`, newest first. The subshell makes a failed
   lookup fail the whole pipeline, so the last line reports it:
   ```
   ( set -o pipefail
     aws cloudtrail lookup-events --profile <profile> --region us-east-1 \
       --lookup-attributes AttributeKey=EventSource,AttributeValue=secretsmanager.amazonaws.com \
       --start-time <utc-start> --query 'Events[].CloudTrailEvent' --output json \
     | jq -r --arg token '<placement-token>' '.[] | fromjson
         | [ .eventTime, .eventName,
             (if .readOnly == true then "read" elif .readOnly == false then "write" else "-" end),
             ((.requestParameters.secretId // "-")
               | if startswith("arn:") then sub("^.*:secret:"; "") | sub("-[A-Za-z0-9]{6}$"; "") else . end),
             ((.requestParameters.versionId // .requestParameters.clientRequestToken // null)
               | if . == null then "-" elif . == $token then "placement-token" else "other-id" end),
             ((.userAgent // "") | if test("terraform-provider-aws") then "terraform"
                                    elif startswith("aws-cli/") then "aws-cli" else "other" end),
             (.errorCode // "ok") ]
         | @tsv' )
   echo "exit $?"
   ```
2. Classify each line against the expected events below. The listing, including an empty one, is a
   result only when the last line is `exit 0`.
   > **Note:** Events can take several minutes to appear, so an absence holds only up to the
   > lookup time minus that delay.

**Expected result.**

| Event | Expected |
|---|---|
| `CreateSecret` | Two, from the Stage 1 apply, when `<utc-start>` precedes it; none after. Stage 1 itself was not accounted in CloudTrail when it ran. |
| `PutSecretValue` | Exactly one since the containers were created: on the master, `placement-token`, `ok`, inside the placement window; none on the application container |
| `GetSecretValue`, `terraform`, no ID | One per plan or apply of this root, on the master |
| `GetSecretValue`, `aws-cli`, `placement-token` | One per run of the [secret-absence proof](#prove-the-master-value-is-absent-from-plans-state-and-logs) |
| Any other `GetSecretValue`, any `BatchGetSecretValue` | None |
| Other writes (`UpdateSecret`, `UpdateSecretVersionStage`, `RotateSecret`, `DeleteSecret`, `PutResourcePolicy`, `TagResource` and similar) | None |
| `DescribeSecret`, `ListSecretVersionIds`, `ListSecrets`, `GetResourcePolicy` | Metadata reads by the verification steps and by Terraform refresh |

**PASS when.**

- [ ] The last line is `exit 0`.
- [ ] Every line matches a row of the table, and no row's count is exceeded.

**STOP if.**

- Any unexpected read or write.
- Any value read (`GetSecretValue` or `BatchGetSecretValue`) or any write on the application
  container.
- A lookup that fails.

**If it fails.** Treat an unexplained read of the master as a possible exposure
([Contain an exposed or unproven master value](#contain-an-exposed-or-unproven-master-value)).

**Evidence to keep.** The listing, kept with the evidence of the procedure that ran this check:
the placement keeps the CloudTrail outputs, and the apply keeps the Secrets Manager accounting.

**Next step.** Return to the procedure that called this check.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-24) |
| Published form | not executed as written (the executed lookups filtered by event name and by write events, and reduced their output in memory before anything was kept; this form filters by event source and reduces the output with `jq`) |
| Evidence basis | Retained private evidence of the post-placement CloudTrail check and of the Stage 2 plan and apply accounting, 2026-09-24 |
| Authority | None (read-only) |
| Cost | None |

- On 2026-09-24 the placement produced exactly one `PutSecretValue`, and the Stage 2 plan, apply,
  convergence plan and their proofs produced exactly the reads in this table.
- Event history holds management events for this region and 90 days; S3 data events on the state
  object are not visible there.
- `lookup-events` accepts one attribute per call.

### Prove the master value is absent from plans, state and logs

**Validation:** AWS-VALIDATED (2026-09-24) for the three runs of the reviewed tool; OFFLINE-VALIDATED (2026-09-24) after a failed apply; DESIGNED-NOT-EXECUTED (never) with an equivalent tool · **Published command form:** not executed as written

**What this does.** Shows that no artifact of a run holds the master value, although every plan
and apply of this root passes it through the provider. Write-only handling keeps it out of state
and plan files by design; this proof measures that.

This page gives the method only. The executed proof is a reviewed tool that is not published,
because every runnable form reads the value.

**Before you start.**

- [ ] An explicit owner grant: each run reads the master value once.
- [ ] A tool that implements this method, able to find a planted copy of the value in every form
  it searches without writing that copy to a file.
- [ ] The run's `<private-dir>` and working tree, not yet shared.
- [ ] An exported shell with at least 5 minutes remaining for a proof after a plan or apply.

**Safety and authority.** Secret-reading, owner-authorized. The value is read once, never
displayed or stored, and the search prints counts only.

> **Warning:** The proof covers `<private-dir>` and the root's directory of the working tree, not
> the operator's terminal scrollback, clipboard or shell history.

**Steps.** These describe the method; no runnable command is published.

1. When: after the Stage 2 plan, after the apply, and after the read-back and convergence plan. A
   proof also runs after a failed apply, before anything from it is shared.
2. What is searched: every regular file in that run's `<private-dir>` and in the root's directory
   of the working tree, `<work-dir>/terraform/dev-datastore`, including `.terraform/` and any
   `errored.tfstate` Terraform leaves there; the saved plan and each of its archive members; its
   JSON rendering; every captured Terraform output; and a fresh pull of the state held only for the
   search. Only the provider binaries under `.terraform/providers` are skipped, as the executed
   proof skipped them.
3. What is prevented rather than searched: Terraform debug logs and protocol dumps. The executed
   runs recorded the names of the environment variables each Terraform run received, and the proof
   required every name to be on an allowlist with no `TF_LOG*`, `TF_CLI_ARGS*`, `TF_VAR_*`,
   `TF_REATTACH_PROVIDERS` or `TF_DATA_DIR`.
4. How: the value is read once through the AWS CLI, by the placement token's version ID, straight
   into the search on standard input. It is never displayed or stored. The search looks for the
   value in its literal form and in common encodings, including base64 at every alignment and inside
   compressed plan members, and prints counts only.
5. Fail-closed rules: the search must first find a planted copy of the value in every form; a
   failed read of the value, the state or any artifact is a HOLD, never a zero; any occurrence is a
   finding. The planted copy is the value itself, so it is never displayed or stored either: it
   exists only in the tool's memory and is never written to a file.
6. Cross-check without the value: the retained evidence is swept for strings in the value's
   format, as chosen at placement, and every hit is accounted for. The executed format is not
   published.

**Expected result.** Zero occurrences in every artifact. The measured result is in
[Status](../../terraform/dev-datastore/README.md#status).

**PASS when.**

- [ ] The planted copy was found in every form, and it was never written to a file.
- [ ] Every read of the value, the state and each artifact succeeded.
- [ ] Zero occurrences in every artifact.
- [ ] Every cross-check hit is accounted for.

**STOP if.**

- Any occurrence, or a proof that cannot complete.

**If it fails.** [Contain an exposed or unproven master value](#contain-an-exposed-or-unproven-master-value).

**Evidence to keep.** The proof's counts, kept with the evidence of the step it followed; the
Stage 2 plan, the apply and the convergence plan all keep them.

**Next step.** Return to the procedure that ran the proof.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-24) for the three runs of the reviewed proof tool, after the Stage 2 plan, after the apply and after the read-back and convergence plan, and their cross-checks; OFFLINE-VALIDATED (2026-09-24) for the reviewed tool after a failed apply; DESIGNED-NOT-EXECUTED (never) for this method with an equivalent tool, in the `<work-dir>` and `<private-dir>` layout |
| Published form | not executed as written (method only; the executed proof is a reviewed tool that is not published, because every runnable form reads the value) |
| Evidence basis | [Status](../../terraform/dev-datastore/README.md#status) records the result; retained private evidence of the plan, post-apply and read-back proofs and of an independent check that never read the value, 2026-09-24 |
| Authority | Explicit owner grant: each run reads the master value once |
| Cost | None beyond per-request API charges |

- The executed runs kept Terraform's working directory inside the searched directory; the layout
  of `<work-dir>` and `<private-dir>` used here has not run.
- Each proof run adds one `GetSecretValue` to CloudTrail.
- The rule behind step 3 is the root README's
  [Debug logging](../../terraform/dev-datastore/README.md#debug-logging).

### Respond to a failed or uncertain placement

**Validation:** OFFLINE-VALIDATED (2026-09-24) · **Published command form:** not executed as written

**What this does.** Leaves the master container in a known state after a placement that did not
end in a clean placed outcome, without ever creating a second version.

**Before you start.**

- [ ] The placement's outcome line and its UTC start time
  ([Place the master value](#place-the-master-value)).
- [ ] The placement grant's terms, including whether a refusal before the write uses up its
  attempt.

**Safety and authority.** Read-only for steps 1, 3 and 4. Step 2 may run the placement again:
mutating and owner-authorized, run only by the owner in the owner's own session, and only as the
placement grant allows ([Place the master value](#place-the-master-value)). Any recovery needs a
separate explicit owner grant.

> **Warning:** Never rerun the placement tool after the write has been attempted. Only a refusal
> before the write can be followed by another run, and only as step 2 allows.

**Steps.**

1. Match the outcome to its class:

   | Outcome | Meaning |
   |---|---|
   | Refused before the write | A target, environment, account, session or preflight check failed. Nothing was written. |
   | Write may have succeeded | The write call returned an error, and the master now shows one version. |
   | No version visible yet | The write call returned an error, and the master showed zero versions at that moment; a committed write can still appear. |
   | Post-check failed | The write returned success, but a metadata post-check failed. |
   | Interrupted or state unknown | A signal arrived during the write, or the version count could not be read. |

2. For a refusal before the write, correct the cause. Run the placement again only if the grant
   states that a refusal before the write does not use up its attempt; otherwise only under a new
   grant. Only the owner runs it, in the owner's own session, as in
   [Place the master value](#place-the-master-value).
3. For every other class, STOP. Do not rerun the tool. Run
   [Verify the secret containers](#verify-the-secret-containers-without-reading-a-value) and
   [Account for secret reads and writes in CloudTrail](#account-for-secret-reads-and-writes-in-cloudtrail),
   and record both.
4. Decide the next step in a separately reviewed decision under a new grant.

**Expected result.** The container's state is known from metadata and CloudTrail, and at most one
version exists.

**PASS when.**

- [ ] The outcome is matched to one class.
- [ ] For every class but a refusal before the write, both reads in step 3 are recorded, and at
  most one version exists.

**STOP if.**

- Any class other than a refusal before the write.

**If it fails.** No recovery after a failed placement has been reviewed or exercised. Removing a
stray version or placing again needs its own reviewed decision and grant
([Not yet exercised](#not-yet-exercised)).

**Evidence to keep.** Both reads from step 3; never the value, the token or an ARN.

**Next step.** A separately reviewed decision under a new grant (step 4).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | OFFLINE-VALIDATED (2026-09-24) |
| Published form | not executed as written (the outcome classes below are the placement's required response classes, exercised only in offline qualification against mocked failures) |
| Evidence basis | Retained private evidence of the placement tool's offline qualification, 2026-09-24 |
| Authority | None for the read-only steps; any recovery needs a separate explicit owner grant |
| Cost | None |

- No live failure has occurred, and no recovery after one has been reviewed or exercised.

### Read the datastore after a failed or interrupted apply

**Validation:** OFFLINE-VALIDATED (2026-09-24) for steps 2 and 3; DESIGNED-NOT-EXECUTED (never) for step 1's not-found reads and step 4's classification · **Published command form:** not executed as written

**What this does.** Supplies the read-back step of the stop rule in
[terraform-operations.md](terraform-operations.md) for this root, without changing anything.

**Before you start.**

- [ ] You are following
  [Stop after a failed or interrupted apply](terraform-operations.md#stop-after-a-failed-or-interrupted-apply)
  after a Stage 2 apply. After a Stage 1 apply, do not run this procedure; use the read-back in
  [Stage 1](#stage-1-create-the-network-boundary-and-the-empty-secret-containers), **If it fails**.
  No proof runs there, because no value exists yet.
- [ ] An explicit owner grant for step 3, which reads the master value once.
- [ ] A tool that implements the
  [secret-absence proof](#prove-the-master-value-is-absent-from-plans-state-and-logs), for step 3;
  the reviewed tool used here is not published.

**Safety and authority.** Read-only for steps 1, 2 and 4; step 3 is secret-reading and
owner-authorized. Any recovery, import or deletion needs a separate explicit owner grant. Billable:
the instance bills from creation if it exists.

> **Warning:** Never re-apply. Nothing in this procedure is retried.

**Steps.**

1. Read the instance and the endpoint parameter with the first and third commands in
   [Run the pre-apply gate](#run-the-pre-apply-gate), step 1.
2. Run [Verify the secret containers](#verify-the-secret-containers-without-reading-a-value).
3. Run the [secret-absence proof](#prove-the-master-value-is-absent-from-plans-state-and-logs)
   before anything from `<private-dir>` or the working tree is shared.
4. Record each of the two planned addresses as the stop rule classifies it, and decide any recovery
   in a separately reviewed decision.

**Expected result.** A recorded state: whether the instance exists, with its status and deletion
protection; whether the parameter exists; the master unchanged; the proof's result.

**PASS when.**

- [ ] Both planned addresses are recorded as the stop rule classifies them.
- [ ] The master is unchanged, and the proof has a result.

**STOP if.**

- This whole procedure runs inside the stop rule, where everything is a stop and nothing is
  retried.
- A proof that finds the value or cannot complete.

**If it fails.** A proof that finds the value or cannot complete:
[Contain an exposed or unproven master value](#contain-an-exposed-or-unproven-master-value). No
recovery after a failed apply has been reviewed or exercised. An instance that exists bills until
it is deleted and carries deletion protection, so removing it needs the reviewed change in
[Decommission](../../terraform/dev-datastore/README.md#decommission). That section gives an order
only: no command-level procedure exists, and each of its state changes runs only as a reviewed
saved plan under a separate explicit owner grant.

**Evidence to keep.** The recorded state from step 4, with the records the stop rule keeps.

**Next step.** Return to step 7 of
[Stop after a failed or interrupted apply](terraform-operations.md#stop-after-a-failed-or-interrupted-apply);
after it, a separately reviewed decision on any recovery (step 4).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | OFFLINE-VALIDATED (2026-09-24) for steps 2 and 3 after a failed apply; DESIGNED-NOT-EXECUTED (never) for step 1's reads with the not-found rule after a failed apply, and for step 4's classification |
| Published form | not executed as written (derived from the qualified read-only inspection, exercised only in offline qualification; confirming absences by error code has run before an apply, never after a failed one) |
| Evidence basis | Retained private evidence of the offline qualification of the apply's failure classes and inspection |
| Authority | None for steps 1, 2 and 4; step 3 reads the master value once and needs an explicit owner grant; any recovery, import or deletion needs a separate explicit owner grant |
| Cost | The instance bills from creation if it exists |

### Contain an exposed or unproven master value

**Validation:** DESIGNED-NOT-EXECUTED (never) · **Published command form:** not executed as written

**What this does.** Stops the spread of the master value when a proof finds it, when a proof cannot
complete, or when the value appears anywhere else.

**Before you start.** Nothing. Start as soon as one of those triggers occurs.

**Safety and authority.** STOP and record only. Any step beyond the STOP and the record needs an
explicit owner grant.

**Steps.**

1. STOP. No further plan or apply, no proof run except the one in step 4 under its own grant, and
   no rerun of the step that produced the artifact.
2. Do not share, copy, commit, upload, export or remove `<private-dir>`, the working tree or any
   artifact from that run. Both stay where they are; `<private-dir>` keeps its owner-only
   permissions.
3. Record which artifact and which step, by name and occurrence count only, never the content.
4. If the proof could not complete, the artifacts are unproven rather than exposed: they stay
   unshared until a proof run completes under its own explicit owner grant, which covers that one
   run and its one read of the master value.
5. If the value was found, treat it as compromised. The remedy is rotation, which is
   [not yet exercised](#not-yet-exercised) and needs its own reviewed procedure and grant. An
   artifact already retained or exported is remediated as in
   [evidence-handling.md](evidence-handling.md).

**Expected result.** Everything is stopped, the artifacts stay where they are, and the record
names the artifact and the step by name and occurrence count only.

**PASS when.**

- [ ] Nothing further has run, and nothing from the run has moved.
- [ ] The record exists, with names and counts only.

**STOP if.** This procedure is itself the STOP.

**If it fails.** Containment has never been needed or exercised, and no rotation procedure exists.
An artifact already retained or exported goes to
[Remediate a prohibited value in retained or exported evidence](evidence-handling.md#remediate-a-prohibited-value-in-retained-or-exported-evidence).

**Evidence to keep.** The record from step 3: artifact and step by name and occurrence count only,
never the content.

**Next step.** For unproven artifacts, one proof run under its own explicit owner grant (step 4).
For a found value, rotation, which needs its own reviewed procedure and grant.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | DESIGNED-NOT-EXECUTED (never) |
| Published form | not executed as written (derived from the reviewed stop behaviour of the plan, apply and proof tooling, whose detection side was exercised only in offline qualification with planted values) |
| Evidence basis | Retained private evidence of the offline qualification, 2026-09-24; no exposure has occurred |
| Authority | Explicit owner grant for any step beyond the STOP and the record |
| Cost | None |

## Not yet exercised

| Item | Label | Note |
|---|---|---|
| [Run the pre-apply gate](#run-the-pre-apply-gate) as a reusable checklist | DESIGNED-NOT-EXECUTED | Only its single-use form ran, once. No gate exists for a later apply of this root. |
| [Contain an exposed or unproven master value](#contain-an-exposed-or-unproven-master-value) | DESIGNED-NOT-EXECUTED | Never needed. |
| [Place the master value](#place-the-master-value) as a step-level procedure with an equivalent tool | DESIGNED-NOT-EXECUTED | Only the reviewed placement tool ran, once. |
| [Prove the master value is absent from plans, state and logs](#prove-the-master-value-is-absent-from-plans-state-and-logs) with an equivalent tool | DESIGNED-NOT-EXECUTED | Only the reviewed proof tool ran, three times on 2026-09-24, with Terraform's working directory inside the searched directory. The `<work-dir>` and `<private-dir>` layout has not run. |
| [Read the datastore after a failed or interrupted apply](#read-the-datastore-after-a-failed-or-interrupted-apply): the not-found reads and the classification | DESIGNED-NOT-EXECUTED | Only its offline qualification ran, and that inspection reported a failed read as not found or absent and classified nothing. No apply has failed. |
| Recovery after a failed or uncertain placement | UNEXERCISED | No reviewed procedure. Removing a stray version or placing again needs its own reviewed decision and grant. |
| Stage 2 apply protected from a terminal hangup, in a published form | UNEXERCISED | The executed apply was shielded by private tooling that is not published. |
| Stage 1 from the current checkout with `-target` | UNEXERCISED | The README's alternative to planning commit `aeb1622`; never run. |
| Master rotation | UNEXERCISED | An operational procedure with no reviewed form. Here rotation means a new master version together with a `password_wo_version` increment in [database.tf](../../terraform/dev-datastore/database.tf). A placement never writes to a non-empty container, so rotation needs its own reviewed procedure and grant. The rotation exercise [ADR-0008](../decisions/0008-define-the-secrets-and-workload-identity-model.md) requires was met on the dev secret path ([Identity, secrets and configuration](../../terraform/dev/README.md#identity-secrets-and-configuration)) and does not cover this secret. |
| Stop and start the instance | UNEXERCISED | No procedure exists. |
| Restore from a snapshot or an automated backup | UNEXERCISED | The workload-data restore exercise that [ADR-0011](../decisions/0011-define-the-backup-and-recovery-model.md) requires is owed now that the datastore exists. It runs only under a separately reviewed recovery package. A retained snapshot or an automated backup is not restore proof. |
| Secret accidental-deletion recovery | UNEXERCISED | [ADR-0011](../decisions/0011-define-the-backup-and-recovery-model.md) requires a secret to be retrieved after a simulated accidental deletion. The seven-day recovery window is configured and has never been verified. |
| Maintenance | UNEXERCISED | Minor-version upgrades (automatic upgrades are off), pending maintenance actions and CA certificate rotation. No procedure exists. |
| Decommission, including the final snapshot's retention and deletion | UNEXERCISED | Designed in [Decommission](../../terraform/dev-datastore/README.md#decommission) as one reviewed change in three steps; no reviewed command sheet exists, and it needs a separate owner grant. No final snapshot exists. |
| Application value and application database role | UNEXERCISED, DEFERRED | The application container stays empty until its consumer path is designed and independently reviewed. |

## Reproducibility gaps

A new engineer cannot yet reproduce the following from the public repositories alone. Separately,
no published command form on this page has been executed as written; each procedure's engineering
notes say what the published form is derived from.

- **Placing the master value.**
  - Cannot be reproduced: the placement as it ran. The reviewed placement tool is not published,
    and the path with an equivalent tool has never run.
  - Public contract: [Place the master value](#place-the-master-value) gives the scope, the
    owner-execution boundary, the value's interface, the placement token, the single write attempt
    with no retry, the metadata and CloudTrail validation and the STOP rules;
    [Respond to a failed or uncertain placement](#respond-to-a-failed-or-uncertain-placement) gives
    the outcome classes.
  - Needed later: yes. Today a reproducer supplies an equivalent tool and qualifies it offline; a
    public tool or runnable procedure would close the gap.
- **The secret-absence proof.**
  - Cannot be reproduced: the proof as it ran. The reviewed tool is not published, because every
    runnable form reads the value, and the value format used by the cross-check is not published.
  - Public contract: the [method](#prove-the-master-value-is-absent-from-plans-state-and-logs):
    when it runs, what it searches, what it prevents, how the value is read, the fail-closed rules
    and the cross-check.
  - Needed later: yes, a public tool that implements the method.
- **Hang-up protection for the Stage 2 apply.**
  - Cannot be reproduced: the shielding the executed apply ran under, which is private tooling
    that is not published. The linked apply command is not shielded.
  - Public contract: the requirement in
    [Stage 2: apply the reviewed saved plan](#stage-2-apply-the-reviewed-saved-plan) that closing
    or losing the terminal cannot end Terraform, and the offline finding that an unshielded hangup
    killed Terraform mid-create.
  - Needed later: yes, a published form, and an exercise of it.
- **The environment control around the Stage 2 plan, apply and convergence plan.**
  - Cannot be reproduced: the private tooling those runs used. All three ran with credentials
    exported instead of `AWS_PROFILE` and an allowlisted environment, and recorded the names of the
    variables each Terraform run received; the plan also ran from an extracted copy of the
    committed root with a local provider directory.
  - Public contract: the linked commands in [terraform-operations.md](terraform-operations.md),
    [Export role credentials once](operator-access.md#export-role-credentials-once),
    [Keep Terraform debug logging off](terraform-operations.md#keep-terraform-debug-logging-off),
    and the variable names the proof's step 3 forbids. The published form relies on the
    debug-logging check.
  - Needed later: a public way to record and check each run's environment, if the allowlist
    control is to be reproduced; none is published.
- **The executed plan review.**
  - Cannot be reproduced: the 48-property check, which is not published. It also proved that the
    configuration held no module, provisioner or other secret read.
  - Public contract: [Review the saved plan](terraform-operations.md#review-the-saved-plan), the
    two value checks and the expected result in
    [Stage 2: plan the instance and its endpoint parameter](#stage-2-plan-the-instance-and-its-endpoint-parameter),
    covering actions, drift, outputs and the principal values.
  - Needed later: only if a reproducer must check the properties the published review does not
    cover; no public form exists for them.
- **The executed pre-apply gate.**
  - Cannot be reproduced: the single-use gate, bound to one commit, one saved plan and one expiry.
    It compared the Terraform and provider binaries by hash and the prices against the reviewed
    cost package.
  - Public contract: the checklist in [Run the pre-apply gate](#run-the-pre-apply-gate), which
    compares the Terraform version, the lock file and the price table instead, and has never run as
    written.
  - Needed later: a first run of the checklist as written, and a gate for any later apply of this
    root, for which none exists.
- **Accounting for the apply's other management events.**
  - Cannot be reproduced: the 2026-09-24 check of `CreateDBInstance`, `PutParameter`, the KMS
    grants and the instance's network interface, which used reads that are not published.
  - Public contract:
    [Account for secret reads and writes in CloudTrail](#account-for-secret-reads-and-writes-in-cloudtrail),
    for Secrets Manager events only.
  - Needed later: yes, a published command for that check.

## Background prerequisites

The suite-wide dependencies this runbook assumes. The runbook index lists them for the whole suite
under Before you start, which you gathered before step 1 of its Build order.

- **Account.** An AWS account of your own.
- **Identity.** An IAM Identity Center operator with an administrator permission set and a CLI
  profile, set up at step 1 of the index's Build order:
  [Configure the local CLI profiles](operator-access.md#configure-the-local-cli-profiles) (PASS:
  for each profile, the identity check prints `True` twice and the account check prints
  `ACCOUNT_MATCH=PASS`). Then return to this list.
- **Toolchain.** Terraform 1.11 or later and below 2.0 (1.15.5 was used) with the `hashicorp/aws`
  provider the committed lock file selects (6.58.0 was used); AWS CLI v2; `jq`; `git`; `unzip`;
  `shasum`.
