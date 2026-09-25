# Terraform Operations

## Scope

This runbook owns the change workflow every Terraform root in this repository shares: the static
and security checks, initializing a root against the S3 backend, the reviewed saved plan and its
binding to state, apply, convergence, drift detection and refresh-only reconciliation, state
locks, the rule for a failed or interrupted apply, moved blocks, and debug-logging safety.
[ADR-0003](../decisions/0003-adopt-terraform-and-remote-state-management.md) fixes the workflow
and the state model, and
[ADR-0011](../decisions/0011-define-the-backup-and-recovery-model.md) fixes the recovery
obligations for state. This page is the procedure.

It links, rather than repeats:

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
  teardown, which are outside this runbook.

| Root | State key, from `backend.tf` | Private inputs |
|---|---|---|
| `terraform/bootstrap` | `bootstrap/terraform.tfstate` | [Input](../../terraform/bootstrap/README.md#input) |
| `terraform/foundation` | `foundation/terraform.tfstate` | [Input](../../terraform/foundation/README.md#input) |
| `terraform/dev` | `dev/terraform.tfstate` | [Input](../../terraform/dev/README.md#input) |
| `terraform/dev-datastore` | `dev-datastore/terraform.tfstate` | [What it creates](../../terraform/dev-datastore/README.md#what-it-creates) |

Every backend uses the same bucket in `us-east-1` with `encrypt = true` and
`use_lockfile = true`. The bucket name reaches Terraform only through the untracked `backend.hcl`.

Conventions:

- `<profile>` is the AdministratorAccess profile from [operator-access.md](operator-access.md).
  The recorded plans and applies ran on that permission set; none has run on ReadOnlyAccess. For
  a long or sensitive operation, [operator-access.md](operator-access.md) runs it on role
  credentials exported once into a clean shell; the commands below are then run without
  `AWS_PROFILE=<profile>` or `--profile <profile>`.
- `<root>` is one of `bootstrap`, `foundation`, `dev` or `dev-datastore`: the directory under
  `terraform/` and the prefix of that root's state key.
- `<commit>` is the full SHA of the reviewed commit. `<main-commit>` is the full SHA of `main`
  that a change is compared against.
- `<work-dir>` is a new directory outside every existing Git working tree, for the working tree
  [Initialize a root against the state backend](#initialize-a-root-against-the-state-backend)
  creates. `<scan-dir>` is a new scratch directory outside every working tree, for the scan in
  [Run the static checks](#run-the-static-checks).
- `<inputs-dir>` is a private directory per root, outside every working tree, holding that
  root's filled `backend.hcl` and `terraform.tfvars`. The roots take different variables, so one
  root's file never serves another.
- `<private-dir>` is a directory outside every Git working tree, created under `umask 077`; use a
  new one for each plan. It holds that plan, its JSON and their logs. A saved plan carries every
  input value and the prior state's attributes in clear text. `.gitignore` excludes `*.tfplan`; it
  does not exclude JSON, so plan JSON must never be written inside the repository. No rule for
  when saved plans, plan JSON and logs are deleted has been defined; the saved plans of applied
  changes have been kept privately with their evidence.
- `<plan-file>` is the absolute path of a saved plan in `<private-dir>`, and `<plan-json>` its
  `terraform show -json` rendering beside it.
- `<state-bucket>` is the state bucket name from `backend.hcl`. `<lock-id>` is the lock ID
  Terraform prints in a lock error. `<n>` is a resource count in Terraform's summary line.
- Commands run from `terraform/<root>` in the working tree the change was reviewed in, unless a
  step says otherwise.
- **Published form** says whether the command form shown, placeholders aside, appears as
  executed in retained private evidence.

## Procedures

### Build the state backend and migrate into it

| Field | Value |
|---|---|
| Validation status | EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-08) |
| Published form | not executed as written (the README gives step-level instructions, not commands; the 2026-08-08 run began before `backend.tf` existed, so the fresh-clone variant that moves `backend.tf` aside has never run) |
| Evidence basis | [Bootstrap README Status](../../terraform/bootstrap/README.md#status); retained private evidence of a 2026-09-10 read-only listing of the state bucket that shows the bootstrap state object at its key. No apply, read-back or migration output was retained. |
| Authority | Explicit owner approval for the stage 1 apply, the project's first billable resource, and separate approval for the migration |
| Cost | The bucket bills for its stored state objects; no separate figure has been measured. Native locking needs no DynamoDB table; its S3 requests have not been measured separately. |

- **Purpose.** Create the state bucket on local state, then move that state into it. The
  procedure is the README's
  [Stage 1](../../terraform/bootstrap/README.md#stage-1-create-the-bucket) and
  [Stage 2](../../terraform/bootstrap/README.md#stage-2-migrate-state-into-the-backend), and it
  is not repeated here.
- **Preconditions.** The project account and operator identity
  ([operator-access.md](operator-access.md)); a budget with its alerts in place before the first
  billable resource ([cost-and-residue.md](cost-and-residue.md)).
- **Validation.** Initialize the root and run
  [Inspect state without writing it](#inspect-state-without-writing-it): it lists exactly the
  five resources in the README. [Confirm convergence](#confirm-convergence) returns 0.
- **STOP conditions.** The migration prompt names a backend or key you did not expect. Never
  pass `-force-copy`; the README says why.
- **Known limitations.**
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

| Field | Value |
|---|---|
| Validation status | OFFLINE-VALIDATED (2026-09-21 to 2026-09-23) |
| Published form | not executed as written (`terraform fmt -check -recursive` and `terraform validate` ran in this form on 2026-09-23; the backend-less init ran with `-plugin-dir` pointing at an already installed provider rather than installing from the registry; TFLint ran with explicit `--chdir` and `--config` arguments; `trivy config` ran in this form on `git archive` extractions on 2026-09-22, and the class comparison was made by a private script from which the `jq` form is derived; the lock-file check is derived from the 2026-09-23 record that init left the lock file unchanged) |
| Evidence basis | Retained private evidence of the static checks on the foundation and dev-datastore roots on 2026-09-21, 2026-09-22 and 2026-09-23, and of the configuration scan of the foundation, dev and dev-datastore roots on 2026-09-21 and 2026-09-22; the bootstrap, foundation and dev READMEs record that formatting, `terraform validate` and TFLint passed |
| Authority | None; no credentials and no backend |
| Cost | None |

- **Purpose.** Catch formatting, syntax, lint and security-configuration errors before any
  credential is used.
- **Preconditions.** A clean tree at the commit under review, holding no filled `terraform.tfvars`
  or `backend.hcl`. The 2026-09-23 run used an extraction of tracked files only.
- **Procedure.**
  1. From the repository's `terraform/` directory:

     ```
     terraform fmt -check -recursive
     ```

  2. In each changed root:

     ```
     terraform init -backend=false -input=false
     git status --porcelain -- .terraform.lock.hcl
     terraform validate
     tflint
     ```

  3. The security check ADR-0003 requires: scan each changed root and compare its finding classes
     with the same root on `main`. From the repository root:

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

- **Expected result.** `fmt` prints nothing and exits 0; `git status` prints nothing; `validate`
  prints `Success! The configuration is valid.`; `tflint` prints nothing and exits 0 with the
  root's `.tflint.hcl`. Each `trivy config` exits 0, and `diff` prints nothing: the change adds no
  finding class, by check ID and severity, that the root on `main` does not already have.
- **STOP conditions.** Any non-zero exit. `git status` prints a line: `init` changed the lock
  file, and a plan made from that tree would fail the binding check. `diff` prints a line
  beginning `>`: a new finding class, which goes no further without a recorded acceptance
  decision.
- **Known limitations.**
  - Never add `-diff` to `terraform fmt` in a directory that holds a filled `terraform.tfvars`:
    `fmt` also formats `.tfvars` files, and `-diff` prints their contents.
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

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-23, 2026-09-24) for initializing the foundation and dev-datastore roots with the provider installed from a local plugin directory; EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-09) for the `git check-ignore` step on the dev root; DESIGNED-NOT-EXECUTED (never) for the `git check-ignore` step on the other roots and for the registry provider install |
| Published form | not executed as written (the executed inits added `-plugin-dir` pointing at a previously installed provider, so a registry install has no retained evidence; the input copy was recorded as a description, not a command; the `git check-ignore` step was not part of them; the lock-file check is derived from the 2026-09-23 static check that recorded the lock file unchanged by init) |
| Evidence basis | Retained private evidence of the 2026-09-23 initialization of `terraform/foundation` in a fresh detached working tree, with its output, and of the 2026-09-24 initialization of `terraform/dev-datastore`, recorded as the first step of a retained plan run |
| Authority | None; it reads the backend only |
| Cost | None |

- **Purpose.** Prepare a working tree at the reviewed commit, with the root's untracked inputs in
  place, bound to the root's state object.
- **Preconditions.** The identity and account checks in [operator-access.md](operator-access.md)
  passed for `<profile>`; the reviewed commit.
- **Inputs.** A filled `backend.hcl` naming the state bucket the bootstrap root created, and a
  filled `terraform.tfvars` for the root, both in that root's `<inputs-dir>`. For
  `terraform/foundation`, `backend.hcl` names the state bucket, never the evidence bucket.
- **Procedure.**
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

  3. Initialize, then confirm the lock file is unchanged:

     ```
     AWS_PROFILE=<profile> terraform init -input=false -no-color -backend-config=backend.hcl
     git status --porcelain -- .terraform.lock.hcl
     ```

- **Expected result.** `git check-ignore` lists both paths. `init` prints
  `Successfully configured the backend "s3"!` and `Terraform has been successfully initialized!`,
  and installs the provider version recorded in `.terraform.lock.hcl` (hashicorp/aws 6.58.0 at
  the time of writing). `git status` prints nothing.
- **Validation.** [Inspect state without writing it](#inspect-state-without-writing-it) lists the
  addresses the root's README says exist. A root that has never been applied lists nothing.
- **STOP conditions.** `git check-ignore` does not list a path: that file would be tracked. `init`
  reports that the backend configuration changed or that state must be migrated: find out why
  before anything else. `init` fails, for example because `backend.hcl` is missing. `git status`
  prints a line: `init` changed the lock file, and a plan made here would fail the binding check.
- **Teardown / decommission.** No rule for removing this working tree, which holds the filled
  inputs and `.terraform/` with the backend configuration, has been defined or exercised here;
  [dev-datastore.md](dev-datastore.md) removes the working tree of its first stage.
- **Known limitations.**
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

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22) |
| Published form | not executed as written (`terraform state list` ran in this form with credentials supplied by a private wrapper rather than `AWS_PROFILE`; serial, lineage and address sets were read by piping `terraform state pull` into a private parser, from which the `jq` and `shasum` forms are derived) |
| Evidence basis | Retained private evidence of 2026-09-22: state serial, lineage and address set recorded before and after the Dev and foundation reconciliations and the foundation apply |
| Authority | None; read-only, and it does not take the lock |
| Cost | None |

- **Purpose.** See what a root manages, and record the serial, lineage and address set that the
  binding and post-apply checks compare.
- **Preconditions.** The root is initialized; the identity and account checks in
  [operator-access.md](operator-access.md) passed in the current shell.
- **Procedure.**

  ```
  AWS_PROFILE=<profile> terraform state list
  AWS_PROFILE=<profile> terraform state pull | jq '{serial, lineage}'
  AWS_PROFILE=<profile> terraform state list | LC_ALL=C sort | shasum -a 256
  ```

- **Expected result.** `state list` prints instance addresses, keys included, for example
  `aws_ecr_repository.workload["cart"]`. The digest covers those instance addresses, so adding or
  removing a `for_each` instance changes it.
- **STOP conditions.** Never redirect `state pull` to a file: state holds full resource attributes.
  The one exception is a recovery copy, described under
  [Handle a held state lock](#handle-a-held-state-lock).
- **Known limitations.** A state list is an inventory of managed state, not a census of AWS. It says
  nothing about resources Terraform does not manage; the orphan census is in
  [cost-and-residue.md](cost-and-residue.md). On `terraform/dev-datastore`, `state list` and
  `state pull` do not read the master secret; every plan does.

### Plan to a saved file

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-21 to 2026-09-24) |
| Published form | executed as written (2026-09-23) |
| Evidence basis | Retained private evidence of the saved plans behind the 2026-09-22 registry and datastore-network applies, the 2026-09-23 zone and certificate applies and the 2026-09-24 datastore-instance apply |
| Authority | None for the plan itself; it writes no state. On `terraform/dev-datastore`, an explicit owner grant, because every plan there reads the master secret's value. |
| Cost | None |

- **Purpose.** Produce the one artifact that is reviewed, bound and applied.
- **Preconditions.** Static checks pass; the root is initialized at the reviewed commit; debug
  logging is off ([Keep Terraform debug logging off](#keep-terraform-debug-logging-off)); the
  caller is confirmed.
- **Procedure.**

  ```
  AWS_PROFILE=<profile> terraform plan -lock=false -input=false -no-color -detailed-exitcode -out=<plan-file>
  echo $?
  ```

- **Expected result.** Exit 2 when the plan has changes, as observed on 2026-09-23 and
  2026-09-24. Exit 0 means there is nothing to apply; exit 1 is an error.
- **STOP conditions.** Exit 1. Exit 0 when a change was expected. `-lock=false` is safe only under
  the conditions in [Plan without taking the state lock](#plan-without-taking-the-state-lock).
- **Known limitations.**
  - On `terraform/dev-datastore` a plan fails if the master container holds no value
    ([README](../../terraform/dev-datastore/README.md#what-it-creates)).
  - The 2026-09-23 plan, run in this form, wrote its saved plan inside the working tree, where
    `.gitignore` excludes `*.tfplan`; the plan was then kept in private storage and applied from
    there, and where its JSON was written is not recorded. The 2026-09-24 plan was written
    directly to a private directory outside the tree, by a reviewed wrapper that is not
    published.
- **Next gate.** [Review the saved plan](#review-the-saved-plan).

### Plan without taking the state lock

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22, 2026-09-23) |
| Published form | not executed as written (the `-lock=false` flag appears in the 2026-09-23 plan and convergence commands; the 2026-09-23 certificate and 2026-09-24 datastore applies of `-lock=false` plans skipped the serial-and-lineage binding these rules require, and the 2026-09-23 zone apply compared the serial only) |
| Evidence basis | Retained private evidence of plans made with `-lock=false` from 2026-09-21 to 2026-09-24, and of the pre-apply checks that bound the 2026-09-22 applies to the state serial and lineage and the 2026-09-23 zone apply to the serial |
| Authority | None |
| Cost | None |

- **Purpose.** State when a plan may skip the lock, and what makes that safe. A plan never writes
  state, with or without the lock; skipping the lock only means the plan neither waits for nor
  refuses a writer that holds it. For a saved plan made with `-lock=false`, the safety basis is
  [Bind the saved plan to its hash and to state](#bind-the-saved-plan-to-its-hash-and-to-state),
  not the flag: it proves the backend still holds the state the plan was made from, and a write
  that lands between plan and apply changes the serial, so the plan is discarded.
  `terraform apply` runs without `-lock=false`, so it requests the lock.
- **Preconditions.** A plan that is only read, a convergence or drift check, has no later check to
  catch a concurrent write. Use `-lock=false` for it only when no other writer can be active on
  the root; otherwise leave the flag off, so the plan waits for the lock or fails.
- **STOP conditions.** A saved plan made with `-lock=false` whose binding check has not passed
  immediately before apply: do not apply it. Never pass `-lock=false` to a command that writes
  state: `apply`, including a refresh-only apply, `import`, `state mv` or `state rm`.
- **Known limitations.**
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

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22 to 2026-09-24) |
| Published form | not executed as written (`terraform show -no-color` and `terraform show -json` ran in this form on 2026-09-23; the `jq` filters are derived from the reviewed checkers that evaluated each applied plan, whose code is not published) |
| Evidence basis | Retained private evidence of exact-shape checks on the saved plans applied on 2026-09-22, 2026-09-23 and 2026-09-24, each checker qualified offline with positive and negative controls before use |
| Authority | None |
| Cost | None |

- **Purpose.** Decide that the plan does exactly what the change intends and nothing else. Under
  ADR-0003 this review is the approval point.
- **Procedure.**
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

- **Expected result.**
  - `applyable` and `complete` are `true`, `errored` is `false`, and `terraform_version` is the
    version the change was validated with.
  - The step 3 list equals the reviewed list exactly, address and action.
  - Every step 4 line names an address and attribute with a written cause, and that address has
    a `no-op` planned action.
  - Step 5 shows only the expected outputs.
- **STOP conditions.** Any criterion fails. A `delete` or `delete,create` the review does not name.
  For a targeted plan, a destroy count that differs from the intended targets. Do not approve with
  an exception: correct the configuration or inputs and plan again.
- **Evidence to retain.** The step 3 to 5 lists, the Terraform version and the plan's sha256,
  privately ([evidence-handling.md](evidence-handling.md)). Never publish the plan, its JSON or
  its text: they carry account identifiers, bucket names and every input value.
- **Known limitations.** A value unknown until apply cannot be reviewed from the plan. On
  2026-09-17 and 2026-09-22 the CI push policy document was unknown at plan time and was
  confirmed by read-back after apply.

### Bind the saved plan to its hash and to state

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22, 2026-09-23) |
| Published form | not executed as written (derived from pre-apply checks that read the same values in-process on 2026-09-22; the plan archive layout used below was measured on Terraform 1.15.5 and is not a documented interface) |
| Evidence basis | Retained private evidence of the 2026-09-22 foundation apply, refresh-only apply and datastore-network apply, each preceded by checks of the plan hash, its embedded configuration and lock file, and the remote serial and lineage against the plan's prior state (for the datastore network, the root's first apply, against a remote state never yet written); and of the 2026-09-23 zone apply, preceded by a comparison of the remote serial with the plan-time serial (lineage recorded, not compared; no plan-hash re-check retained) |
| Authority | None |
| Cost | None |

- **Purpose.** Make the reviewed plan the only thing that can be applied, and only against the
  state it was made from.
- **Procedure.**
  1. At review, record the plan's hash and the state it was made from:

     ```
     shasum -a 256 <plan-file>
     unzip -p <plan-file> tfstate | jq '{serial, lineage}'
     ```

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

- **Expected result.** Step 2 prints `same` for every file and the lock file, and `diff` prints
  nothing. In step 3 the hash equals the one recorded, and the serial and lineage equal the
  plan's. For a root's first apply, step 1 shows serial 0 and an empty lineage; the 2026-09-22
  check read that root's remote state as serial 0 with no lineage and no resources. The `jq`
  rendering of that remote read was not captured, so whether it prints an empty or a null lineage
  is not recorded.
- **STOP conditions.** Any mismatch. Discard the plan, plan again and review again. A serial that
  moved means something wrote state after the plan was made; find out what before planning again.
- **Known limitations.**
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

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-17, 2026-09-22, 2026-09-23, 2026-09-24) |
| Published form | not executed as written (the `terraform apply` line ran in this form, without the redirection to a log, on 2026-09-23; the time stamps, log capture and state reads are derived, as in [Inspect state without writing it](#inspect-state-without-writing-it)) |
| Evidence basis | Retained private evidence of saved-plan applies on 2026-09-17 (registry), 2026-09-22 (registry and datastore network), 2026-09-23 (zone and certificate) and 2026-09-24 (datastore instance), with read-back recorded for each, and a convergence plan after each except the 2026-09-22 datastore-network apply (the 2026-09-22 registry apply converged only after its refresh-only reconciliation); the Status sections of the [foundation](../../terraform/foundation/README.md#status) and [dev-datastore](../../terraform/dev-datastore/README.md#status) READMEs |
| Authority | Explicit owner approval of this plan, identified by its hash |
| Cost | Whatever the plan creates; each root's runbook states it |

- **Purpose.** Apply exactly the reviewed plan, once.
- **Preconditions.** The plan is reviewed and approved; the binding check passes immediately
  before; the session outlives the apply ([operator-access.md](operator-access.md)); debug logging
  is off.
- **Procedure.**
  1. Apply, writing the output to a log in `<private-dir>`, with the time before and after:

     ```
     date -u +%Y-%m-%dT%H:%M:%SZ
     AWS_PROFILE=<profile> terraform apply -input=false -no-color <plan-file> > <private-dir>/apply.log 2>&1
     echo $?
     date -u +%Y-%m-%dT%H:%M:%SZ
     tail -n 5 <private-dir>/apply.log
     ```

     A saved plan applies without a confirmation prompt; the approval happened at review.
  2. Read the state after the apply:

     ```
     AWS_PROFILE=<profile> terraform state pull | jq '{serial, lineage}'
     AWS_PROFILE=<profile> terraform state list | LC_ALL=C sort
     ```

- **Expected result.** Exit 0, and the log ends with
  `Apply complete! Resources: <n> added, <n> changed, <n> destroyed.` with counts equal to the
  reviewed list. The serial has advanced, and the lineage equals the one recorded in the binding
  check, except on a root's first apply, which creates the state. The address list includes every
  reviewed create and every moved-to address, and none of the reviewed destroys or moved-from
  addresses.
- **Validation.** Read back the changed resources through the root's runbook, then
  [Confirm convergence](#confirm-convergence).
- **Evidence to retain.** The plan hash, `apply.log` with the exit code, start and end UTC, and the
  serial and lineage before (from the binding check) and after, privately.
- **STOP conditions.** A non-zero exit, an interrupt, a lost terminal, a session that expired
  during the apply, or a summary that differs from the review. Go to
  [Stop after a failed or interrupted apply](#stop-after-a-failed-or-interrupted-apply). Never run
  the apply again.
- **Known limitations.** Lock acquisition and release during an apply have not been observed in
  retained evidence.
- **Next gate.** [Confirm convergence](#confirm-convergence).

### Confirm convergence

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-17 to 2026-09-24) |
| Published form | executed as written (2026-09-23) |
| Evidence basis | Retained private evidence of post-apply plans exiting 0 on 2026-09-17, 2026-09-22, 2026-09-23 and 2026-09-24 |
| Authority | None; on `terraform/dev-datastore`, an explicit owner grant, because the plan reads the master secret's value |
| Cost | None |

- **Purpose.** Show that configuration and AWS agree after a change.
- **Preconditions.** No other writer can be active on the root; otherwise drop `-lock=false`
  ([Plan without taking the state lock](#plan-without-taking-the-state-lock)).
- **Procedure.**

  ```
  AWS_PROFILE=<profile> terraform plan -lock=false -input=false -no-color -detailed-exitcode
  echo $?
  ```

- **Expected result.** Exit 0 and `No changes. Your infrastructure matches the configuration.`
- **STOP conditions.** Exit 2 or 1. Do not apply a plan to make the difference go away; find its
  cause.
- **Known limitations.** Exit 0 does not prove that every attribute Terraform mirrors in state is
  current: one post-apply plan exited 0 while the state still held a superseded copy of a policy
  ([persistent-foundations.md](persistent-foundations.md)). [Detect state drift](#detect-state-drift)
  is the check for that.

### Detect state drift

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22) for the clean result, exit 0, and for drift found in the plan's text or JSON; DESIGNED-NOT-EXECUTED (never) for exit 2 as the drift signal |
| Published form | not executed as written (the same Terraform command ran on 2026-09-22 with credentials exported by a private wrapper instead of `AWS_PROFILE`) |
| Evidence basis | Retained private evidence of 2026-09-22: a refresh-only plan that reported drift on the Dev private route table, the refresh-only check after its reconciliation returning 0, a refresh-only check after a runtime teardown returning 0, and a foundation refresh-only plan whose JSON listed one drifted attribute |
| Authority | None; on `terraform/dev-datastore`, an explicit owner grant, because the plan reads the master secret's value |
| Cost | None |

- **Purpose.** Find differences between state and AWS that an ordinary plan does not surface.
- **Preconditions.** No other writer can be active on the root; otherwise drop `-lock=false`
  ([Plan without taking the state lock](#plan-without-taking-the-state-lock)).
- **Procedure.**

  ```
  AWS_PROFILE=<profile> terraform plan -refresh-only -input=false -no-color -lock=false -detailed-exitcode
  echo $?
  ```

- **Expected result.** Exit 0 and `No changes. Your infrastructure still matches the configuration.`
- **STOP conditions.** Any of these is drift: exit 2, the text `Objects have changed outside of
  Terraform`, or any `resource_drift` entry in a saved refresh-only plan's JSON. Reconcile it only
  through the next procedure. Exit 1 is an error; stop.
- **Known limitations.** The exit 2 branch has not been observed here; drift has been found only by
  reading the plan's text or JSON. Detection never changes state. A clean result says nothing about
  AWS resources Terraform does not manage.

### Reconcile explained state-only drift

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22) |
| Published form | not executed as written (the foundation run used this plan and apply form with credentials exported by a private wrapper; the Dev run's plan ran with normal locking (`-lock=false` not used) and its exact commands were not retained; the acceptance checks are derived from reviewed private logic) |
| Evidence basis | Retained private evidence of the two 2026-09-22 reconciliations, foundation and Dev, each ending `0 added, 0 changed, 0 destroyed` and followed by a clean convergence or refresh-only check |
| Authority | Explicit owner approval of the refresh-only plan, because applying it writes state |
| Cost | None; no AWS resource changes |

- **Purpose.** Record in state a difference in AWS that is explained and expected, without changing
  any AWS resource.
- **Preconditions.** [Detect state drift](#detect-state-drift) reported drift, and the cause of each
  drifted attribute is known and written down: a class in this table, or a new class reviewed as
  such.

  | Root | Address and attribute | Cause | Reconciled | Result |
  |---|---|---|---|---|
  | `terraform/foundation` | `aws_iam_role.ci_checkout`, `inline_policy` | The push policy is its own resource, `aws_iam_role_policy.ci_checkout_ecr_push`. The role's `inline_policy` attribute mirrors it in state and kept the earlier document after the policy resource changed. | 2026-09-22 | 0 added, 0 changed, 0 destroyed; only that attribute changed in state; convergence exit 0 |
  | `terraform/dev` | `aws_route_table.private`, `route` | A targeted runtime teardown destroys `aws_route.private_default` and keeps the route table, whose computed `route` attribute kept the destroyed NAT route until a refresh. | 2026-09-22 | 0 added, 0 changed, 0 destroyed; lineage and address set unchanged; refresh-only check exit 0 |

- **Procedure.**
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
  5. Bind the plan ([Bind the saved plan to its hash and to state](#bind-the-saved-plan-to-its-hash-and-to-state)),
     obtain approval, and apply it:

     ```
     AWS_PROFILE=<profile> terraform apply -input=false -no-color <plan-file>
     ```

  6. Inspect state again, then run [Detect state drift](#detect-state-drift).
- **Expected result.** Step 2 prints `0`. Step 3 lists exactly the explained addresses and
  attributes and no output change. The apply prints
  `Apply complete! Resources: 0 added, 0 changed, 0 destroyed.` The serial advances by one; the
  lineage and address digest are unchanged; the drift check exits 0.
- **STOP conditions.** Any resource action. Any drifted address or attribute that is not explained,
  or a second attribute on an explained address. A change to the address set. A live value that
  differs from what the configuration intends: that is a real change, not state lag, and goes
  through an ordinary reviewed plan.
- **Known limitations.**
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

### Handle a held state lock

| Field | Value |
|---|---|
| Validation status | EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-10) |
| Published form | not executed as written (standard Terraform and AWS CLI usage; no command transcript or lock ID was retained from the one recorded force-unlock) |
| Evidence basis | The recorded 2026-08-10 recovery of a terminated apply; [bootstrap README, Locking](../../terraform/bootstrap/README.md#locking-as-it-currently-stands). A retained private listing of the state bucket from 2026-09-10 shows no lock object, but it is not tied to any write. |
| Authority | None to look; explicit owner approval to force-unlock |
| Cost | None |

- **Purpose.** Tell a live lock from a stale one, and release only a stale one. The lock is the
  object `<root>/terraform.tfstate.tflock` beside the state object, present while an operation
  holds the lock, including a plan run without `-lock=false`. The locking design and its status
  are in the bootstrap README's
  [Locking](../../terraform/bootstrap/README.md#locking-as-it-currently-stands).
- **Preconditions.** The identity and account checks in [operator-access.md](operator-access.md)
  passed in the current shell.
- **Procedure.**
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

     Every other operator with access confirms the same.
  4. If a process remains, wait for it to end. Do not unlock.
  5. If none remains, with approval:

     ```
     AWS_PROFILE=<profile> terraform force-unlock <lock-id>
     ```

     Answer the confirmation prompt; do not add `-force`.
  6. Repeat step 2.
  7. If the lock was left by a failed or interrupted apply, continue with
     [Stop after a failed or interrupted apply](#stop-after-a-failed-or-interrupted-apply) before
     any further write.
- **Expected result.** Step 2 lists `<root>/terraform.tfstate` and, while held,
  `<root>/terraform.tfstate.tflock`. After step 5 only the state object remains.
- **STOP conditions.** A process that may hold the lock; a lock ID that differs from the one in the
  error; any doubt about who holds it. Never use `-lock=false` on a write to get past a lock.
- **Recovery / rollback.** If a recovery needs a copy of state before cleanup, write it only to
  `<private-dir>` under `umask 077`, never into evidence that is exported or published. This is the
  only case in which `state pull` output is written to a file. The bootstrap stages also keep state
  on disk: the local state before migration and the private backup taken in
  [Stage 2](../../terraform/bootstrap/README.md#stage-2-migrate-state-into-the-backend). Object
  versioning also keeps prior versions, but restoring one has not been exercised.
- **Known limitations.**
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

| Field | Value |
|---|---|
| Validation status | OFFLINE-VALIDATED (2026-09-24) |
| Published form | not executed as written (derived from the failure contract of a reviewed apply wrapper, qualified offline on 2026-09-24 and not published; no apply has failed since that contract existed) |
| Evidence basis | Retained private evidence of the 2026-09-24 offline qualification: a failed apply stops and is not retried, an interrupt is recorded as unknown state and not retried, a hangup does not stop Terraform mid-create, and inspection changes nothing. One earlier recovery from a terminated apply, on 2026-08-10, is EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE. |
| Authority | None to inspect; every recovery action needs its own reviewed decision and explicit owner approval |
| Cost | Resources a partial apply created keep billing until removed; each root's runbook gives rates |

- **Purpose.** Keep a partial apply from turning into a second, unreviewed change.
- **Preconditions.** Any of: a non-zero exit, an interrupt, a lost terminal or session, credentials
  that expired during the apply, a summary that differs from the review, or an outcome you cannot
  tell. Before any read, the identity and account checks in
  [operator-access.md](operator-access.md) passed in the current shell; sign in again first if the
  session expired.
- **Procedure.** Record the state as unknown. Do not run `apply` again, from this plan or a new one.
  Then, read-only:
  1. `pgrep -fl terraform`. If Terraform is still running, let it finish.
  2. Keep `<private-dir>/apply.log` and the exit code, if one was printed.
  3. [Inspect state without writing it](#inspect-state-without-writing-it).
  4. Read back from AWS every address in the reviewed step 3 list of
     [Review the saved plan](#review-the-saved-plan), whatever its action: create, update, delete
     or replace. Use the root's runbook. Count a resource as absent only on a not-found error; any
     other failure, such as `AccessDenied`, leaves it unknown.
  5. Check for a lock object ([Handle a held state lock](#handle-a-held-state-lock)).
  6. On `terraform/dev-datastore`, also follow that root's inspection in
     [dev-datastore.md](dev-datastore.md), which adds the secret-absence proof over the apply's
     artifacts.
  7. Write down each planned resource as: in state and in AWS; in AWS only; in state only; or
     unknown.
- **STOP conditions.** Everything in this procedure is a stop. Nothing is retried.
- **Recovery / rollback.** A separate reviewed decision under explicit approval: a fresh plan from
  the recorded state, a targeted cleanup, or import. None is chosen in advance, and none has a
  reviewed procedure here.
- **Known limitations.**
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

### Move resource addresses with moved blocks

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-17) |
| Published form | not executed as written (the configuration is public; its plan and apply followed the saved-plan procedures above, but their exact commands were not retained) |
| Evidence basis | Commit `35e4caa`, the six `moved` blocks in [`terraform/foundation/artifact-registry.tf`](../../terraform/foundation/artifact-registry.tf); retained private evidence of the 2026-09-17 apply: state before and after, all six new addresses present, no old address left, convergence exit 0 |
| Authority | Explicit owner approval of the plan |
| Cost | None for the move itself |

- **Purpose.** Change a resource's address, for example folding separate resource blocks into a
  `for_each` set, without destroying and recreating it.
- **Procedure.**
  1. In the same change as the refactor, add one `moved` block per address, `from` the old address
     `to` the new one.
  2. Run the static checks, then [Plan to a saved file](#plan-to-a-saved-file).
  3. Review the plan. In addition to the usual checks, list the moves:

     ```
     jq -r '.resource_changes[] | select(.previous_address != null) | "\(.previous_address) -> \(.address)\t\(.change.actions | join(","))"' <plan-json>
     ```

  4. Bind, approve and apply the plan.
  5. Run `terraform state list`: the new addresses are present and none of the old ones.
  6. [Confirm convergence](#confirm-convergence).
- **Expected result.** Every moved address shows in step 3 with no create, destroy or replace, and
  the text plan says `has moved to`. The move changes no AWS resource. The 2026-09-17 plan combined
  the move with four creates and one policy update, and destroyed nothing.
- **STOP conditions.** A moved address planned for create, destroy or replace.
- **Known limitations.** The 2026-09-17 plan text was not retained; the move is proven by the state
  before and after. The six blocks remain in the configuration, and removing them would be a
  separate reviewed change. No retained evidence or project record shows `terraform state mv`,
  `state rm` or `state push` in use.

### Keep Terraform debug logging off

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22, 2026-09-24) for the check finding no logging variable before live plans and applies; OFFLINE-VALIDATED (2026-09-24) for the refusal when a logging variable is present |
| Published form | not executed as written (the executed checks inspected the environment inside reviewed wrappers; the `env` form is derived from them) |
| Evidence basis | Retained private evidence: the pre-apply checks of the 2026-09-22 foundation applies found no `TF_LOG` variable, and every Terraform run of the 2026-09-24 datastore plan and apply recorded the names of the variables it received, none of them a logging variable; [dev-datastore README, Debug logging](../../terraform/dev-datastore/README.md#debug-logging) |
| Authority | None |
| Cost | None |

- **Purpose.** Keep secret values out of debug logs and protocol dumps. On
  `terraform/dev-datastore` the master value passes through the provider on every plan and apply.
  The check applies to every root so it does not depend on remembering which root reads a secret.
- **Procedure.** Before every plan, apply or refresh-only plan, in the shell that will run it:

  ```
  env | grep '^TF_'
  ```

- **Expected result.** No output.
- **STOP conditions.** Any listed variable. Unset it, or open a fresh shell, and check again. The
  variables that matter most are listed in the
  [dev-datastore README](../../terraform/dev-datastore/README.md#debug-logging).
- **Known limitations.** The refusal path, a logging variable present at the start of a run, has
  been exercised offline only (2026-09-24).

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

## Hidden prerequisites

- A dedicated AWS account and its account ID, supplied as `allowed_account_id` in each root's
  untracked `terraform.tfvars`.
- An operator identity with the AdministratorAccess permission set and a local SSO profile
  ([operator-access.md](operator-access.md)).
- The state bucket name the bootstrap root created, in each root's untracked `backend.hcl`.
- Each root's other private inputs. Every plan of a root needs all of them, including plans of
  unrelated changes.
- For `terraform/dev-datastore`, a master secret that already holds its value
  ([dev-datastore.md](dev-datastore.md)).
- An approver who approves each apply, refresh-only apply, force-unlock and recovery action in
  writing, identifying the plan by its hash, and, on `terraform/dev-datastore`, every plan.
- A list of everyone with access to the state backend, and a way to reach each of them, for the
  lock check.
- The monthly budget and its notifications, created outside Terraform before the first billable
  resource. [cost-and-residue.md](cost-and-residue.md) reads them back; no creation procedure is
  published.
- A private directory outside every Git working tree for saved plans, plan JSON, logs and any
  recovery copy of state, and a private evidence location
  ([evidence-handling.md](evidence-handling.md)).
- Tools: the toolchain in [operator-access.md](operator-access.md), where Terraform 1.15.5 is the
  only exercised version. In addition: `git`, `jq`, `unzip`, and `shasum` (or `sha256sum`); bash
  or zsh, for process substitution; TFLint, run as 0.64.0; Trivy, run as 0.74.0; and network
  access to the Terraform registry for a provider install, which has no retained evidence here.
