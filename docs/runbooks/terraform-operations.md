# Terraform Operations

This runbook is the change workflow that every Terraform root in this repository shares: the static
and security checks, initializing a root against the S3 state backend, the reviewed saved plan and
its binding to state, apply, convergence, drift detection and refresh-only reconciliation, state
locks, the rule for a failed or interrupted apply, moved blocks, and debug-logging safety. It also
holds the state backend's one-time first build.
[ADR-0003](../decisions/0003-adopt-terraform-and-remote-state-management.md) fixes the workflow
and the state model, and
[ADR-0011](../decisions/0011-define-the-backup-and-recovery-model.md) fixes the recovery
obligations for state. This page is the procedure. It does not say what a particular root's plan
should contain, and it does not cover runtime windows. It links, rather than repeats:

- the [runbook index](README.md) for the validation labels and the order in which the roots are
  built;
- the bootstrap README for the backend's
  [first build and migration](../../terraform/bootstrap/README.md#execution-sequence),
  [locking design](../../terraform/bootstrap/README.md#locking-as-it-currently-stands),
  [recovery outline](../../terraform/bootstrap/README.md#recovery) and
  [final decommission](../../terraform/bootstrap/README.md#final-decommission);
- [operator-access.md](operator-access.md) for the workstation toolchain, signing in, the identity
  and account checks, and session lifetime before a long write;
- each root's runbook for what its plans should contain and how its resources are read back:
  [persistent-foundations.md](persistent-foundations.md),
  [public-dns-and-certificate.md](public-dns-and-certificate.md),
  [dev-network.md](dev-network.md) and [dev-datastore.md](dev-datastore.md);
- [cost-and-residue.md](cost-and-residue.md) for the budget read-back and the orphan census;
- [evidence-handling.md](evidence-handling.md) for capturing and redacting output;
- [Runtime Validation](../validation/runtime-validation.md) for runtime windows and their
  teardown, which are outside this runbook. A runtime window creates the EKS cluster, its nodes
  and the NAT gateway on top of the Dev network, exercises them and destroys them at close.

## Normal path

Not every root can run this path to the end today. Check your root before step 1:

| Root | Where this path stops | What lets you continue |
|---|---|---|
| `terraform/bootstrap` | First build: this path does not build it. [Build the state backend and migrate into it](#build-the-state-backend-and-migrate-into-it) does, and on a fresh clone it stops before the Stage 1 apply. Later change: step 7, because no runbook publishes a read-back for its resources. | Nothing published: a reviewed decision under explicit approval ([When something fails](README.md#when-something-fails)). |
| `terraform/foundation` | Build from nothing: its first build follows the [Normal path](public-dns-and-certificate.md#normal-path) of public-dns-and-certificate.md, which currently stops at its certificate stage. Applied root: step 4, unless you hold an expected address set; none is published for this root. | Build from nothing: nothing published, a reviewed decision under explicit approval. Applied root: the address list printed by step 2 of [Apply the reviewed saved plan](#apply-the-reviewed-saved-plan) after the root's last apply, kept in that campaign's evidence (rule 3 in [Inspect state without writing it](#inspect-state-without-writing-it), **Expected result**). |
| `terraform/dev` | Not followed as written: see the first warning below. | Only its targeted first build, [Build only the retained baseline](dev-network.md#build-only-the-retained-baseline), and [Reconcile explained state-only drift](#reconcile-explained-state-only-drift) for its route-table drift. |
| `terraform/dev-datastore` | Not followed on its own: see the second warning below. After its first build, no gate exists for a later apply. | Its first build, through the [Normal path](dev-datastore.md#normal-path) of dev-datastore.md. |

Follow these in order for every change to a root; `terraform/dev` and `terraform/dev-datastore`
are the exceptions, as the warnings below say. The state backend must already exist: it is
built once per project, by
[Build the state backend and migrate into it](#build-the-state-backend-and-migrate-into-it).

Open the campaign's evidence set before step 1, and capture into it what each procedure's
**Evidence to keep** names
([Capture a campaign evidence set](evidence-handling.md#capture-a-campaign-evidence-set)). A
*campaign* is one bounded operation whose evidence is kept together, for example an apply with its
read-back.

**What goes into the evidence set.** Each command's output goes into the set through redaction
([Redact at capture](evidence-handling.md#redact-at-capture)), except:

| Output | Where it goes |
|---|---|
| The saved plan, plan JSON and `apply.log` | `<private-dir>` only, and the set records their sha256 digests ([Capture a campaign evidence set](evidence-handling.md#capture-a-campaign-evidence-set), step 5); exit codes and the apply's summary line go into the set as verdicts. These files can carry input values, bucket names and account identifiers. |
| Plan text: the output of `terraform plan` and `terraform show -no-color` | Never into the set, not even through redaction: it carries the same private values. The published commands print it to the terminal and write no file. A copy you keep goes in `<private-dir>` only, and the set records its sha256. |
| `terraform state pull` | Nowhere. Only its `jq` projection of serial and lineage is kept; a recovery copy is the one exception ([Handle a held state lock](#handle-a-held-state-lock)). |
| `env \| grep '^TF_'` | Nowhere: it prints the variables' values. |

> **Warning: `terraform/dev` does not follow this path as written.** Between runtime windows, a
> plan of that root without targets holds the 17 runtime creates, the billable runtime
> ([Confirm the retained and runtime split](dev-network.md#confirm-the-retained-and-runtime-split)).
> Never apply it; its step 7 review fails for any other change, and step 12 cannot exit 0 there.
> The one published build of that root is the targeted first build,
> [Build only the retained baseline](dev-network.md#build-only-the-retained-baseline), which
> accepts `complete` as `false` in review and runs Confirm the retained and runtime split in
> place of step 12. No procedure in this suite covers any other change to `terraform/dev`, apart
> from reconciling its route-table drift
> ([Reconcile explained state-only drift](#reconcile-explained-state-only-drift)). Work stays
> stopped until a reviewed decision is taken under explicit approval
> ([When something fails](README.md#when-something-fails)).

> **Warning: `terraform/dev-datastore` does not follow this path on its own either.** Its first
> build follows the [Normal path](dev-datastore.md#normal-path) of dev-datastore.md, which uses
> these procedures and adds that root's own controls: the secret-absence proof, the single-use
> pre-apply gate and the hang-up protection of the Stage 2 apply. That runbook has no procedure
> for a later apply of the root, and no gate exists for one. After the first build, a change to
> `terraform/dev-datastore` does not run through this path: a later apply waits for a reviewed
> decision under explicit approval ([When something fails](README.md#when-something-fails)).

1. **Prepare the root.** Put its filled `backend.hcl` and `terraform.tfvars` in its private
   `<inputs-dir>`, and create a new `<private-dir>` for this plan
   ([Before you start](#before-you-start)). Write the reviewed list, the addresses and actions the
   change intends, before the plan is made, and record it as the **Expected** field of the campaign
   record ([Review the saved plan](#review-the-saved-plan), **Before you start**).
2. [Run the static checks](#run-the-static-checks) on the commit under review. No credentials are
   used.
3. [Initialize a root against the state backend](#initialize-a-root-against-the-state-backend) in a
   clean working tree at that commit.
4. [Inspect state without writing it](#inspect-state-without-writing-it), and record the serial,
   lineage and address digest.
5. [Keep Terraform debug logging off](#keep-terraform-debug-logging-off) in the shell that will
   plan and apply.
6. [Plan to a saved file](#plan-to-a-saved-file).
   [Plan without taking the state lock](#plan-without-taking-the-state-lock) says when its
   `-lock=false` is safe. On `terraform/dev`, see the warning above.
7. [Review the saved plan](#review-the-saved-plan). This review is the approval point; the
   approval itself is step 9. Before approval, also check read-back coverage: for every address in
   the reviewed list, the root's runbook publishes a read-back, or the procedure you are following
   says how that address is checked instead. If an address has neither, stop here, before
   approval: its apply would end in the stop in step 3 of
   [Apply the reviewed saved plan](#apply-the-reviewed-saved-plan). A later change to
   `terraform/bootstrap` always stops here, because no runbook in this suite publishes a read-back
   for its resources.
8. [Bind the saved plan to its hash and to state](#bind-the-saved-plan-to-its-hash-and-to-state):
   record the binding at review, and check it again immediately before apply.
9. **Obtain approval.** The owner approves this plan in writing, identified by its sha256. There is
   no command for this step.
10. [Apply the reviewed saved plan](#apply-the-reviewed-saved-plan), once. For a billable change,
    first [read back the budget and its alert states](cost-and-residue.md#read-back-the-budget-and-its-alert-states)
    and [re-check prices](cost-and-residue.md#re-check-prices-before-billable-work), as the
    [task list](README.md#task-list) requires before each billable change. A change is billable
    when it bills a rate; identify the rates from the root's README and the reviewed plan, as the
    price re-check's **Before you start** says. A resource that costs nothing until used bills no
    rate at apply: a new registry repository, for example, costs nothing while it holds no image
    ([Add a registry repository and widen the CI push scope](persistent-foundations.md#add-a-registry-repository-and-widen-the-ci-push-scope)).
    Both cost reads run in the exported shell that
    [cost-and-residue.md](cost-and-residue.md#before-you-start) requires for every procedure, not
    with `AWS_PROFILE=<profile>`. Run them before step 3 of the binding check, which runs in the
    Terraform shell and stays the last check immediately before the apply. In this path the order
    is: approval (step 9), the cost reads, binding step 3, then the apply.
11. **Read back** the changed resources through the root's runbook:
    [persistent-foundations.md](persistent-foundations.md),
    [public-dns-and-certificate.md](public-dns-and-certificate.md),
    [dev-network.md](dev-network.md) or [dev-datastore.md](dev-datastore.md). None of them covers
    `terraform/bootstrap`. Where the root's runbook publishes no read-back for a changed address,
    see step 3 of [Apply the reviewed saved plan](#apply-the-reviewed-saved-plan).
12. [Confirm convergence](#confirm-convergence). Not on `terraform/dev`; see the warning above.
13. **Close the evidence set.** Sweep it with its planted positive control, handle any hit, and
    seal it: steps 4 to 7 of the [Normal path](evidence-handling.md#normal-path) of
    evidence-handling.md.

A clean convergence plan does not prove that every attribute Terraform mirrors in state is
current. [Detect state drift](#detect-state-drift) is the check for that, run when state may lag
AWS ([task list](README.md#task-list)). Reconcile drift only through
[Reconcile explained state-only drift](#reconcile-explained-state-only-drift).

When something goes wrong:

- An apply fails, is interrupted, loses its terminal or session, or reports a different summary:
  [Stop after a failed or interrupted apply](#stop-after-a-failed-or-interrupted-apply).
- Terraform reports `Error acquiring the state lock`:
  [Handle a held state lock](#handle-a-held-state-lock). If an apply reported it, its exit is
  non-zero, so the rules here treat it as a failed apply: go to
  [Stop after a failed or interrupted apply](#stop-after-a-failed-or-interrupted-apply) first.
- A refactor changes resource addresses:
  [Move resource addresses with moved blocks](#move-resource-addresses-with-moved-blocks).
- The state backend's first build or its migration fails or is interrupted:
  [Build the state backend and migrate into it](#build-the-state-backend-and-migrate-into-it),
  **If it fails**.

> **Warning: saved plans, plan JSON and state hold private values.** A saved plan carries every
> input value and the prior state's attributes in clear text. Plan JSON and plan text carry
> account identifiers, bucket names and every input value, and state holds full resource
> attributes. Keep them in `<private-dir>`, outside every Git working tree, and never publish
> them. `.gitignore` excludes `*.tfplan`; it does not exclude JSON, so plan JSON must never be
> written inside the repository. Never redirect `terraform state pull` to a file, except for a
> recovery copy ([Handle a held state lock](#handle-a-held-state-lock)).

> **Warning: never re-run a failed or interrupted apply.** A non-zero exit, an interrupt, a lost
> terminal or session, credentials that expired during the apply, or a summary that differs from
> the review leaves the state unknown. Do not run `apply` again, from this plan or a new one. Go to
> [Stop after a failed or interrupted apply](#stop-after-a-failed-or-interrupted-apply).

> **Warning: force-unlock only a lock proven stale.** Release a state lock only when no Terraform
> CLI or provider process remains on your machine and every other operator with access confirms
> the same, the lock ID matches the one in the error, and the owner has approved. Never use
> `-lock=false` on a write to get past a lock
> ([Handle a held state lock](#handle-a-held-state-lock)).

## Before you start

- [ ] The identity and account checks in [operator-access.md](operator-access.md) pass for
  `<profile>` in the current shell. The *account check*
  ([Check the account before AWS commands](operator-access.md#check-the-account-before-aws-commands))
  compares the caller's account with the root's `allowed_account_id` and prints only a verdict.
- [ ] The tools: the toolchain in [operator-access.md](operator-access.md#prepare-the-workstation-toolchain),
  where Terraform 1.15.5 is the only exercised version. In addition: `git`, `jq`, `unzip`, and
  `shasum` (or `sha256sum`); bash or zsh, for process substitution; TFLint, run as 0.64.0; Trivy,
  run as 0.74.0; and network access to the Terraform registry for a provider install, which has
  no retained evidence here.
- [ ] For each root you work on, a private `<inputs-dir>` holding that root's filled `backend.hcl`,
  which names the state bucket the bootstrap root created, and its filled `terraform.tfvars`,
  which supplies the account ID as `allowed_account_id` and the root's other private inputs. Every
  plan of a root needs all of them, including plans of unrelated changes.
- [ ] A new `<private-dir>` for each plan, and a private evidence location
  ([evidence-handling.md](evidence-handling.md)).
- [ ] For step 4 of the [Normal path](#normal-path), the expected address set for the root at this
  point, from the rules in [Inspect state without writing it](#inspect-state-without-writing-it)
  (**Expected result**). No address list is published for `terraform/foundation`: on an applied
  foundation root, step 4 cannot pass without the list kept from its last apply.
- [ ] Before the campaign's evidence set is opened, which the [Normal path](#normal-path) does
  before its step 1: the private literal list, the address allowlist, a redaction filter, and a
  value-based, archive-aware sweep that fails closed. The project's own filter and sweep are not
  published, so you supply your own
  ([evidence-handling.md](evidence-handling.md#before-you-start)).
- [ ] The owner, the person accountable for the AWS account
  ([runbook index](README.md#conventions)), who approves each apply, refresh-only apply,
  force-unlock and recovery action in writing, identifying the plan by its hash, and, on
  `terraform/dev-datastore`, every plan.
- [ ] For `terraform/dev-datastore`, once its configuration includes `database.tf`, a master secret
  that already holds its value ([dev-datastore.md](dev-datastore.md);
  [What it creates](../../terraform/dev-datastore/README.md#what-it-creates)).

**Roots and their state.**

| Root | State key, from `backend.tf` | Private inputs |
|---|---|---|
| `terraform/bootstrap` | `bootstrap/terraform.tfstate` | [Input](../../terraform/bootstrap/README.md#input) |
| `terraform/foundation` | `foundation/terraform.tfstate` | [Input](../../terraform/foundation/README.md#input) |
| `terraform/dev` | `dev/terraform.tfstate` | [Input](../../terraform/dev/README.md#input) |
| `terraform/dev-datastore` | `dev-datastore/terraform.tfstate` | [What it creates](../../terraform/dev-datastore/README.md#what-it-creates) |

Every backend uses the same bucket in `us-east-1` with `encrypt = true` and
`use_lockfile = true`. The bucket name reaches Terraform only through the untracked `backend.hcl`.

**Placeholders and conventions.**

- `<profile>` is the AdministratorAccess profile from [operator-access.md](operator-access.md).
  The recorded plans and applies ran on that permission set; none has run on ReadOnlyAccess. For
  a long or sensitive operation, [operator-access.md](operator-access.md) runs it on role
  credentials exported once into a clean shell, an
  [exported shell](operator-access.md#export-role-credentials-once); the commands below are then
  run without `AWS_PROFILE=<profile>` or `--profile <profile>`. This runbook does not define which
  operation counts as long or sensitive, and it requires an exported shell for none of its own
  plans or applies. A root's runbook that needs one says so, as
  [dev-datastore.md](dev-datastore.md) does for its Stage 2 runs. On 2026-09-23 the
  `terraform apply` line ran in the form shown, with `AWS_PROFILE=<profile>`
  ([Apply the reviewed saved plan](#apply-the-reviewed-saved-plan), Engineering notes).
- `<root>` is one of `bootstrap`, `foundation`, `dev` or `dev-datastore`: the directory under
  `terraform/` and the prefix of that root's state key.
- `<commit>` is the full SHA of the reviewed commit. The code review that produces that commit is
  outside this runbook. No rule here says whether the change merges to `main` before or after the
  apply, or what to do when the commit that lands on `main` is not `<commit>`; settle it with the
  owner before the apply. The one recorded zone build applied its plan from the reviewed commit
  before the merge, and the same foundation tree was confirmed on merged `main` afterwards
  ([Build the zone on its own](public-dns-and-certificate.md#build-the-zone-on-its-own),
  Engineering notes). `<main-commit>` is the full SHA of `main` that a change is compared
  against. It must be a `main` commit that does not contain the change, normally the one the
  change branched from. If the change has already merged, use `main` as it was just before the
  merge: compared with itself, a change adds no finding class, and step 3 of
  [Run the static checks](#run-the-static-checks) proves nothing.
- On a first build from a clone there is no change under review. `<commit>` is the commit you
  build from, and `<main-commit>` is that same commit, so the class comparison in
  [Run the static checks](#run-the-static-checks) is empty by construction and re-decides nothing.
  The findings the roots already carry are listed by that step's scan. Those recorded on
  2026-09-21 for the foundation and dev-datastore roots were accepted by recorded decision, not
  every rationale is published, and this runbook defines no step in which a reproducer reviews or
  accepts them ([Reproducibility gaps](#reproducibility-gaps)).
- `<work-dir>` is a new directory outside every existing Git working tree, for the working tree
  [Initialize a root against the state backend](#initialize-a-root-against-the-state-backend)
  creates. `<scan-dir>` is a new scratch directory outside every working tree, for the scan in
  [Run the static checks](#run-the-static-checks).
- `<inputs-dir>` is a private directory per root, outside every working tree, holding that
  root's filled `backend.hcl` and `terraform.tfvars`. The roots take different variables, so one
  root's file never serves another.
- `<private-dir>` is a directory outside every Git working tree, created under `umask 077`; use a
  new one for each plan. It holds that plan, its JSON and their logs, and any recovery copy of
  state. No rule for when saved plans, plan JSON and logs are deleted has been defined; the saved
  plans of applied changes have been kept privately with their evidence.
- `<plan-file>` is the absolute path of a saved plan in `<private-dir>`, and `<plan-json>` its
  `terraform show -json` rendering beside it.
- `<state-bucket>` is the state bucket name from `backend.hcl`. `<lock-id>` is the lock ID
  Terraform prints in a lock error. `<n>` is a resource count in Terraform's summary line.
- Commands run from `terraform/<root>` in the working tree the change was reviewed in, unless a
  step says otherwise.
- **Validation** labels are defined in the [runbook index](README.md#validation-labels).
  **Published form** says whether the command form shown, placeholders aside, appears as
  executed in retained private evidence. *Retained evidence* is the private record of an
  execution; it is described here generically and never published
  ([Public and private evidence](evidence-handling.md#public-and-private-evidence)).

## Procedures

### Build the state backend and migrate into it

**Validation:** EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-08) · **Published command form:** not executed as written

**What this does.** Creates the S3 bucket that holds every root's Terraform state, then moves the
bootstrap root's own state into that bucket. It runs once per project, before any other root. It starts on local state because the bucket does not exist yet, so the first run
cannot use the backend that needs it
([why](../../terraform/bootstrap/README.md#why-the-backend-block-arrived-second)).

The procedure is the bootstrap README's
[Stage 1](../../terraform/bootstrap/README.md#stage-1-create-the-bucket) and
[Stage 2](../../terraform/bootstrap/README.md#stage-2-migrate-state-into-the-backend), and it is not
repeated here. This page adds the checks after it.

**Before you start.**

- [ ] The project account and operator identity ([operator-access.md](operator-access.md)).
- [ ] A budget with its alerts in place before the first billable resource
  ([Read back the budget and its alert states](cost-and-residue.md#read-back-the-budget-and-its-alert-states)).
- [ ] The bootstrap root's private inputs ([Input](../../terraform/bootstrap/README.md#input)).

**Safety and authority.** Mutating, billable, owner-authorized. The Stage 1 apply creates the
project's first billable resource and needs explicit owner approval; the migration needs a
separate approval.

**Steps.**

1. With approval for the Stage 1 apply, create the bucket on local state, following
   [Stage 1](../../terraform/bootstrap/README.md#stage-1-create-the-bucket).

   > **Warning:** From a clone, Stage 1 moves `backend.tf` aside. That fresh-clone variant has
   > never run ([Not yet exercised](#not-yet-exercised)). With `backend.tf` moved aside,
   > [Initialize a root against the state backend](#initialize-a-root-against-the-state-backend)
   > does not apply, and step 2 of
   > [Bind the saved plan to its hash and to state](#bind-the-saved-plan-to-its-hash-and-to-state)
   > as written reports `backend.tf` missing from the plan. Review and binding of a Stage 1 plan on
   > local state have never run, and this runbook has no published form for them. So on a fresh
   > clone, stop before the Stage 1 apply: it waits for a reviewed decision under explicit approval
   > ([When something fails](README.md#when-something-fails)).

2. With separate approval, migrate the state into the bucket, following
   [Stage 2](../../terraform/bootstrap/README.md#stage-2-migrate-state-into-the-backend).

   > **Warning:** Never pass `-force-copy`; the README says why. Read the migration prompt: if it
   > names a backend or key you did not expect, stop.

3. Initialize the root
   ([Initialize a root against the state backend](#initialize-a-root-against-the-state-backend))
   and run [Inspect state without writing it](#inspect-state-without-writing-it).
4. Run [Confirm convergence](#confirm-convergence).

**Expected result.** Step 3 lists exactly the five resources in the README's
[What it creates](../../terraform/bootstrap/README.md#what-it-creates). Step 4 returns 0.

**PASS when.**

- [ ] State lists exactly those five resources.
- [ ] Confirm convergence returns 0.

**STOP if.**

- The migration prompt names a backend or key you did not expect.
- The Stage 1 apply or the migration fails or is interrupted.
- On a fresh clone, before the Stage 1 apply: review and binding of its plan on local state have
  no published form (step 1).

**If it fails.** No procedure in this runbook recovers a failed first build or migration. The
bootstrap README's [Recovery](../../terraform/bootstrap/README.md#recovery) is an outline that
names no restore mechanism and no commands. Work stays stopped until a reviewed decision is taken
under explicit approval. Until then:

- Do not run the Stage 1 apply or the migration again, and never pass `-force-copy`.
- Leave the local state and the private backup taken in Stage 2 where they are
  ([Recovery copy of state](#handle-a-held-state-lock)); their removal awaits an owner decision.
- [Stop after a failed or interrupted apply](#stop-after-a-failed-or-interrupted-apply) is written
  for the S3 backend. Before the migration, state is local and its step 5 lock listing may have no
  bucket to read; no form of that procedure adapted to local state is published.

**Evidence to keep.** Nothing specific to this procedure; the campaign's evidence set applies
([Capture a campaign evidence set](evidence-handling.md#capture-a-campaign-evidence-set)). The
2026-08-08 run retained no apply, read-back or migration output.

**Next step.** Build the other roots through the [Normal path](#normal-path), in the order of the
[runbook index](README.md#task-list).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-08) |
| Published form | not executed as written (the README gives step-level instructions, not commands; the 2026-08-08 run began before `backend.tf` existed, so the fresh-clone variant that moves `backend.tf` aside has never run) |
| Evidence basis | [Bootstrap README Status](../../terraform/bootstrap/README.md#status); retained private evidence of a 2026-09-10 read-only listing of the state bucket that shows the bootstrap state object at its key. No apply, read-back or migration output was retained. |
| Authority | Explicit owner approval for the stage 1 apply, the project's first billable resource, and separate approval for the migration |
| Cost | The bucket bills for its stored state objects; no separate figure has been measured. Native locking needs no DynamoDB table; its S3 requests have not been measured separately. |

**Known limitations.**

- Stage 1 step 4 lists the tags and the TLS-only policy among the checks. The policy text was
  read back; no request without TLS has been sent to test the denial, and the tags were not
  read back through the tagging API.
- For Stage 1 the 2026-08-08 record shows an init on the local backend, a plan, a separately
  approved apply and a clean plan after it. It does not show a saved plan, a plan hash or a
  binding check; the saved-plan procedures below were written later. With `backend.tf` moved
  aside, [Initialize a root against the state backend](#initialize-a-root-against-the-state-backend)
  does not apply, and step 2 of
  [Bind the saved plan to its hash and to state](#bind-the-saved-plan-to-its-hash-and-to-state)
  as written reports `backend.tf` missing from the plan. Review and binding of a Stage 1 plan on
  local state have never run.
- Stage 2 step 10 has not been carried out as a recorded step. The residual local state files
  from the migration remain in the root's directory of the working copy the migration ran in,
  protected only by file mode and `.gitignore`, and their removal awaits a separate owner
  decision.
- The bootstrap root has not been initialized against its own backend since the migration.
- Locking is configured, not proven, and least-privilege access to the backend is not
  demonstrated ([Locking](../../terraform/bootstrap/README.md#locking-as-it-currently-stands),
  [Access boundary](../../terraform/bootstrap/README.md#access-boundary-not-yet-demonstrated)).

### Run the static checks

**Validation:** OFFLINE-VALIDATED (2026-09-21 to 2026-09-23) · **Published command form:** not executed as written

**What this does.** Catches formatting, syntax, lint and security-configuration errors before any
credential is used. It runs on the commit under review, with no credentials and no backend.

Step 3 is the security check ADR-0003 requires. It scans the changed root and the same root on
`main`, and compares their finding classes, by check ID and severity. The change is judged on the
classes it adds; findings already on `main` are carried, not re-decided.

**Before you start.**

- [ ] A clean Git working tree at the commit under review, holding no filled `terraform.tfvars` or
  `backend.hcl`. Step 2's `git status` needs a Git working tree.
- [ ] `<commit>`, `<main-commit>` and a new `<scan-dir>`
  ([Placeholders and conventions](#before-you-start)).
- [ ] Terraform, TFLint, Trivy, `git` and `jq` ([Before you start](#before-you-start)).

**Safety and authority.** Local-only and read-only. No credentials, no backend, no approval.

**Steps.**

1. From the repository's `terraform/` directory, check formatting:

   ```
   terraform fmt -check -recursive
   ```

   > **Warning:** Never add `-diff` to `terraform fmt` in a directory that holds a filled
   > `terraform.tfvars`: `fmt` also formats `.tfvars` files, and `-diff` prints their contents.

2. In each changed root, install providers without a backend, confirm the lock file is unchanged,
   validate and lint:

   ```
   terraform init -backend=false -input=false
   git status --porcelain -- .terraform.lock.hcl
   terraform validate
   tflint
   ```

3. From the repository root, scan each changed root and compare its finding classes with the same
   root on `main`:

   ```
   mkdir -p <scan-dir>/main <scan-dir>/change
   git archive <main-commit> terraform/<root> | tar -x -C <scan-dir>/main
   git archive <commit> terraform/<root> | tar -x -C <scan-dir>/change
   for side in main change; do
     trivy config --quiet --skip-check-update --skip-version-check --format json \
       --output <scan-dir>/$side.json <scan-dir>/$side/terraform/<root>
   done
   classes='.Results[]?.Misconfigurations[]? | select(.Status == "FAIL") | "\(.ID) \(.Severity)"'
   diff <(jq -r "$classes" <scan-dir>/main.json | LC_ALL=C sort -u) \
        <(jq -r "$classes" <scan-dir>/change.json | LC_ALL=C sort -u)
   ```

   For a root that is not yet on `main`, skip the `main` side: every class the scan reports is
   new.

**Expected result.** `fmt` prints nothing and exits 0; `git status` prints nothing; `validate`
prints `Success! The configuration is valid.`; `tflint` prints nothing and exits 0 with the
root's `.tflint.hcl`. Each `trivy config` exits 0, and `diff` prints no line beginning `>`: the
change adds no finding class, by check ID and severity, that the root on `main` does not already
have. A clean `diff` means no new class, not no finding. A line beginning `<`, with `diff`'s own
markers such as `3d2` or `---`, is a class on `main` that the change removes. The change is judged
on the classes it adds, so such a line is not a stop.

**PASS when.**

- [ ] `fmt`, `validate`, `tflint` and every `trivy config` exit 0.
- [ ] `git status` prints nothing.
- [ ] `diff` prints no line beginning `>`.

**STOP if.**

- Any non-zero exit, except exit 1 from `diff`: `diff` exits 1 whenever it prints a difference,
  and its lines are judged by the rules here.
- `git status` prints a line: `init` changed the lock file, and a plan made from that tree would
  fail the binding check.
- `diff` prints a line beginning `>`: a new finding class, which goes no further without a recorded
  acceptance decision.

**If it fails.** The change goes no further until the check passes. A new finding class needs a
recorded acceptance decision; no other route is defined here. A lock-file change on a platform the
committed lock files do not cover is [not yet exercised](#not-yet-exercised).

**Evidence to keep.** Nothing specific to this procedure; the campaign's evidence set applies
([Capture a campaign evidence set](evidence-handling.md#capture-a-campaign-evidence-set)).

**Next step.**
[Initialize a root against the state backend](#initialize-a-root-against-the-state-backend).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | OFFLINE-VALIDATED (2026-09-21 to 2026-09-23) |
| Published form | not executed as written (`terraform fmt -check -recursive` and `terraform validate` ran in this form on 2026-09-23; the backend-less init ran with `-plugin-dir` pointing at an already installed provider rather than installing from the registry; TFLint ran with explicit `--chdir` and `--config` arguments; `trivy config` ran in this form on `git archive` extractions on 2026-09-22, and the class comparison was made by a private script from which the `jq` form is derived; the lock-file check is derived from the 2026-09-23 record that init left the lock file unchanged) |
| Evidence basis | Retained private evidence of the static checks on the foundation and dev-datastore roots on 2026-09-21, 2026-09-22 and 2026-09-23, and of the configuration scan of the foundation, dev and dev-datastore roots on 2026-09-21 and 2026-09-22; the bootstrap, foundation and dev READMEs record that formatting, `terraform validate` and TFLint passed |
| Authority | None; no credentials and no backend |
| Cost | None |

**Known limitations.** The `-diff` warning is at step 1.

- The 2026-09-23 run used an extraction of tracked files only.
- `init -backend=false` installs providers only. It cannot carry a plan or an apply
  ([why](../../terraform/bootstrap/README.md#why-the-backend-block-arrived-second)).
- TFLint runs the bundled Terraform ruleset only; it is not a security scan. Step 3 is.
- The scan reports findings already present on `main` for the roots scanned. The comparison
  carries them rather than re-deciding them. The findings recorded on 2026-09-21 for the
  foundation and dev-datastore roots were accepted by recorded decision, and not every
  rationale is published. A clean `diff` means no new class, not no finding.
- The scan ran on the foundation, dev and dev-datastore roots on 2026-09-21 and 2026-09-22,
  with Trivy 0.74.0. The 2026-09-23 checks did not include it. The bootstrap root has never
  been scanned; its security check on 2026-08-08 is recorded, without retained evidence, as a
  source review.
- The lock files and the platforms they cover are described under
  [Initialize a root against the state backend](#initialize-a-root-against-the-state-backend).

### Initialize a root against the state backend

**Validation:** AWS-VALIDATED (2026-09-23, 2026-09-24) for init of the foundation and dev-datastore roots with the provider from a local plugin directory; EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-09) for `git check-ignore` on the dev root; DESIGNED-NOT-EXECUTED (never) for `git check-ignore` on the other roots and for the registry provider install · **Published command form:** not executed as written

**What this does.** Prepares a clean working tree at the reviewed commit, puts the root's private
inputs in place, and runs `terraform init`. Init connects the working tree to the root's state object
in the S3 backend and installs the provider. It reads the backend and writes nothing to it.

**Before you start.**

- [ ] The identity and account checks in [operator-access.md](operator-access.md) passed for
  `<profile>`.
- [ ] The reviewed commit, `<commit>`.
- [ ] A filled `backend.hcl` naming the state bucket the bootstrap root created, and a filled
  `terraform.tfvars` for the root, both in that root's `<inputs-dir>`. For
  `terraform/foundation`, `backend.hcl` names the state bucket, never the evidence bucket.
- [ ] A new `<work-dir>` outside every existing Git working tree.

**Safety and authority.** Read-only against AWS; no approval. It writes local files that hold the
root's private inputs, and no rule for removing that working tree has been defined (see
Engineering notes).

> **Warning:** `init`, `state list`, `state pull` and `force-unlock` touch only the backend, and
> this backend configuration carries no account check of its own. The identity check in
> [operator-access.md](operator-access.md) is their only account guard.

**Steps.**

1. From the repository, create a clean working tree at the reviewed commit:

   ```
   git worktree add --detach <work-dir> <commit>
   ```

2. Copy the inputs in with owner-only permissions and confirm that Git ignores them:

   ```
   cd <work-dir>/terraform/<root>
   install -m 0600 <inputs-dir>/backend.hcl <inputs-dir>/terraform.tfvars .
   git check-ignore -v backend.hcl terraform.tfvars
   ```

   > **Warning:** If `git check-ignore` does not list a path, stop: that file would be tracked.

3. Initialize, then confirm the lock file is unchanged:

   ```
   AWS_PROFILE=<profile> terraform init -input=false -no-color -backend-config=backend.hcl
   git status --porcelain -- .terraform.lock.hcl
   ```

**Expected result.** `git check-ignore` lists both paths. `init` prints
`Successfully configured the backend "s3"!` and `Terraform has been successfully initialized!`,
and installs the provider version recorded in `.terraform.lock.hcl` (hashicorp/aws 6.58.0 at
the time of writing). `git status` prints nothing. Afterwards,
[Inspect state without writing it](#inspect-state-without-writing-it) lists the addresses expected
at that point, as its **Expected result** says. A root that has never been applied lists nothing.

**PASS when.**

- [ ] `git check-ignore` lists `backend.hcl` and `terraform.tfvars`.
- [ ] `init` reports the backend configured and Terraform initialized.
- [ ] `git status` prints nothing.

**STOP if.**

- `git check-ignore` does not list a path: that file would be tracked.
- `init` reports that the backend configuration changed or that state must be migrated: find out
  why before anything else.
- `init` fails, for example because `backend.hcl` is missing.
- `git status` prints a line: `init` changed the lock file, and a plan made here would fail the
  binding check.

**If it fails.** No recovery procedure exists here. Recovering from an init against the wrong
bucket or key, and the reviewed lock-file change another platform would need, are
[not yet exercised](#not-yet-exercised). An account check that does not pass goes to
[Recover from a wrong account](operator-access.md#recover-from-a-wrong-account).

**Evidence to keep.** Nothing specific to this procedure; the campaign's evidence set applies
([Capture a campaign evidence set](evidence-handling.md#capture-a-campaign-evidence-set)).

**Next step.** [Inspect state without writing it](#inspect-state-without-writing-it).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-23, 2026-09-24) for initializing the foundation and dev-datastore roots with the provider installed from a local plugin directory; EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-09) for the `git check-ignore` step on the dev root; DESIGNED-NOT-EXECUTED (never) for the `git check-ignore` step on the other roots and for the registry provider install |
| Published form | not executed as written (the executed inits added `-plugin-dir` pointing at a previously installed provider, so a registry install has no retained evidence; the input copy was recorded as a description, not a command; the `git check-ignore` step was not part of them; the lock-file check is derived from the 2026-09-23 static check that recorded the lock file unchanged by init) |
| Evidence basis | Retained private evidence of the 2026-09-23 initialization of `terraform/foundation` in a fresh detached working tree, with its output, and of the 2026-09-24 initialization of `terraform/dev-datastore`, recorded as the first step of a retained plan run |
| Authority | None; it reads the backend only |
| Cost | None |

**Teardown / decommission.** No rule for removing this working tree, which holds the filled
inputs and `.terraform/` with the backend configuration, has been defined or exercised here;
[dev-datastore.md](dev-datastore.md) removes the working tree of its first stage.

**Known limitations.**

- The provider's `allowed_account_ids` check runs only when the provider is configured.
  `init`, `state list`, `state pull` and `force-unlock` touch only the backend, and this
  backend configuration carries no account check of its own, so the identity check in
  [operator-access.md](operator-access.md) is their only account guard.
- The executed inits installed the provider from a local plugin directory, which Terraform
  reports as `unauthenticated`: the lock-file hash is checked and the registry signature is
  not. The registry install this form performs has no retained evidence here.
- The `git check-ignore` step was not part of the 2026-09-23 or 2026-09-24 inits. It is
  recorded once, for the dev root on 2026-08-09 (EXECUTED — RECORDED ONLY; RETAINED EXECUTION
  EVIDENCE NOT AVAILABLE), and never for the other roots.
- The four committed lock files are identical and carry `h1:` hashes for two platforms, which
  the project record lists as darwin_arm64 and linux_amd64 without establishing which hash is
  which. On another platform, `init` may add that platform's hashes, which the `git status`
  check stops on; that case has not been exercised.
- The bootstrap root has not been initialized against its own backend since the 2026-08-08
  migration.
- `git worktree add` creates a Git working tree. Saved plans and plan JSON go to
  `<private-dir>`, never into it.

### Inspect state without writing it

**Validation:** AWS-VALIDATED (2026-09-22) · **Published command form:** not executed as written

**What this does.** Shows what a root manages, and records three values that later checks
compare: the state's *serial*, which advances each time state is written; its *lineage*, the
identifier the state keeps from its creation; and a digest of its address set. The binding check
and the checks after apply use them. It is read-only and does not take the state lock.

**Before you start.**

- [ ] The root is initialized
  ([Initialize a root against the state backend](#initialize-a-root-against-the-state-backend)).
- [ ] The identity and account checks in [operator-access.md](operator-access.md) passed in the
  current shell.

**Safety and authority.** Read-only; no approval. On `terraform/dev-datastore`, `state list` and
`state pull` do not read the master secret.

> **Warning:** Never redirect `state pull` to a file: state holds full resource attributes. The
> one exception is a recovery copy, described under
> [Handle a held state lock](#handle-a-held-state-lock).

**Steps.**

1. List the managed addresses:

   ```
   AWS_PROFILE=<profile> terraform state list
   ```

2. Read the serial and lineage:

   ```
   AWS_PROFILE=<profile> terraform state pull | jq '{serial, lineage}'
   ```

3. Hash the sorted address list:

   ```
   AWS_PROFILE=<profile> terraform state list | LC_ALL=C sort | shasum -a 256
   ```

**Expected result.** `state list` prints instance addresses, keys included, for example
`aws_ecr_repository.workload["cart"]`. It also prints the root's data sources as `data.`
addresses; only `terraform/dev-datastore` has them: `data.aws_vpc.dev`,
`data.aws_subnet.private["a"]` and `data.aws_subnet.private["b"]`
([`network.tf`](../../terraform/dev-datastore/network.tf)). The digest covers those instance
addresses, so adding or removing a `for_each` instance changes it.

The addresses to expect are those of your own state at this point, not everything the
configuration declares. Use the first of these that applies:

1. A root never applied: none.
2. The set the procedure you are following publishes for this point: the five bootstrap
   resources ([What it creates](../../terraform/bootstrap/README.md#what-it-creates)); the 21
   retained Dev addresses between runtime windows
   ([Confirm the retained and runtime split](dev-network.md#confirm-the-retained-and-runtime-split));
   for the datastore, the six Stage 1 addresses before Stage 2, and those six with
   `aws_db_instance.datastore` and `aws_ssm_parameter.endpoint` after it
   ([Stage 2: plan the instance and its endpoint parameter](dev-datastore.md#stage-2-plan-the-instance-and-its-endpoint-parameter)).
   These sets name no data source.
3. The address list printed by step 2 of
   [Apply the reviewed saved plan](#apply-the-reviewed-saved-plan) after this root's last apply,
   kept in that campaign's evidence.
4. The resources the root's README says currently exist, in its Status section (for
   `terraform/dev`, Lifecycle and current state). The READMEs describe the reference deployment,
   in prose, not as addresses; no address list is published for `terraform/foundation`.

If none of these gives you a concrete address set, for example on `terraform/foundation` when no
earlier campaign kept the step 2 list of
[Apply the reviewed saved plan](#apply-the-reviewed-saved-plan), the listed addresses cannot be
shown equal to an expected set, and PASS cannot be reached.

**PASS when.**

- [ ] The listed addresses equal the expected set, plus the root's data sources.
- [ ] The serial, lineage and address digest are recorded.

**STOP if.**

- The listed addresses differ from the expected set, or none of the rules above gives you one.

**If it fails.** No failure procedure exists here, and none handles a listed address set that
differs from the expected set, or a root with no expected set: work stays stopped until a
reviewed decision is taken under explicit approval
([When something fails](README.md#when-something-fails)). When
[Stop after a failed or interrupted apply](#stop-after-a-failed-or-interrupted-apply) runs this
procedure, these PASS and STOP criteria do not apply; a difference there is what that procedure
classifies. A command that fails on an expired or missing
token goes to [Recover from session expiry](operator-access.md#recover-from-session-expiry).

**Evidence to keep.** The serial, lineage and address digest, privately, for the binding and
post-apply checks.

**Next step.** [Keep Terraform debug logging off](#keep-terraform-debug-logging-off), then
[Plan to a saved file](#plan-to-a-saved-file).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22) |
| Published form | not executed as written (`terraform state list` ran in this form with credentials supplied by a private wrapper rather than `AWS_PROFILE`; serial, lineage and address sets were read by piping `terraform state pull` into a private parser, from which the `jq` and `shasum` forms are derived) |
| Evidence basis | Retained private evidence of 2026-09-22: state serial, lineage and address set recorded before and after the Dev and foundation reconciliations and the foundation apply |
| Authority | None; read-only, and it does not take the lock |
| Cost | None |

**Known limitations.** A state list is an inventory of managed state, not a census of AWS. It says
nothing about resources Terraform does not manage; the orphan census is in
[cost-and-residue.md](cost-and-residue.md). On `terraform/dev-datastore`, `state list` and
`state pull` do not read the master secret; every plan does.

### Keep Terraform debug logging off

**Validation:** AWS-VALIDATED (2026-09-22, 2026-09-24) for the check; OFFLINE-VALIDATED (2026-09-24) for the refusal · **Published command form:** not executed as written

**What this does.** Keeps secret values out of debug logs and protocol dumps. On
`terraform/dev-datastore` the master value passes through the provider on every plan and apply.
The check applies to every root so it does not depend on remembering which root reads a secret.

**Before you start.**

- [ ] The shell that will run the plan, apply or refresh-only plan.

**Safety and authority.** Local-only and read-only; no approval.

**Steps.**

1. Before every plan, apply or refresh-only plan, in the shell that will run it:

   ```
   env | grep '^TF_'
   ```

   > **Warning:** This prints each matching variable's value as well as its name. Never capture
   > its output into evidence.

**Expected result.** No output.

**PASS when.**

- [ ] The command prints nothing.

**STOP if.**

- Any listed variable.

**If it fails.** Unset it, or open a fresh shell, and check again. The variables that matter most
are listed in the [dev-datastore README](../../terraform/dev-datastore/README.md#debug-logging).

**Evidence to keep.** Nothing specific to this procedure; the campaign's evidence set applies
([Capture a campaign evidence set](evidence-handling.md#capture-a-campaign-evidence-set)).

**Next step.** The plan or apply this check guards, first
[Plan to a saved file](#plan-to-a-saved-file).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22, 2026-09-24) for the check finding no logging variable before live plans and applies; OFFLINE-VALIDATED (2026-09-24) for the refusal when a logging variable is present |
| Published form | not executed as written (the executed checks inspected the environment inside reviewed wrappers; the `env` form is derived from them) |
| Evidence basis | Retained private evidence: the pre-apply checks of the 2026-09-22 foundation applies found no `TF_LOG` variable, and every Terraform run of the 2026-09-24 datastore plan and apply recorded the names of the variables it received, none of them a logging variable; [dev-datastore README, Debug logging](../../terraform/dev-datastore/README.md#debug-logging) |
| Authority | None |
| Cost | None |

**Known limitations.** The refusal path, a logging variable present at the start of a run, has
been exercised offline only (2026-09-24).

### Plan to a saved file

**Validation:** AWS-VALIDATED (2026-09-21 to 2026-09-24) · **Published command form:** executed as written

**What this does.** Produces the *saved plan*: a file, written with `-out`, that records the
changes Terraform will make. It is the one artifact that is reviewed, bound and applied. A plan
writes no state.

**Before you start.**

- [ ] The static checks pass ([Run the static checks](#run-the-static-checks)).
- [ ] The root is initialized at the reviewed commit
  ([Initialize a root against the state backend](#initialize-a-root-against-the-state-backend)).
- [ ] Debug logging is off ([Keep Terraform debug logging off](#keep-terraform-debug-logging-off)).
- [ ] The caller is confirmed: the identity and account checks in
  [operator-access.md](operator-access.md) passed.
- [ ] A new `<private-dir>` for this plan; `<plan-file>` is inside it.
- [ ] On `terraform/dev-datastore`: an explicit owner grant, and, when the configuration includes
  `database.tf`, a master container that holds a value
  ([README](../../terraform/dev-datastore/README.md#what-it-creates)). Stage 1 is planned without
  `database.tf`
  ([dev-datastore.md](dev-datastore.md#stage-1-create-the-network-boundary-and-the-empty-secret-containers)).

**Safety and authority.** Read-only for state; no approval, except on `terraform/dev-datastore`,
where every plan reads the master secret's value (secret-reading, owner-authorized). `-lock=false`
is safe only under the conditions in
[Plan without taking the state lock](#plan-without-taking-the-state-lock).

> **Warning:** The saved plan carries every input value and the prior state's attributes in clear
> text. Write it only to `<private-dir>`, never inside a Git working tree.

**Steps.**

1. Plan to the saved file, and print the exit code:

   ```
   AWS_PROFILE=<profile> terraform plan -lock=false -input=false -no-color -detailed-exitcode -out=<plan-file>
   echo $?
   ```

**Expected result.** Exit 2 when the plan has changes, as observed on 2026-09-23 and
2026-09-24. Exit 0 means there is nothing to apply; exit 1 is an error.

**PASS when.**

- [ ] Exit 2 for an expected change, with the saved plan at `<plan-file>`.

**STOP if.**

- Exit 1.
- Exit 0 when a change was expected.

**If it fails.** No failure procedure exists here. On `terraform/dev-datastore` a plan fails if
the master container holds no value; placing it is
[Place the master value](dev-datastore.md#place-the-master-value).

**Evidence to keep.** The saved plan, in `<private-dir>` only. Its hash is recorded at review.

**Next step.** [Review the saved plan](#review-the-saved-plan).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-21 to 2026-09-24) |
| Published form | executed as written (2026-09-23) |
| Evidence basis | Retained private evidence of the saved plans behind the 2026-09-22 registry and datastore-network applies, the 2026-09-23 zone and certificate applies and the 2026-09-24 datastore-instance apply |
| Authority | None for the plan itself; it writes no state. On `terraform/dev-datastore`, an explicit owner grant, because every plan there reads the master secret's value. |
| Cost | None |

**Known limitations.**

- On `terraform/dev-datastore` a plan fails if the master container holds no value
  ([README](../../terraform/dev-datastore/README.md#what-it-creates)).
- The 2026-09-23 plan, run in this form, wrote its saved plan inside the working tree, where
  `.gitignore` excludes `*.tfplan`; the plan was then kept in private storage and applied from
  there, and where its JSON was written is not recorded. The 2026-09-24 plan was written
  directly to a private directory outside the tree, by a reviewed wrapper that is not
  published.

### Plan without taking the state lock

**Validation:** AWS-VALIDATED (2026-09-22, 2026-09-23) · **Published command form:** not executed as written

**What this does.** States when a plan may skip the state lock, and what makes that safe. The
*state lock* is the object `<root>/terraform.tfstate.tflock` beside the state object, present
while an operation holds the lock. A plan never writes state, with or without the lock; skipping
the lock only means the plan neither waits for nor refuses a writer that holds it.
`terraform apply` runs without `-lock=false`, so it requests the lock.

For a saved plan made with `-lock=false`, the safety basis is
[Bind the saved plan to its hash and to state](#bind-the-saved-plan-to-its-hash-and-to-state),
not the flag: it proves the backend still holds the state the plan was made from, and a write
that lands between plan and apply changes the serial, so the plan is discarded.

**Before you start.**

- [ ] Know whether any other writer can be active on the root.

**Safety and authority.** Read-only; no approval. The flag is for plans only.

**Steps.** This procedure has no commands of its own. It governs `-lock=false` in
[Plan to a saved file](#plan-to-a-saved-file), [Confirm convergence](#confirm-convergence),
[Detect state drift](#detect-state-drift) and
[Reconcile explained state-only drift](#reconcile-explained-state-only-drift).

1. A saved plan made with `-lock=false` is applied only after its binding check passes
   immediately before apply.
2. A plan that is only read, a convergence or drift check, has no later check to catch a
   concurrent write. Use `-lock=false` for it only when no other writer can be active on the
   root; otherwise leave the flag off, so the plan waits for the lock or fails.
3. Never pass the flag to a write.

   > **Warning:** Never pass `-lock=false` to a command that writes state: `apply`, including a
   > refresh-only apply, `import`, `state mv` or `state rm`.

**Expected result.** Every saved plan made with `-lock=false` passed its binding check
immediately before apply, and every read-only plan that skipped the lock ran while no other writer
could be active.

**PASS when.**

- [ ] The binding check passed immediately before applying a plan made with `-lock=false`.
- [ ] No read-only plan skipped the lock while another writer could be active.
- [ ] No command that writes state carried `-lock=false`.

**STOP if.**

- A saved plan made with `-lock=false` whose binding check has not passed immediately before
  apply: do not apply it.
- A command that writes state carries `-lock=false`.

**If it fails.** A binding mismatch: discard the plan, plan again and review again
([Bind the saved plan to its hash and to state](#bind-the-saved-plan-to-its-hash-and-to-state)).
A lock error on a plan run without the flag:
[Handle a held state lock](#handle-a-held-state-lock).

**Evidence to keep.** The binding-check values, as
[Bind the saved plan to its hash and to state](#bind-the-saved-plan-to-its-hash-and-to-state)
records them.

**Next step.** Return to the procedure that runs the plan.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22, 2026-09-23) |
| Published form | not executed as written (the `-lock=false` flag appears in the 2026-09-23 plan and convergence commands; the 2026-09-23 certificate and 2026-09-24 datastore applies of `-lock=false` plans skipped the serial-and-lineage binding these rules require, and the 2026-09-23 zone apply compared the serial only) |
| Evidence basis | Retained private evidence of plans made with `-lock=false` from 2026-09-21 to 2026-09-24, and of the pre-apply checks that bound the 2026-09-22 applies to the state serial and lineage and the 2026-09-23 zone apply to the serial |
| Authority | None |
| Cost | None |

**Known limitations.**

- Terraform also refuses to apply a saved plan whose recorded state no longer matches the
  backend. That refusal has not been observed in this project, so it is not the control relied
  on.
- Lock acquisition has not been observed in retained evidence
  ([Handle a held state lock](#handle-a-held-state-lock)).
- The convention is not uniform: the 2026-09-22 Dev refresh-only plan ran with normal locking
  (`-lock=false` not used).
- The 2026-09-23 zone apply compared the serial but not the lineage. The 2026-09-23 certificate
  apply and the 2026-09-24 datastore-instance apply re-checked the plan hash but not the serial
  and lineage.

### Review the saved plan

**Validation:** AWS-VALIDATED (2026-09-22 to 2026-09-24) · **Published command form:** not executed as written

**What this does.** Decides that the plan does exactly what the change intends and nothing else.
Under ADR-0003 this review is the approval point: the owner approves the plan on the basis of it,
in writing, identified by its sha256, after steps 1 and 2 of
[Bind the saved plan to its hash and to state](#bind-the-saved-plan-to-its-hash-and-to-state)
([Normal path](#normal-path), step 9). Running the review does not itself approve anything. It
renders the saved plan as JSON, the *plan JSON*, in `<private-dir>`, and lists every planned
action, every drifted attribute and every output change. *Drift* is a difference Terraform found
between state and AWS while planning.

**Before you start.**

- [ ] A saved plan at `<plan-file>` ([Plan to a saved file](#plan-to-a-saved-file)).
- [ ] The reviewed list: the addresses and actions the change intends, one line each in the form
  step 3 prints: the actions, a tab, then the address. Where the root's runbook gives a plan's
  contents for the procedure you are following, that is the list; otherwise write it from the
  change. Write it before the plan is made, and record it as the **Expected** field of the
  campaign record, which is fixed before the run
  ([Capture a campaign evidence set](evidence-handling.md#capture-a-campaign-evidence-set)).
- [ ] The Terraform version the change was validated with.

**Safety and authority.** Local-only and read-only; running it needs no approval.

> **Warning:** Never publish the plan, its JSON or its text: they carry account identifiers,
> bucket names and every input value. Write the JSON only into `<private-dir>`; `.gitignore`
> does not exclude it.

**Steps.**

1. Read the plan, then render it as JSON into `<private-dir>`:

   ```
   terraform show -no-color <plan-file>
   terraform show -json <plan-file> > <plan-json>
   ```

2. Completeness and version:

   ```
   jq '{terraform_version, applyable, complete, errored}' <plan-json>
   ```

3. Every planned action other than `no-op`:

   ```
   jq -r '.resource_changes[]? | select(.change.actions != ["no-op"]) | "\(.change.actions | join(","))\t\(.address)"' <plan-json>
   ```

4. Drift, as address and changed attribute:

   ```
   jq -r '.resource_drift[]? | .address as $a | (.change.before // {}) as $b | (.change.after // {}) as $n | ($b + $n | keys[]) as $k | select($b[$k] != $n[$k]) | "\($a)\t\($k)"' <plan-json>
   ```

5. Output changes:

   ```
   jq -r '.output_changes // {} | to_entries[] | select(.value.actions != ["no-op"]) | "\(.value.actions | join(","))\t\(.key)"' <plan-json>
   ```

**Expected result.**

- `applyable` and `complete` are `true`, `errored` is `false`, and `terraform_version` is the
  version the change was validated with.
- The step 3 list equals the reviewed list exactly, address and action.
- Every step 4 line names an address and attribute with a written cause, and that address has
  a `no-op` planned action.
- Step 5 shows only the expected outputs.

**PASS when.**

- [ ] Step 2 shows a complete, applyable, error-free plan from the validated version.
- [ ] Step 3 equals the reviewed list exactly.
- [ ] Every step 4 line has a written cause, on an address whose planned action is `no-op`.
- [ ] Step 5 shows only the expected outputs.

**STOP if.**

- Any criterion fails.
- A `delete` or `delete,create` the review does not name.
- For a targeted plan, a destroy count that differs from the intended targets.

**If it fails.** Do not approve with an exception: correct the configuration or inputs,
[plan again](#plan-to-a-saved-file) and review again.

**Evidence to keep.** The step 3 to 5 lists, the Terraform version and the plan's sha256,
privately ([evidence-handling.md](evidence-handling.md)).

**Next step.**
[Bind the saved plan to its hash and to state](#bind-the-saved-plan-to-its-hash-and-to-state).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22 to 2026-09-24) |
| Published form | not executed as written (`terraform show -no-color` and `terraform show -json` ran in this form on 2026-09-23; the `jq` filters are derived from the reviewed checkers that evaluated each applied plan, whose code is not published) |
| Evidence basis | Retained private evidence of exact-shape checks on the saved plans applied on 2026-09-22, 2026-09-23 and 2026-09-24, each checker qualified offline with positive and negative controls before use |
| Authority | None |
| Cost | None |

**Known limitations.** A value unknown until apply cannot be reviewed from the plan. On
2026-09-17 and 2026-09-22 the CI push policy document was unknown at plan time and was
confirmed by read-back after apply.

### Bind the saved plan to its hash and to state

**Validation:** AWS-VALIDATED (2026-09-22, 2026-09-23) · **Published command form:** not executed as written

**What this does.** Makes the reviewed plan the only thing that can be applied, and only against
the state it was made from. At review, you record the plan's sha256 and the serial and lineage of
the state it was made from, and confirm that the plan carries the reviewed configuration and lock
file. Immediately before apply, you check the hash and the remote serial and lineage again. A
serial that moved means something wrote state after the plan was made, and the plan is discarded.

**Before you start.**

- [ ] The reviewed saved plan ([Review the saved plan](#review-the-saved-plan)).
- [ ] The repository at hand for step 2, with the reviewed commit `<commit>`.
- [ ] For step 3, the root's initialized working tree, and the identity and account checks in
  [operator-access.md](operator-access.md) passed in the current shell.

**Safety and authority.** Read-only; no approval. Step 3 reads remote state through `jq` only.

**Steps.**

1. At review, record the plan's hash and the state it was made from:

   ```
   shasum -a 256 <plan-file>
   unzip -p <plan-file> tfstate | jq '{serial, lineage}'
   ```

   > **Warning:** Steps 1 and 2 read the saved plan's archive layout as measured on Terraform
   > 1.15.5, which is not a documented interface. Re-check the layout after any Terraform
   > upgrade.

2. From the repository root, confirm the plan carries the reviewed configuration and lock file:

   ```
   for f in $(git ls-tree --name-only <commit> terraform/<root>/ | grep '\.tf$'); do
     unzip -p <plan-file> "tfconfig/m-/${f##*/}" | cmp -s - <(git show "<commit>:$f") && echo "same     $f" || echo "DIFFERS  $f"
   done
   unzip -p <plan-file> .terraform.lock.hcl | cmp -s - <(git show "<commit>:terraform/<root>/.terraform.lock.hcl") && echo "same     lock file" || echo "DIFFERS  lock file"
   diff <(unzip -Z1 <plan-file> | sed -n 's|^tfconfig/m-/||p' | sort) \
        <(git ls-tree --name-only <commit> terraform/<root>/ | grep '\.tf$' | sed 's|.*/||' | sort)
   ```

3. Immediately before apply, in the root's working tree:

   ```
   shasum -a 256 <plan-file>
   AWS_PROFILE=<profile> terraform state pull | jq '{serial, lineage}'
   ```

**Expected result.** Step 2 prints `same` for every file and the lock file, and `diff` prints
nothing. In step 3 the hash equals the one recorded, and the serial and lineage equal the
plan's. For a root's first apply, step 1 shows serial 0 and an empty lineage; the 2026-09-22
check read that root's remote state as serial 0 with no lineage and no resources. The `jq`
rendering of that remote read was not captured, so whether it prints an empty or a null lineage
is not recorded.

**PASS when.**

- [ ] Step 2 prints `same` for every file and for the lock file, and `diff` prints nothing.
- [ ] Step 3's hash equals the recorded hash.
- [ ] Step 3's serial and lineage equal the plan's. On a root's first apply, both steps 1 and 3
  show serial 0, and neither shows a lineage: an empty string or `null` counts as no lineage. A
  step 3 that prints nothing shows no serial 0, so it is a mismatch, not a first-apply match.

**STOP if.**

- Any mismatch.
- A serial that moved: something wrote state after the plan was made.

**If it fails.** Discard the plan, [plan again](#plan-to-a-saved-file) and
[review again](#review-the-saved-plan). If the serial moved, find out what wrote state before
planning again; no procedure here does that. On a root's first apply, a step 3 that prints nothing
is a mismatch that planning again cannot clear, because a plan writes no state. What the published
step 3 prints against a state object never yet written has not been recorded, and no procedure
here resolves that mismatch: work stays stopped until a reviewed decision is taken under explicit
approval ([When something fails](README.md#when-something-fails)).

**Evidence to keep.** The plan's hash and the serial and lineage recorded at review, and the step 3
values, privately. They are the "before" values in the apply's evidence.

**Next step.** Steps 1 and 2 run at review. Then obtain the owner's written approval of this plan,
identified by its sha256. For a billable change, run the budget read-back and the price re-check
in the exported shell next, before step 3, not after it ([Normal path](#normal-path), step 10).
Then run step 3 in the Terraform shell, and if it passes,
[apply the plan](#apply-the-reviewed-saved-plan).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22, 2026-09-23) |
| Published form | not executed as written (derived from pre-apply checks that read the same values in-process on 2026-09-22; the plan archive layout used below was measured on Terraform 1.15.5 and is not a documented interface) |
| Evidence basis | Retained private evidence of the 2026-09-22 foundation apply, refresh-only apply and datastore-network apply, each preceded by checks of the plan hash, its embedded configuration and lock file, and the remote serial and lineage against the plan's prior state (for the datastore network, the root's first apply, against a remote state never yet written); and of the 2026-09-23 zone apply, preceded by a comparison of the remote serial with the plan-time serial (lineage recorded, not compared; no plan-hash re-check retained) |
| Authority | None |
| Cost | None |

**Known limitations.**

- The binding covers Terraform state, not AWS. Applying a saved plan does not refresh, so a
  change made in AWS after planning is not seen, and no maximum plan age is enforced. One zone
  plan was applied about 23 hours after it was made, bound to the serial.
- The 2026-09-23 zone apply compared the serial only, and no plan-hash re-check of it was
  retained. The 2026-09-23 certificate apply and the 2026-09-24 datastore-instance apply
  re-checked the hash, and for the datastore the extracted configuration, but not the serial
  and lineage.
- Terraform writes the prior state's serial and lineage on the archive's `tfstate` member;
  `tfstate-prev` carries serial 0 and no lineage. The first 2026-09-22 check required both
  members to match, failed on `tfstate-prev` because of that check's own defect, and held the
  apply; the plan's `tfstate` member did match. Re-check the layout after any Terraform
  upgrade.

### Apply the reviewed saved plan

**Validation:** AWS-VALIDATED (2026-09-17, 2026-09-22, 2026-09-23, 2026-09-24) · **Published command form:** not executed as written

**What this does.** Applies exactly the reviewed plan, once, and reads state after it. A saved
plan applies without a confirmation prompt; the approval happened at review.

**Before you start.**

- [ ] The plan is reviewed ([Review the saved plan](#review-the-saved-plan)), and the owner
  approved it in writing, identified by its hash.
- [ ] The binding check passes immediately before
  ([Bind the saved plan to its hash and to state](#bind-the-saved-plan-to-its-hash-and-to-state),
  step 3).
- [ ] The session outlives the apply
  ([Check session headroom before long operations](operator-access.md#check-session-headroom-before-long-operations)).
  Where the root's runbook states a minimum session time, as
  [dev-datastore.md](dev-datastore.md#before-you-start) does, that is `<required-minutes>`. This
  runbook states none and publishes no measured apply duration, so otherwise set it as step 1 of
  that procedure describes; no margin rule has been established.
- [ ] Debug logging is off ([Keep Terraform debug logging off](#keep-terraform-debug-logging-off)).
- [ ] For a billable change, the budget read-back and the price re-check pass
  ([Read back the budget and its alert states](cost-and-residue.md#read-back-the-budget-and-its-alert-states),
  [Re-check prices before billable work](cost-and-residue.md#re-check-prices-before-billable-work)).

**Safety and authority.** Mutating, owner-authorized, billable: it costs whatever the plan
creates, which each root's runbook states.

**Steps.**

1. Apply, writing the output to a log in `<private-dir>`, with the time before and after:

   ```
   date -u +%Y-%m-%dT%H:%M:%SZ
   AWS_PROFILE=<profile> terraform apply -input=false -no-color <plan-file> > <private-dir>/apply.log 2>&1
   echo $?
   date -u +%Y-%m-%dT%H:%M:%SZ
   tail -n 5 <private-dir>/apply.log
   ```

   > **Warning:** Run the apply once. If it fails, is interrupted, or loses its terminal or session,
   > never run it again: go to
   > [Stop after a failed or interrupted apply](#stop-after-a-failed-or-interrupted-apply).
   > After the first time stamp the terminal prints nothing until Terraform exits, because the
   > apply's output goes to `apply.log`. That is expected: do not interrupt it. An interrupt is a
   > failed apply.

2. Read the state after the apply:

   ```
   AWS_PROFILE=<profile> terraform state pull | jq '{serial, lineage}'
   AWS_PROFILE=<profile> terraform state list | LC_ALL=C sort
   ```

3. Read back the changed resources through the root's runbook:
   [persistent-foundations.md](persistent-foundations.md),
   [public-dns-and-certificate.md](public-dns-and-certificate.md),
   [dev-network.md](dev-network.md) or [dev-datastore.md](dev-datastore.md).

   Where the root's runbook publishes no read-back for a changed address, record the gap in the
   campaign record's **Not exercised** field. If the procedure you are following says how that
   address is checked instead, continue as it says:
   [Build only the retained baseline](dev-network.md#build-only-the-retained-baseline) covers the
   Dev Parameter Store entry, the two Pod Identity roles and their inline policies only by the
   state listing, and lists their AWS read-back under
   [Not yet exercised](dev-network.md#not-yet-exercised). Otherwise no procedure covers the
   address: stop, and work resumes only on a reviewed decision under explicit approval
   ([When something fails](README.md#when-something-fails)). Step 7 of the
   [Normal path](#normal-path) checks this coverage before approval.

**Expected result.** Exit 0, and the log contains
`Apply complete! Resources: <n> added, <n> changed, <n> destroyed.` with counts equal to the
reviewed list. On `terraform/foundation`, which declares two root outputs, Terraform prints an
`Outputs:` block after that line, so `tail -n 5` shows output values, not the summary: read the
summary line above them in `apply.log`. Those values, the certificate ARN and the zone's name
servers, are private: capture them only through redaction. The serial has advanced, and the
lineage equals the one recorded in the binding check, except on a root's first apply, which
creates the state. The address list includes every reviewed create and every moved-to address,
and none of the reviewed destroys or moved-from addresses.

**PASS when.**

- [ ] Exit 0, with summary counts equal to the reviewed list.
- [ ] The serial advanced, and the lineage equals the recorded one (a root's first apply creates
  it).
- [ ] The address list holds every reviewed create and moved-to address, and no reviewed destroy
  or moved-from address.
- [ ] The changed resources are read back through the root's runbook, or checked as the procedure
  you are following says, with any gap recorded (step 3).

**STOP if.**

- A non-zero exit, an interrupt, a lost terminal, a session that expired during the apply, or a
  summary that differs from the review.
- A changed address that no published read-back covers and that the procedure you are following
  does not check another way (step 3).

**If it fails.** Go to
[Stop after a failed or interrupted apply](#stop-after-a-failed-or-interrupted-apply); on
`terraform/dev-datastore`, with
[Read the datastore after a failed or interrupted apply](dev-datastore.md#read-the-datastore-after-a-failed-or-interrupted-apply).
Never run the apply again. A read-back gap after a successful apply is not a failed apply: step 3
says what to do.

**Evidence to keep.** Privately: the plan hash, `apply.log` with the exit code, start and end UTC,
the serial and lineage before (from the binding check) and after, and the step 2 address list,
which the next [Inspect state without writing it](#inspect-state-without-writing-it) of this root
can compare against.

**Next step.** [Confirm convergence](#confirm-convergence).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-17, 2026-09-22, 2026-09-23, 2026-09-24) |
| Published form | not executed as written (the `terraform apply` line ran in this form, without the redirection to a log, on 2026-09-23; the time stamps, log capture and state reads are derived, as in [Inspect state without writing it](#inspect-state-without-writing-it)) |
| Evidence basis | Retained private evidence of saved-plan applies on 2026-09-17 (registry), 2026-09-22 (registry and datastore network), 2026-09-23 (zone and certificate) and 2026-09-24 (datastore instance), with read-back recorded for each, and a convergence plan after each except the 2026-09-22 datastore-network apply (the 2026-09-22 registry apply converged only after its refresh-only reconciliation); the Status sections of the [foundation](../../terraform/foundation/README.md#status) and [dev-datastore](../../terraform/dev-datastore/README.md#status) READMEs |
| Authority | Explicit owner approval of this plan, identified by its hash |
| Cost | Whatever the plan creates; each root's runbook states it |

**Known limitations.** Lock acquisition and release during an apply have not been observed in
retained evidence.

### Confirm convergence

**Validation:** AWS-VALIDATED (2026-09-17 to 2026-09-24) · **Published command form:** executed as written

**What this does.** Shows that configuration and AWS agree after a change. A fresh plan, not
saved, finds nothing to change: that is *convergence*.

**Before you start.**

- [ ] The apply completed and the changed resources were read back
  ([Apply the reviewed saved plan](#apply-the-reviewed-saved-plan)).
- [ ] No other writer can be active on the root; otherwise drop `-lock=false`
  ([Plan without taking the state lock](#plan-without-taking-the-state-lock)).
- [ ] Debug logging is off ([Keep Terraform debug logging off](#keep-terraform-debug-logging-off)).
- [ ] On `terraform/dev-datastore`, an explicit owner grant.

**Safety and authority.** Read-only; it writes no state and needs no approval, except on
`terraform/dev-datastore`, where the plan reads the master secret's value (secret-reading,
owner-authorized).

**Steps.**

1. Plan without saving, and print the exit code:

   ```
   AWS_PROFILE=<profile> terraform plan -lock=false -input=false -no-color -detailed-exitcode
   echo $?
   ```

**Expected result.** Exit 0 and `No changes. Your infrastructure matches the configuration.`
On `terraform/dev` between runtime windows, this plan shows the 17 runtime creates and cannot exit
0; that root's check is
[Confirm the retained and runtime split](dev-network.md#confirm-the-retained-and-runtime-split).

**PASS when.**

- [ ] Exit 0, with that line.

**STOP if.**

- Exit 2 or 1.

**If it fails.** Do not apply a plan to make the difference go away; find its cause. No procedure
here resolves a convergence difference.

**Evidence to keep.** Nothing specific to this procedure; the campaign's evidence set applies
([Capture a campaign evidence set](evidence-handling.md#capture-a-campaign-evidence-set)).

**Next step.** Step 13 of the [Normal path](#normal-path): close the campaign's evidence set.
Exit 0 here does not prove that every attribute Terraform mirrors in state is current;
[Detect state drift](#detect-state-drift) is the check for that, run when state may lag AWS.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-17 to 2026-09-24) |
| Published form | executed as written (2026-09-23) |
| Evidence basis | Retained private evidence of post-apply plans exiting 0 on 2026-09-17, 2026-09-22, 2026-09-23 and 2026-09-24 |
| Authority | None; on `terraform/dev-datastore`, an explicit owner grant, because the plan reads the master secret's value |
| Cost | None |

**Known limitations.** Exit 0 does not prove that every attribute Terraform mirrors in state is
current: one post-apply plan exited 0 while the state still held a superseded copy of a policy
([persistent-foundations.md](persistent-foundations.md)). [Detect state drift](#detect-state-drift)
is the check for that.

### Detect state drift

**Validation:** AWS-VALIDATED (2026-09-22) for a clean result and for drift read from the plan's text or JSON; DESIGNED-NOT-EXECUTED (never) for exit 2 as the drift signal · **Published command form:** not executed as written

**What this does.** Finds differences between state and AWS that an ordinary plan does not
surface. It runs a *refresh-only* plan, which compares state with what AWS reports now and
proposes no configuration change. Detection never changes state.

**Before you start.**

- [ ] No other writer can be active on the root; otherwise drop `-lock=false`
  ([Plan without taking the state lock](#plan-without-taking-the-state-lock)).
- [ ] Debug logging is off ([Keep Terraform debug logging off](#keep-terraform-debug-logging-off)).
- [ ] On `terraform/dev-datastore`, an explicit owner grant.

**Safety and authority.** Read-only; no approval, except on `terraform/dev-datastore`, where the
plan reads the master secret's value (secret-reading, owner-authorized).

**Steps.**

1. Run a refresh-only plan, and print the exit code:

   ```
   AWS_PROFILE=<profile> terraform plan -refresh-only -input=false -no-color -lock=false -detailed-exitcode
   echo $?
   ```

**Expected result.** Exit 0 and `No changes. Your infrastructure still matches the configuration.`
Read the text as well as the exit code: exit 2 as the drift signal has never been observed here.

**PASS when.**

- [ ] Exit 0, with that line, and no `Objects have changed outside of Terraform` text.

**STOP if.**

- Drift, which is any of: exit 2, the text `Objects have changed outside of Terraform`, or any
  `resource_drift` entry in a saved refresh-only plan's JSON.
- Exit 1, which is an error.

**If it fails.** Reconcile drift only through
[Reconcile explained state-only drift](#reconcile-explained-state-only-drift), and only when the
cause of each drifted attribute is known and written down. A live value that differs from what
the configuration intends is a real change, not state lag, and goes through an ordinary reviewed
plan ([Normal path](#normal-path)).

**Evidence to keep.** Nothing specific to this procedure; the campaign's evidence set applies
([Capture a campaign evidence set](evidence-handling.md#capture-a-campaign-evidence-set)).

**Next step.** On drift,
[Reconcile explained state-only drift](#reconcile-explained-state-only-drift). On a clean result,
none.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22) for the clean result, exit 0, and for drift found in the plan's text or JSON; DESIGNED-NOT-EXECUTED (never) for exit 2 as the drift signal |
| Published form | not executed as written (the same Terraform command ran on 2026-09-22 with credentials exported by a private wrapper instead of `AWS_PROFILE`) |
| Evidence basis | Retained private evidence of 2026-09-22: a refresh-only plan that reported drift on the Dev private route table, the refresh-only check after its reconciliation returning 0, a refresh-only check after a runtime teardown returning 0, and a foundation refresh-only plan whose JSON listed one drifted attribute |
| Authority | None; on `terraform/dev-datastore`, an explicit owner grant, because the plan reads the master secret's value |
| Cost | None |

**Known limitations.** The exit 2 branch has not been observed here; drift has been found only by
reading the plan's text or JSON. Detection never changes state. A clean result says nothing about
AWS resources Terraform does not manage.

### Reconcile explained state-only drift

**Validation:** AWS-VALIDATED (2026-09-22) · **Published command form:** not executed as written

**What this does.** Records in state a difference in AWS that is explained and expected, without
changing any AWS resource. It applies a reviewed refresh-only saved plan, which writes the
refreshed values into state only. Drift is accepted by address and attribute, never wholesale.

**Before you start.**

- [ ] [Detect state drift](#detect-state-drift) reported drift.
- [ ] The cause of each drifted attribute is known and written down: a class in this table, or a
  new class reviewed as such.
- [ ] Debug logging is off ([Keep Terraform debug logging off](#keep-terraform-debug-logging-off)).
- [ ] On `terraform/dev-datastore`, an explicit owner grant for the step 2 plan, which reads the
  master secret's value.

| Root | Address and attribute | Cause | Reconciled | Result |
|---|---|---|---|---|
| `terraform/foundation` | `aws_iam_role.ci_checkout`, `inline_policy` | The push policy is its own resource, `aws_iam_role_policy.ci_checkout_ecr_push`. The role's `inline_policy` attribute mirrors it in state and kept the earlier document after the policy resource changed. | 2026-09-22 | 0 added, 0 changed, 0 destroyed; only that attribute changed in state; convergence exit 0 |
| `terraform/dev` | `aws_route_table.private`, `route` | A targeted runtime teardown destroys `aws_route.private_default` and keeps the route table, whose computed `route` attribute kept the destroyed NAT route until a refresh. | 2026-09-22 | 0 added, 0 changed, 0 destroyed; lineage and address set unchanged; refresh-only check exit 0 |

**Safety and authority.** Mutating (state only) and owner-authorized: applying the refresh-only
plan writes state, so it needs explicit owner approval of that plan. On `terraform/dev-datastore`
the step 2 plan is also secret-reading and owner-authorized. No AWS resource changes, and it costs
nothing.

**Steps.**

1. Record the serial, lineage and address digest
   ([Inspect state without writing it](#inspect-state-without-writing-it)).
2. Plan:

   ```
   AWS_PROFILE=<profile> terraform plan -refresh-only -lock=false -input=false -no-color -out=<plan-file>
   terraform show -json <plan-file> > <plan-json>
   jq '[.resource_changes[]? | select(.change.actions != ["no-op"])] | length' <plan-json>
   ```

3. List the drift and the output changes with the step 4 and 5 filters of
   [Review the saved plan](#review-the-saved-plan).
4. Read the live value from AWS through the root's runbook and confirm it is what the
   configuration intends.
5. Bind the plan
   ([Bind the saved plan to its hash and to state](#bind-the-saved-plan-to-its-hash-and-to-state)),
   obtain approval, and apply it:

   ```
   AWS_PROFILE=<profile> terraform apply -input=false -no-color <plan-file>
   ```

   > **Warning:** Never pass `-lock=false` to this apply: it writes state.

6. Inspect state again, then run [Detect state drift](#detect-state-drift).

**Expected result.** Step 2 prints `0`. Step 3 lists exactly the explained addresses and
attributes and no output change. The apply prints
`Apply complete! Resources: 0 added, 0 changed, 0 destroyed.` The serial advances by one; the
lineage and address digest are unchanged; the drift check exits 0.

**PASS when.**

- [ ] Step 2 prints `0`, and step 3 lists exactly the explained addresses and attributes and no
  output change.
- [ ] The apply reports 0 added, 0 changed, 0 destroyed.
- [ ] The serial advanced by one; the lineage and address digest are unchanged.
- [ ] The drift check exits 0.

**STOP if.**

- Any resource action.
- Any drifted address or attribute that is not explained, or a second attribute on an explained
  address.
- A change to the address set.
- A live value that differs from what the configuration intends: that is a real change, not state
  lag, and goes through an ordinary reviewed plan.

**If it fails.** A real change goes through an ordinary reviewed plan ([Normal path](#normal-path)).
A binding mismatch: discard the plan and plan again. An apply that fails or is interrupted:
[Stop after a failed or interrupted apply](#stop-after-a-failed-or-interrupted-apply).

**Evidence to keep.** The serial, lineage and address digest from steps 1 and 6, privately.

**Next step.** Return to the [Normal path](#normal-path).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22) |
| Published form | not executed as written (the foundation run used this plan and apply form with credentials exported by a private wrapper; the Dev run's plan ran with normal locking (`-lock=false` not used) and its exact commands were not retained; the acceptance checks are derived from reviewed private logic) |
| Evidence basis | Retained private evidence of the two 2026-09-22 reconciliations, foundation and Dev, each ending `0 added, 0 changed, 0 destroyed` and followed by a clean convergence or refresh-only check |
| Authority | Explicit owner approval of the refresh-only plan, because applying it writes state |
| Cost | None; no AWS resource changes |

**Known limitations.**

- Refresh drift is never accepted wholesale; each class is accepted by address and attribute.
- Step 5's binding and approval of the specific plan were exercised only in the foundation
  reconciliation. The Dev plan was accepted by a reviewed classifier and applied in the same run
  under a task-level approval.
- The route-table class is expected after every targeted teardown that removes the NAT route,
  but it was measured once: left by a 2026-09-13 teardown and found on 2026-09-22.
- The 2026-09-24 plan that created the datastore instance also recorded drift with `no-op`
  actions: `tags` on the DB subnet group and both secrets, and `ingress` on the datastore
  security group. That plan was applied, but no refresh-only plan of that root has run since, so
  this is not listed as a reconciled class.

### Move resource addresses with moved blocks

**Validation:** AWS-VALIDATED (2026-09-17) · **Published command form:** not executed as written

**What this does.** Changes a resource's address, for example folding separate resource blocks
into a `for_each` set, without destroying and recreating it. A `moved` block in the configuration
maps the old address to the new one. The plan, review, binding and apply are the normal path's.

**Before you start.**

- [ ] The refactor that changes the addresses, in the change under review.

**Safety and authority.** Mutating (state addresses) and owner-authorized: explicit owner approval
of the plan. The move itself changes no AWS resource and costs nothing.

**Steps.**

1. In the same change as the refactor, add one `moved` block per address, `from` the old address
   `to` the new one.
2. [Run the static checks](#run-the-static-checks), then [Plan to a saved file](#plan-to-a-saved-file).
3. [Review the saved plan](#review-the-saved-plan). In addition to the usual checks, list the
   moves:

   ```
   jq -r '.resource_changes[] | select(.previous_address != null) | "\(.previous_address) -> \(.address)\t\(.change.actions | join(","))"' <plan-json>
   ```

4. [Bind the plan](#bind-the-saved-plan-to-its-hash-and-to-state), obtain the owner's approval,
   and [apply it](#apply-the-reviewed-saved-plan).
5. Run `terraform state list`: the new addresses are present and none of the old ones.
6. [Confirm convergence](#confirm-convergence).

**Expected result.** Every moved address shows in step 3 with no create, destroy or replace, and
the text plan says `has moved to`. The move changes no AWS resource. The 2026-09-17 plan combined
the move with four creates and one policy update, and destroyed nothing.

**PASS when.**

- [ ] Every moved address shows in step 3 with no create, destroy or replace.
- [ ] State lists the new addresses and none of the old ones.
- [ ] Convergence exits 0.

**STOP if.**

- A moved address planned for create, destroy or replace.

**If it fails.** Do not approve: correct the configuration and plan again, as for any failed
review ([Review the saved plan](#review-the-saved-plan)). An apply that fails or is interrupted:
[Stop after a failed or interrupted apply](#stop-after-a-failed-or-interrupted-apply).

**Evidence to keep.** As for any apply
([Apply the reviewed saved plan](#apply-the-reviewed-saved-plan)). The 2026-09-17 move is proven by
the state before and after.

**Next step.** None. The `moved` blocks stay in the configuration; removing them would be a
separate reviewed change.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-17) |
| Published form | not executed as written (the configuration is public; its plan and apply followed the saved-plan procedures above, but their exact commands were not retained) |
| Evidence basis | Commit `35e4caa`, the six `moved` blocks in [`terraform/foundation/artifact-registry.tf`](../../terraform/foundation/artifact-registry.tf); retained private evidence of the 2026-09-17 apply: state before and after, all six new addresses present, no old address left, convergence exit 0 |
| Authority | Explicit owner approval of the plan |
| Cost | None for the move itself |

**Known limitations.** The 2026-09-17 plan text was not retained; the move is proven by the state
before and after. The six blocks remain in the configuration, and removing them would be a
separate reviewed change. No retained evidence or project record shows `terraform state mv`,
`state rm` or `state push` in use.

### Handle a held state lock

**Validation:** EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-10) · **Published command form:** not executed as written

**What this does.** Tells a live lock from a stale one, and releases only a stale one. The lock is
the object `<root>/terraform.tfstate.tflock` beside the state object, present while an operation
holds the lock, including a plan run without `-lock=false`. A lock is stale when no Terraform
process can still hold it. The locking design and its status are in the bootstrap README's
[Locking](../../terraform/bootstrap/README.md#locking-as-it-currently-stands).

**Before you start.**

- [ ] The identity and account checks in [operator-access.md](operator-access.md) passed in the
  current shell.
- [ ] Terraform's `Error acquiring the state lock` message, with its lock ID.
- [ ] The list of everyone with access to the state backend, and a way to reach each of them.

**Safety and authority.** Read-only to look, with no approval. `terraform force-unlock` changes the
backend and needs explicit owner approval.

> **Warning:** Force-unlock only a lock proven stale: no Terraform CLI or provider process remains
> anywhere, and the lock ID matches the one in the error. Never use `-lock=false` on a write to get
> past a lock.

**Steps.**

1. Read the lock ID, operation, holder and creation time from Terraform's
   `Error acquiring the state lock` message.
2. Check whether the lock object exists:

   ```
   aws s3api list-objects-v2 --bucket <state-bucket> --prefix <root>/ --query 'Contents[].Key' --output text --profile <profile>
   ```

3. Confirm that no Terraform process can still hold it. On the operator's machine this prints
   no Terraform CLI or provider process; provider processes can outlive the CLI:

   ```
   pgrep -fl terraform
   ```

   `pgrep -fl terraform` also matches unrelated processes whose arguments contain `terraform`,
   such as an editor or language server open on the repository. Identify each match. Every other
   operator with access confirms the same.

4. If a process remains, wait for it to end. Do not unlock.
5. If none remains, with approval:

   ```
   AWS_PROFILE=<profile> terraform force-unlock <lock-id>
   ```

   > **Warning:** Only with the owner's approval, and only after steps 3 and 4 show no process
   > remains. Answer the confirmation prompt; do not add `-force`.

6. Repeat step 2.
7. If the lock was left by a failed or interrupted apply, continue with
   [Stop after a failed or interrupted apply](#stop-after-a-failed-or-interrupted-apply) before
   any further write.

**Expected result.** Step 2 lists `<root>/terraform.tfstate` and, while held,
`<root>/terraform.tfstate.tflock`. After step 5 only the state object remains.

**PASS when.**

- [ ] No Terraform process remains on any operator's machine, and the lock ID matches the error.
- [ ] After the unlock, step 2 lists only the state object.

**STOP if.**

- A process that may hold the lock.
- A lock ID that differs from the one in the error.
- Any doubt about who holds it.

**If it fails.** If a process remains, wait for it to end; do not unlock. A lock object found by
listing, without a lock error, has no documented way to obtain its lock ID, so this procedure
cannot release it.

**Recovery copy of state.** If a recovery needs a copy of state before cleanup, write it only to
`<private-dir>` under `umask 077`, never into evidence that is exported or published. This is the
only case in which `state pull` output is written to a file. The bootstrap stages also keep state
on disk: the local state before migration and the private backup taken in
[Stage 2](../../terraform/bootstrap/README.md#stage-2-migrate-state-into-the-backend). Object
versioning also keeps prior versions, but restoring one has not been exercised.

**Evidence to keep.** Nothing specific to this procedure; the campaign's evidence set applies
([Capture a campaign evidence set](evidence-handling.md#capture-a-campaign-evidence-set)).

**Next step.** If the lock was left by a failed or interrupted apply,
[Stop after a failed or interrupted apply](#stop-after-a-failed-or-interrupted-apply), before any
further write.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-10) |
| Published form | not executed as written (standard Terraform and AWS CLI usage; no command transcript or lock ID was retained from the one recorded force-unlock) |
| Evidence basis | The recorded 2026-08-10 recovery of a terminated apply; [bootstrap README, Locking](../../terraform/bootstrap/README.md#locking-as-it-currently-stands). A retained private listing of the state bucket from 2026-09-10 shows no lock object, but it is not tied to any write. |
| Authority | None to look; explicit owner approval to force-unlock |
| Cost | None |

**Known limitations.**

- No retained evidence shows a lock taken or released, and contention has never been tested.
- The one recorded force-unlock, on 2026-08-10, followed a terminated apply. It was taken only
  after no Terraform CLI remained and an orphaned provider process had exited, and state was
  copied before any cleanup. None of it was retained.
- A check that no lock object remained after the 2026-09-22 Dev reconciliation is recorded, but
  its method is not.
- Step 1 needs a lock error. When a lock object is found by listing instead, as in
  [Stop after a failed or interrupted apply](#stop-after-a-failed-or-interrupted-apply), how to
  obtain its lock ID is not documented or exercised.
- Plans here normally use `-lock=false`, so a held lock is usually first met at apply. That
  refusal has not been observed. Its exit is non-zero, so the rules here treat it as a failed
  apply; whether it may instead be treated as a refusal that changed nothing has not been
  decided.
- `pgrep -fl terraform` also matches unrelated processes whose arguments contain `terraform`,
  such as an editor or language server open on the repository. Identify each match.

### Stop after a failed or interrupted apply

**Validation:** OFFLINE-VALIDATED (2026-09-24) · **Published command form:** not executed as written

**What this does.** Keeps a partial apply from turning into a second, unreviewed change. You
record the state as unknown, inspect read-only, and write down where each planned resource
stands. Nothing is retried. Recovery is a separate, reviewed decision.

**Before you start.**

- [ ] One of these happened: a non-zero exit, an interrupt, a lost terminal or session,
  credentials that expired during the apply, a summary that differs from the review, or an
  outcome you cannot tell.
- [ ] Before any read, the identity and account checks in
  [operator-access.md](operator-access.md) passed in the current shell; sign in again first if the
  session expired.
- [ ] The reviewed step 3 list from [Review the saved plan](#review-the-saved-plan).

**Safety and authority.** Read-only; no approval to inspect, except on `terraform/dev-datastore`,
where step 6's inspection includes a secret-reading step that needs an explicit owner grant. Every
recovery action, including `terraform state push`, `import`, `state rm` and any destroy, needs its
own reviewed decision and explicit owner approval. Resources a partial apply created keep billing
until removed; each root's runbook gives rates.

> **Warning:** Record the state as unknown. Do not run `apply` again, from this plan or a new one.

**Steps.** Record the state as unknown. Then, read-only:

1. Check whether Terraform is still running. If it is, let it finish:

   ```
   pgrep -fl terraform
   ```

   It also matches unrelated processes whose arguments contain `terraform`, such as an editor or
   language server open on the repository. Identify each match.

   > **Warning:** Do not kill a Terraform CLI or provider process to end the wait: a kill is an
   > interrupt. No wait limit is defined. A process that does not end is a matter for a reviewed
   > decision under explicit approval ([When something fails](README.md#when-something-fails)).
   > This procedure still applies if a process you waited for later exits 0 with the reviewed
   > summary: finish its steps, and nothing is applied again.

2. Keep `<private-dir>/apply.log` and the exit code, if one was printed, and read the error at
   the end of the log. Then check whether the root's directory in the working tree holds an
   `errored.tfstate`, which Terraform leaves there when it cannot save state to the backend.

   > **Warning:** An `errored.tfstate` is state: it holds full resource attributes and stays
   > private. Record that it exists and leave it where it is. Do not push, move, delete or share
   > it, and do not remove the working tree that holds it. Pushing it is a recovery action.

3. Run steps 1 to 3 of [Inspect state without writing it](#inspect-state-without-writing-it) and
   record the serial, lineage and addresses. Its PASS and STOP criteria do not apply here: a
   difference from the expected addresses is what step 7 classifies.
4. Read back from AWS every address in the reviewed step 3 list of
   [Review the saved plan](#review-the-saved-plan), whatever its action: create, update, delete
   or replace. Use the root's runbook. Count a resource as absent only on a not-found error; any
   other failure, such as `AccessDenied`, leaves it unknown.
   - An address the root's runbook has no read-back for stays unknown;
     [dev-network.md](dev-network.md#not-yet-exercised) lists the Dev Parameter Store entry, the
     two Pod Identity roles and their inline policies.
   - A Secrets Manager entry scheduled for deletion is not absent: its metadata read shows a
     `deletedDate`
     ([Read back the two Secrets Manager entries](dev-network.md#read-back-the-two-secrets-manager-entries)).
   - Error output is not projected and can carry the account ID, so redact it at capture
     ([Redact at capture](evidence-handling.md#redact-at-capture)). Step 1 of
     [Run the pre-apply gate](dev-datastore.md#run-the-pre-apply-gate) shows a form that prints
     only the error code. Its `sed` rewrites only an alphabetic error code; any other error line
     passes through whole, so redaction at capture still applies.
   - That step names not-found codes only for the datastore instance, its final snapshot name and
     the endpoint parameter. The read-backs the other root runbooks publish for the addresses they
     manage name no not-found code, and no read-back is published for
     `terraform/bootstrap`. An address for which you cannot tell a not-found error from another
     failure stays unknown.
5. Check for a lock object with step 2, the listing, of
   [Handle a held state lock](#handle-a-held-state-lock). A lock object found this way, without a
   lock error, cannot be released by that procedure: no way to obtain its lock ID is documented.
6. On `terraform/dev-datastore`, after a Stage 2 apply, also follow that root's inspection,
   [Read the datastore after a failed or interrupted apply](dev-datastore.md#read-the-datastore-after-a-failed-or-interrupted-apply),
   which adds the secret-absence proof over the apply's artifacts.
7. Write down each planned resource as: in state and in AWS; in AWS only; in state only; in
   neither, absent from state and absent from AWS by a not-found error; or unknown. For an update
   or a replace, also write down whether the read-back shows the reviewed change and, for a
   replace, whether the old object, the new one or both exist; where the read-back cannot tell,
   write unknown. If step 2 found an `errored.tfstate`, record it with the
   classification: the backend's state may not show what the apply did.

**Expected result.** Every planned resource is written down in one of the five classes, the lock
object is checked, the log and exit code are kept, and any `errored.tfstate` is recorded.

**PASS when.**

- [ ] Steps 1 to 7 are done, and every planned resource is classified.

**STOP if.**

- Everything in this procedure is a stop. Nothing is retried.

**If it fails.** Recovery is a separate reviewed decision under explicit approval: a fresh plan
from the recorded state, a targeted cleanup, or import. None is chosen in advance, and none has a
reviewed procedure here ([Not yet exercised](#not-yet-exercised)). Count a targeted plan's
destroys against its intended targets before approval.

**Evidence to keep.** `apply.log`, the exit code if one was printed, whether an
`errored.tfstate` exists, and the step 7 classification, privately.

**Next step.** The owner's reviewed recovery decision.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | OFFLINE-VALIDATED (2026-09-24) |
| Published form | not executed as written (derived from the failure contract of a reviewed apply wrapper, qualified offline on 2026-09-24 and not published; no apply has failed since that contract existed) |
| Evidence basis | Retained private evidence of the 2026-09-24 offline qualification: a failed apply stops and is not retried, an interrupt is recorded as unknown state and not retried, a hangup does not stop Terraform mid-create, and inspection changes nothing. One earlier recovery from a terminated apply, on 2026-08-10, is EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE. |
| Authority | None to inspect; every recovery action needs its own reviewed decision and explicit owner approval |
| Cost | Resources a partial apply created keep billing until removed; each root's runbook gives rates |

**Known limitations.**

- The 2026-08-10 recovery is EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT
  AVAILABLE. Two resources were tainted in state and one existed in AWS but not in state. After
  inspection, a reviewed targeted destroy removed the partial resources, the untracked one was
  deleted separately, and a clean plan and apply followed.
  During it, a broken shell line continuation dropped the targets and produced an untargeted
  plan with 23 destroys; it was caught at review and never approved. Count a targeted plan's
  destroys against its intended targets before approval.
- The not-found rule in step 4 was executed in a pre-apply check on 2026-09-24, but not in an
  inspection after a failure. The offline-qualified inspection does not apply this rule: it
  reports a failed read as "not found (or not readable)". Step 4 is derived from the 2026-09-24
  pre-apply check, not from the qualified inspection.
- The five classes record presence. No published command reads whether state marks an instance
  tainted or holds a deposed object; in the 2026-08-10 case two resources were tainted in state.
- No published procedure reads the contents of an `errored.tfstate`; step 2 only records that one
  exists.

## Not yet exercised

| Item | Label | Note |
|---|---|---|
| Terraform state recovery from a prior object version | UNEXERCISED | ADR-0011 makes one Terraform-state recovery exercise mandatory before its implementation is complete. It has not run, and no reviewed procedure exists. The [README outline](../../terraform/bootstrap/README.md#recovery) names no restore mechanism, no specific isolated test key, and no commands. The exercise runs against an isolated test state object, never the active state. Versioning being enabled is not proof that a version can be restored. |
| `terraform import` as the last resort | UNEXERCISED | It rebuilds the binding, not the state object, its serial or its outputs ([README](../../terraform/bootstrap/README.md#recovery)). |
| A reviewed recovery procedure after a failed or interrupted apply (targeted cleanup, import, re-plan) | UNEXERCISED | Only the stop-and-inspect contract above exists. The one recovery, on 2026-08-10, ran without a reviewed procedure (EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE). |
| Migrating a root's state out of the S3 backend, to local state or another key | UNEXERCISED | Backend decommission depends on it. |
| Final decommission of the state backend | UNEXERCISED | The [README](../../terraform/bootstrap/README.md#final-decommission) gives preconditions and an order, and no commands. Its order empties the bucket and then destroys the backend through Terraform, while the bootstrap root's own state object is in that bucket; the outline does not yet say where that state lives during the destroy. |
| First build of the backend from a fresh clone, with `backend.tf` moved aside | DESIGNED-NOT-EXECUTED | [Stage 1](../../terraform/bootstrap/README.md#stage-1-create-the-bucket) describes it; the one executed build predates it. Review and binding of a Stage 1 saved plan on local state have never run, and step 2 of the binding check as written reports `backend.tf` missing in that variant. |
| Removing or relocating the residual local bootstrap state after migration ([Stage 2](../../terraform/bootstrap/README.md#stage-2-migrate-state-into-the-backend) step 10) | DESIGNED-NOT-EXECUTED | The files remain protected only by file mode and `.gitignore`; their removal awaits an owner decision. |
| Initializing the bootstrap root against its own backend since the 2026-08-08 migration | DESIGNED-NOT-EXECUTED | [Initialize a root against the state backend](#initialize-a-root-against-the-state-backend) covers it; the retained inits are of other roots. |
| Initializing a root with a provider install from the registry | DESIGNED-NOT-EXECUTED | [Initialize a root against the state backend](#initialize-a-root-against-the-state-backend) performs it; every retained init installed the provider from a local plugin directory. |
| The `git check-ignore` input check on any root other than dev | DESIGNED-NOT-EXECUTED | Step 2 of [Initialize a root against the state backend](#initialize-a-root-against-the-state-backend). |
| Detecting drift by exit code 2 | DESIGNED-NOT-EXECUTED | [Detect state drift](#detect-state-drift); drift has been found only by reading a plan's text or JSON. |
| Initializing on a platform the committed lock files do not cover, and the reviewed lock-file change that would need | UNEXERCISED | |
| Lock contention: a second writer refused | UNEXERCISED | To run against an isolated test key, never an active state object ([README](../../terraform/bootstrap/README.md#locking-as-it-currently-stands)). |
| Least-privilege access to the backend | UNEXERCISED | [Access boundary](../../terraform/bootstrap/README.md#access-boundary-not-yet-demonstrated). |
| TLS-denial test and tag read-back on the state bucket | UNEXERCISED | Only the policy text was read back. |
| Removing an address from state without destroying it (`state rm` or a `removed` block) | UNEXERCISED | |
| Recovering from an init against the wrong bucket or key | UNEXERCISED | |
| Planning on the ReadOnlyAccess profile | UNEXERCISED | |

## Reproducibility gaps

What a new engineer cannot reproduce from the public repositories today, taken from the
procedures above.

| What cannot be reproduced | Public contract today | New public procedure or tool needed later |
|---|---|---|
| A later reviewed change reaching apply on an applied root: `terraform/bootstrap` has no published read-back (the path stops at step 7); `terraform/foundation` has no published expected address set (step 4 needs the list from the last apply's private evidence); `terraform/dev` and `terraform/dev-datastore` have no later-change procedure or gate. | The [Normal path](#normal-path) and its root table. | A read-back for the backend's resources; an expected address set for the foundation; later-change procedures for the dev and datastore roots. |
| The executed tooling behind several procedures: the reviewed checkers that evaluated each applied plan, the in-process pre-apply binding checks, the apply wrapper whose failure contract the stop rule is derived from, the private wrappers that supplied credentials for state reads, drift checks and reconciliation, the script that compared scan classes, the classifier that accepted the Dev reconciliation plan, and the wrappers that checked for debug logging. None is published. | The published command forms in each procedure, each labeled not executed as written, and the rules they implement. | Not established. The published forms have not run as written, so each still rests on evidence from the unpublished tooling. |
| The monthly budget and its notifications, which must exist before the first billable resource. | [ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md) requires it; [cost-and-residue.md](cost-and-residue.md) reads it back. | Yes: no creation procedure is published. |
| Terraform state recovery from a prior object version. | ADR-0011's obligation, and the bootstrap README's [recovery outline](../../terraform/bootstrap/README.md#recovery), which names no restore mechanism, no isolated test key and no commands. | Yes: a reviewed procedure. ADR-0011 makes the exercise mandatory. |
| Recovery after a failed or interrupted apply: a fresh plan, a targeted cleanup or import. | [Stop after a failed or interrupted apply](#stop-after-a-failed-or-interrupted-apply), which stops and inspects only. | Yes: a reviewed recovery procedure. None exists. |
| The backend's first build from a fresh clone, including review and binding of a Stage 1 saved plan on local state. | The bootstrap README's [Stage 1](../../terraform/bootstrap/README.md#stage-1-create-the-bucket) and [Stage 2](../../terraform/bootstrap/README.md#stage-2-migrate-state-into-the-backend), as step-level instructions without commands. | Yes: step 2 of the binding check as written reports `backend.tf` missing when it is moved aside, and no form for local state exists. |
| Migrating a root's state out of the backend, and the backend's final decommission. | The bootstrap README's [Final decommission](../../terraform/bootstrap/README.md#final-decommission): preconditions and an order, no commands. | Yes: commands, and where the bootstrap root's own state lives during the destroy. |
| Releasing a lock object found by listing, without a lock error. | [Handle a held state lock](#handle-a-held-state-lock), which needs the lock ID from the error. | Yes: a documented way to obtain the lock ID. |
| A provider install from the registry, and initialization on a platform the lock files do not cover. Which committed hash belongs to which platform is not established. | The committed lock files and [Initialize a root against the state backend](#initialize-a-root-against-the-state-backend). | No new tool: a run of the published init. Another platform needs a reviewed lock-file change. |
| The binding check on a Terraform version other than 1.15.5. | [Bind the saved plan to its hash and to state](#bind-the-saved-plan-to-its-hash-and-to-state), whose archive layout was measured on 1.15.5 and is not a documented interface. | No new tool: re-check the layout after any Terraform upgrade. |
| The rationale for the scan findings accepted on 2026-09-21 for the foundation and dev-datastore roots. Not every rationale is published. | The class comparison in [Run the static checks](#run-the-static-checks), which carries existing findings rather than re-deciding them. | No procedure or tool: the gap is the unpublished rationale. |
| When saved plans, plan JSON, logs and working trees holding filled inputs are removed. | The `<private-dir>` and `<work-dir>` conventions and `.gitignore`. | Yes: no deletion rule is defined. |

<a id="hidden-prerequisites"></a>

## Background prerequisites

- The tools, private inputs, working directories and evidence tooling needed before a first
  action are listed under [Before you start](#before-you-start).
- A dedicated AWS account and its account ID, supplied as `allowed_account_id` in each root's
  untracked `terraform.tfvars`.
- An operator identity with the AdministratorAccess permission set and a local SSO profile
  ([operator-access.md](operator-access.md)).
- The monthly budget and its notifications, created outside Terraform before the first billable
  resource. [cost-and-residue.md](cost-and-residue.md) reads them back; no creation procedure is
  published.
- A list of everyone with access to the state backend, and a way to reach each of them, for the
  lock check.
