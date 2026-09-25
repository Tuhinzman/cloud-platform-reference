# Operator Access

This runbook covers human access to the project AWS account: preparing the workstation, setting up
IAM Identity Center and the local CLI profiles, signing in, the identity and account checks that
come before AWS commands, credential lifetime and a clean shell for long operations, recovery from
an expired session or a wrong account, and the retirement of legacy IAM user credentials. Human
access runs through AWS IAM Identity Center, as decided in
[ADR-0005](../decisions/0005-adopt-centralized-identity-and-least-privilege-access.md), which holds
the reasoning, the alternatives and the boundaries. This file is the procedure only; the
[root README](../../README.md) says what the platform is and why.

It does not cover Terraform commands, locks and interrupted applies
([terraform-operations.md](terraform-operations.md)), evidence capture and redaction
([evidence-handling.md](evidence-handling.md)), or runtime windows, which create the cluster,
exercise it and destroy it at close. Runtime windows, including credential handling
inside a window, are outside this suite; [Runtime Validation](../validation/runtime-validation.md)
summarizes the windows that ran. Validation labels and the task order are in the
[runbook index](README.md).

## Normal path

Steps 1 to 4 run once; skip any whose result already exists. A new operator who has an invitation
or a one-time password from the Identity Center administrator skips step 2, does the operator part
of step 3 (a password and an MFA device), then runs step 4. Step 4's account list shows whether the
project account and both permission sets are assigned; its failure table routes anything missing
back to the administrator's part of step 3. Steps 5 to 7 come before AWS work. Steps 8 and 9 come
before a long or sensitive operation. No general rule for what counts as one is published: where a
task runbook needs an exported shell or a minimum session time, it says so, as
[dev-datastore.md](dev-datastore.md) and [cost-and-residue.md](cost-and-residue.md) do.

1. [Prepare the workstation toolchain](#prepare-the-workstation-toolchain): once per workstation.
2. [Enable Organizations and Identity Center](#enable-organizations-and-identity-center): once per
   account. Never exercised in this project.
3. [Set up an operator in Identity Center](#set-up-an-operator-in-identity-center): once per
   operator.
4. [Configure the local CLI profiles](#configure-the-local-cli-profiles): once per workstation.
5. [Sign in](#sign-in) with the profile the work needs. Its step 2 runs steps 6 and 7.
6. [Verify the resolved identity](#verify-the-resolved-identity): two values, both `True`.
7. [Check the account before AWS commands](#check-the-account-before-aws-commands):
   `ACCOUNT_MATCH=PASS`.
8. [Check session headroom before long operations](#check-session-headroom-before-long-operations):
   the credential outlives the operation.
9. [Export role credentials once](#export-role-credentials-once): a clean shell that holds one role
   credential and nothing else.

When something goes wrong:

- A read-only command fails on an expired or missing token:
  [Recover from session expiry](#recover-from-session-expiry).
- Credentials expire during a run, or a command that could have written state (an apply, a destroy
  or a state change) fails on an expired or missing token: do not re-run it;
  [Recover from credential expiry mid-run](#recover-from-credential-expiry-mid-run).
- The identity check errors or prints `False`, the account check prints `ACCOUNT_MATCH=HOLD`, or a
  mutating command already ran against another account:
  [Recover from a wrong account](#recover-from-a-wrong-account).

Once, where it applies: a human IAM user still holds an access key or a console password:
[Retire legacy IAM user credentials](#retire-legacy-iam-user-credentials).

<a id="hidden-prerequisites"></a>

## Before you start

- [ ] A dedicated AWS account for the platform. Its ID goes only into each root's untracked
  `terraform.tfvars` (a root is a Terraform root directory under `terraform/`, not the AWS root
  user), as `allowed_account_id`, and into local AWS CLI configuration; never into the repository.
- [ ] That account ID, supplied by the owner, the person accountable for the AWS account. It is
  the pin every account check compares against, so never take it from what the CLI or AWS shows
  you: not from the account list in `aws configure sso` or the access portal, and not from
  `get-caller-identity`. A pin copied from the account a profile selected compares the profile
  with itself, and the check passes in the wrong account.
- [ ] For the account check: `<root-tfvars>`, the path to the filled, untracked `terraform.tfvars`
  of the root the work targets (`terraform/bootstrap`, `terraform/foundation`, `terraform/dev` or
  `terraform/dev-datastore`). Create that file in the root's private `<inputs-dir>`, outside every
  working tree, as [terraform-operations.md](terraform-operations.md#before-you-start) sets out,
  so `<root-tfvars>` is `<inputs-dir>/terraform.tfvars`. Once
  [Initialize a root against the state backend](terraform-operations.md#initialize-a-root-against-the-state-backend)
  has copied it into `terraform/<root>`, `./terraform.tfvars` from inside that directory holds the
  same values. It sets `allowed_account_id` to the owner-supplied account ID, the account pin each
  root reads, described in the Input sections of the
  [bootstrap](../../terraform/bootstrap/README.md#input),
  [foundation](../../terraform/foundation/README.md#input) and
  [dev](../../terraform/dev/README.md#input) roots, and the inputs of the
  [dev-datastore](../../terraform/dev-datastore/README.md#what-it-creates) root.
  For work that targets no root, such as sign-in, the identity and account checks and read-backs,
  `<root-tfvars>` is the bootstrap root's `<inputs-dir>/terraform.tfvars`: copy the tracked
  `terraform/bootstrap/terraform.tfvars.example` there and set `allowed_account_id` to the
  owner-supplied account ID. Its other input, `state_bucket_name`, can wait until
  [Build the state backend and migrate into it](terraform-operations.md#build-the-state-backend-and-migrate-into-it).
  Every root pins the same account, so this file serves the account check for that work.
- [ ] An AWS Organizations management account with an IAM Identity Center organization instance
  ([Enable Organizations and Identity Center](#enable-organizations-and-identity-center)).
- [ ] For a new account only: an identity for the first Identity Center setup. In the reference
  account, the account where this project's recorded runs took place, it was the root user, and no
  other path was exercised.
- [ ] An Identity Center user for each operator, with an email address the operator can read and
  the operator's own MFA device
  ([Set up an operator in Identity Center](#set-up-an-operator-in-identity-center)).
- [ ] The two permission sets, named exactly `ReadOnlyAccess` and `AdministratorAccess`, assigned
  to the account. Their generated role-name suffixes stay out of every record.
- [ ] The Identity Center start URL and its Region, from the Identity Center administrator, and one
  SSO session name, a local label both profiles share. All three are kept only in local AWS CLI
  configuration.
- [ ] A browser on the workstation to approve the sign-in.
- [ ] The toolchain in [Prepare the workstation toolchain](#prepare-the-workstation-toolchain).
- [ ] An approver for every step that needs an explicit owner grant. An explicit owner grant is
  written approval given before the step by the person accountable for the AWS account.

**Rules for every procedure.**

> **Warning: never print the account number.** Checks print verdicts. No SSO token, authorization
> code, access key, secret key, session token, ARN or account ID goes into documentation,
> evidence, commit messages or issue text. Neither does a hash of an account ID: hashing a
> twelve-digit number does not anonymize it. The account is compared, never read off the output.

> **Warning: never test a profile with a mutating command, the ReadOnly profile included.** A
> profile can be pointed at the wrong account or resolve a wider role than intended. Resolve the
> account and the role first, with the read-only checks in steps 6 and 7 of the normal path.

- Every AWS CLI command names its profile with `--profile`, or runs inside a shell prepared by
  [Export role credentials once](#export-role-credentials-once), where no profile is configured.
  No command relies on a default profile or an inherited `AWS_PROFILE`, except the deliberate
  default-path check in [Retire legacy IAM user credentials](#retire-legacy-iam-user-credentials),
  step 6.

## Procedures

<a id="workstation-toolchain"></a>

### Prepare the workstation toolchain

**Validation:** OFFLINE-VALIDATED · **Published command form:** not executed as written

**What this does.** Prepares the workstation to run the Terraform binary and provider the recorded
applies used, and shows that the binary is HashiCorp's release. HashiCorp's signature covers the
release's checksum file, the checksum file covers the archive, and a hash comparison ties the
installed binary to the archive.

Use Terraform 1.15.5, the version recorded for the 2026-09-23 and 2026-09-24 applies.
Every root accepts `>= 1.11, < 2.0`, but later releases have not been exercised. A package manager
may now resolve a later release, so install 1.15.5 explicitly from HashiCorp's release archive. The
AWS provider `hashicorp/aws` 6.58.0 is pinned by the committed lock file in every root, and
`terraform init` checks it against that file
([Initialize a root against the state backend](terraform-operations.md#initialize-a-root-against-the-state-backend)).

**Before you start.**

- [ ] `curl`, `gpg`, `unzip` and `shasum` (`sha256sum` where `shasum` is absent) for the
  provenance check, and `bash`, `python3` and `sed` for the other checks in this runbook.
- [ ] AWS CLI version 2 with IAM Identity Center support: `aws configure sso` with an SSO session,
  `aws sso login` and `aws configure export-credentials`. The CLI version used was not recorded.
- [ ] Your platform's release suffix, `<os>_<arch>`.

**Safety and authority.** Local-only; no owner grant. A binary that fails any check below is never
run against the account.

**Steps.**

1. Download the release checksum file, its signature and the archive for your platform, and
   import HashiCorp's signing key. `<os>_<arch>` is the release's platform suffix, for example
   `darwin_arm64` or `linux_amd64`:

```
v=1.15.5; p=<os>_<arch>
base=https://releases.hashicorp.com/terraform/$v
curl -fsSO "$base/terraform_${v}_SHA256SUMS"
curl -fsSO "$base/terraform_${v}_SHA256SUMS.sig"
curl -fsSO "$base/terraform_${v}_${p}.zip"
curl -fsS https://www.hashicorp.com/.well-known/pgp-key.txt | gpg --import
```

2. Compare the key's fingerprint with the one HashiCorp publishes on its
   [security page](https://www.hashicorp.com/trust/security)
   (`C874 011F 0AB4 0511 0D02 1055 3436 5D94 72D7 468F` when this was checked), then verify the
   signature. It covers the checksum file, not the archive and not the binary.

```
gpg --fingerprint 72D7468F
gpg --verify "terraform_${v}_SHA256SUMS.sig" "terraform_${v}_SHA256SUMS"
```

3. Check the archive against the signed checksum file:

```
grep " terraform_${v}_${p}.zip\$" "terraform_${v}_SHA256SUMS" | shasum -a 256 -c
```

4. Install the `terraform` binary from the verified archive into a directory on `PATH`.
   `command -v terraform` must then resolve to this binary, not to another `terraform` earlier on
   `PATH`.
5. Tie the installed binary to that archive:

```
unzip -p "terraform_${v}_${p}.zip" terraform | shasum -a 256
shasum -a 256 "$(command -v terraform)"
terraform version
```

**Expected result.** A good signature from the key with the published fingerprint, `OK` for the
archive, equal hashes for the extracted and the installed binary, and Terraform v1.15.5.

**PASS when.**

- [ ] The key's fingerprint matches the published one, and the signature is good.
- [ ] The archive check prints `OK`.
- [ ] The extracted and the installed binary have equal hashes.
- [ ] `terraform version` reports v1.15.5.

**STOP if.**

- A different fingerprint, a bad signature, a checksum mismatch or unequal binary hashes. Do not
  run that binary against the account.

**If it fails.** No recovery procedure is published for a failed provenance check. The binary stays
unused.

**Evidence to keep.** The three results and the Terraform and provider versions, without local
paths.

**Next step.** On a new account,
[Enable Organizations and Identity Center](#enable-organizations-and-identity-center). For a new
operator, [Set up an operator in Identity Center](#set-up-an-operator-in-identity-center). With
an operator user but no local profiles,
[Configure the local CLI profiles](#configure-the-local-cli-profiles). With profiles already
configured, [Sign in](#sign-in).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | OFFLINE-VALIDATED (2026-09-24) |
| Published form | not executed as written (the executed check verified the `darwin_arm64` archive against the signed checksum file with a standard-library OpenPGP verifier, because `gpg` was not installed, and compared the extracted and installed binaries byte for byte; `gpg` and `shasum` are the conventional equivalent) |
| Evidence basis | Each root's `versions.tf` and committed `.terraform.lock.hcl`; retained private evidence of the 2026-09-24 Terraform provenance check, with three retained negative controls |
| Authority | None (local) |
| Cost | None |

**Known limitations.**

- Only `darwin_arm64` was checked.
- The recorded install came through a package-manager formula that installs the official archive,
  not directly from the archive as step 4 does, and that formula now resolves a later release.
  Installing directly from the archive has not been exercised.
- Provider binaries are checked only by `terraform init` against the lock file. The Terraform
  version is not recorded for every earlier apply.

<a id="first-time-identity-center-prerequisites"></a>

### Enable Organizations and Identity Center

**Validation:** UNEXERCISED · **Published command form:** not executed as written

**What this does.** Puts in place what
[Set up an operator in Identity Center](#set-up-an-operator-in-identity-center) assumes: AWS
Organizations and an IAM Identity Center organization instance, once per account. This project did
not perform these steps, so they are a manual prerequisite, not a validated procedure. No command
form is published; the AWS Organizations and IAM Identity Center documentation is the source for
these steps.

**Before you start.**

- [ ] The account that will hold the platform.
- [ ] An explicit owner grant for the organization and identity changes.

**Safety and authority.** Mutating and owner-authorized: organization and identity changes. Step 3
may mean a root-user session.

**Steps.** Manual and unexercised.

1. In the account that will hold the platform, enable AWS Organizations, within the scope
   [ADR-0005](../decisions/0005-adopt-centralized-identity-and-least-privilege-access.md#decision)
   sets for it.
2. Enable the IAM Identity Center organization instance with its built-in identity store. Keep
   its start URL and Region in local CLI configuration only.
3. Decide which identity performs the operator setup. No Identity Center user exists yet, and
   this project identified and exercised no path that avoids a root-user session for first-time
   setup: the reference setup ran in a root-user session, recorded and reviewed as a deviation
   from ADR-0005.

> **Warning:** Any root session is recorded and reviewed as
> [ADR-0005](../decisions/0005-adopt-centralized-identity-and-least-privilege-access.md#decision)
> requires.

**Expected result.** AWS Organizations enabled in the account, and an IAM Identity Center
organization instance with its built-in identity store. No output is published for these steps.

**PASS when.**

- [ ] AWS Organizations is enabled, within the scope ADR-0005 sets.
- [ ] The Identity Center organization instance is enabled, and its start URL and Region are only
  in local CLI configuration.
- [ ] The identity for the operator setup is decided, and any root session is recorded for review.

**STOP if.**

- The explicit owner grant for the organization and identity changes is not in place.

**If it fails.** No recovery procedure is published for these steps.

**Evidence to keep.** The record of any root session, for the review ADR-0005 requires.

**Next step.** [Set up an operator in Identity Center](#set-up-an-operator-in-identity-center).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | UNEXERCISED (never) |
| Published form | not executed as written (no command form is published; the AWS Organizations and IAM Identity Center documentation is the source for these steps) |
| Evidence basis | ADR-0005. The reference account was already an organization management account when first inventoried on 2026-08-06, and its Identity Center organization instance is first recorded on 2026-08-07; who enabled the instance is not recorded |
| Authority | Explicit owner grant (organization and identity changes) |
| Cost | None |

<a id="operator-setup-in-identity-center"></a>

### Set up an operator in Identity Center

**Validation:** EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE · **Published command form:** not executed as written

**What this does.** Gives one operator a user, MFA and two permission sets on the project account,
through console steps. It is done once per operator. Each permission set gives the operator a role
in the account, and Identity Center derives that role's name from the permission-set name.
[ADR-0005](../decisions/0005-adopt-centralized-identity-and-least-privilege-access.md#decision)
sets what each permission set serves.

**Before you start.**

- [ ] [Enable Organizations and Identity Center](#enable-organizations-and-identity-center) is
  complete.
- [ ] An identity that can administer Identity Center. The recorded setup used a root-user session;
  setup by any other identity has not been exercised. Below, the administrator is that identity
  and the operator is the person being given access.
- [ ] The operator's email address, which the operator can read, and the operator's own MFA device.
- [ ] An explicit owner grant for the identity change.

**Safety and authority.** Mutating and owner-authorized: an identity change.

> **Warning:** Any root session is recorded and reviewed as
> [ADR-0005](../decisions/0005-adopt-centralized-identity-and-least-privilege-access.md#decision)
> requires. The recorded setup ran in one.

**Steps.**

1. **Administrator.** Create the operator's user in IAM Identity Center. The user needs an email
   address. **Operator.** Set a password, from the emailed invitation or a one-time password,
   before registering MFA.
2. **Operator.** Register your own MFA device for that user. Requiring MFA at sign-in is an
   Identity Center setting for every user of the instance, not a per-user one.
3. **Administrator.** Create or select two permission sets named exactly `ReadOnlyAccess` and
   `AdministratorAccess`. Set the `AdministratorAccess` session duration to 12 hours instead of
   Identity Center's default of one hour, so that a long apply, its verification and any teardown
   finish on one exported credential. The reference account keeps `ReadOnlyAccess` at one hour.
   ADR-0005
   [defers](../decisions/0005-adopt-centralized-identity-and-least-privilege-access.md#deferred-decisions)
   the exact contents of the permission sets; what the reference account's sets are recorded to
   hold is under Recorded detail in the Engineering notes below.

> **Warning:** Use exactly these two names.
> [Verify the resolved identity](#verify-the-resolved-identity) matches the role name Identity
> Center derives from the permission-set name, so any other name fails it. It checks the name, not
> what the set grants.

4. **Administrator.** Assign the user, or a group containing the user, to the project AWS account
   with both permission sets. Give the operator the start URL and its Region, for their local CLI
   configuration.

**Expected result.** Session durations of 12 hours for `AdministratorAccess` and one hour for
`ReadOnlyAccess`, as the reference account's read-back shows. Once profiles exist, the
`AdministratorAccess` profile resolves its role in the pinned account, the account that
`allowed_account_id` names ([Verify the resolved identity](#verify-the-resolved-identity)).

**PASS when.**

- [ ] The user exists, has set a password and has registered an MFA device.
- [ ] Both permission sets exist under exactly these names, with `AdministratorAccess` at 12 hours.
- [ ] The user, or a group containing the user, is assigned to the project account with both
  permission sets.
- [ ] Once the [profiles](#configure-the-local-cli-profiles) exist,
  [Verify the resolved identity](#verify-the-resolved-identity) passes for each of them.

**STOP if.**

- The explicit owner grant for the identity change is not in place.

**If it fails.** No recovery procedure is published for the console steps. A missing assignment or
permission set shows up when the profiles are configured: the failure table in
[Configure the local CLI profiles](#configure-the-local-cli-profiles) names the causes, which
lead back to steps 3 and 4 here.

**Evidence to keep.** The record of any root session, for the review ADR-0005 requires. The start
URL, the account ID and the role-name suffixes stay out of every record.

**Next step.** [Configure the local CLI profiles](#configure-the-local-cli-profiles).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-08) |
| Published form | not executed as written (console steps; the recorded setup ran in a root-user session, and no command or console output was retained) |
| Evidence basis | ADR-0005; the 2026-08-08 setup is recorded without retained output; retained private evidence of a 2026-09-12 read-only read-back of the permission-set session durations |
| Authority | Explicit owner grant (identity change) |
| Cost | None |

**Recorded detail.** The 2026-09-12 read-back retained the session durations: 12 hours for
`AdministratorAccess` and one hour for `ReadOnlyAccess`. The retained 2026-09-23 runs resolved the
`AdministratorAccess` role in the pinned account
([Verify the resolved identity](#verify-the-resolved-identity)). The reference account's
`ReadOnlyAccess` set is recorded, from a 2026-08-08 inspection without retained output, as holding
only the AWS managed `ReadOnlyAccess` policy, with no inline policy, customer managed policy or
permissions boundary. The contents of its `AdministratorAccess` set were not recorded; ADR-0005
[defers](../decisions/0005-adopt-centralized-identity-and-least-privilege-access.md#deferred-decisions)
the exact contents of the permission sets.

**Known limitations.**

- MFA registration and enforcement rest on what was observed at sign-in. No measured check
  exists.
- Setup by an identity other than the root user has not been executed.
- Current identity configuration contains unresolved deviations from the
  [ADR-0005](../decisions/0005-adopt-centralized-identity-and-least-privilege-access.md) target
  model. Resolve those deviations before treating the identity baseline as conformant.

<a id="local-cli-profiles"></a>

### Configure the local CLI profiles

**Validation:** EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE · **Published command form:** not executed as written

**What this does.** Creates one local AWS CLI profile per permission set, `cloud-platform-readonly`
and `cloud-platform-admin`, so that elevation is explicit. Reaching for `cloud-platform-admin` is a
deliberate choice that stays visible in the command that used it, rather than a permission level
already held by default.

**Before you start.**

- [ ] [Set up an operator in Identity Center](#set-up-an-operator-in-identity-center): the user,
  its MFA device and both permission sets assigned.
- [ ] AWS CLI version 2 with IAM Identity Center support
  ([Prepare the workstation toolchain](#prepare-the-workstation-toolchain)).
- [ ] The Identity Center start URL and its Region, from the Identity Center administrator, and a
  browser on the workstation to approve the authorization.
- [ ] The account ID the owner supplied ([Before you start](#before-you-start)), to select the
  project account in step 1.

**Safety and authority.** Local-only: this writes local CLI configuration; no owner grant. The
start URL, account ID and role names belong in local configuration, not in this repository.

**Steps.**

1. Configure the two profiles. Run the commands one at a time, and finish the first one's prompts
   before starting the second:

```
aws configure sso --profile cloud-platform-readonly
aws configure sso --profile cloud-platform-admin
```

   The CLI may first ask for an SSO session name, then for the Identity Center start URL, its
   Region and the registration scope. Give both profiles the same SSO session name, the one in
   [Before you start](#before-you-start). The CLI opens a browser for authorization, then lists
   the AWS accounts and roles available to the user. Prompt order and wording differ between CLI
   versions. Set the default Region to `us-east-1`.

> **Warning:** The account list can show more than one account. For each profile, select the
> project account by matching its ID with the account ID the owner supplied, and select the
> intended permission set, deliberately.

2. Before any other command, run [Verify the resolved identity](#verify-the-resolved-identity) for
   each profile, then the [Account check](#check-the-account-before-aws-commands) for each
   profile. The identity check shows the role, not the account. The account check needs a root's
   filled `terraform.tfvars`; until it prints `ACCOUNT_MATCH=PASS`, the profile is not verified
   and nothing but the identity check runs on it.

> **Warning:** Never test a profile with a mutating command. Use only the read-only checks in this
> step.

**Expected result.** For each profile, [Verify the resolved identity](#verify-the-resolved-identity)
prints two values, both `True`, for the permission set selected, and the account check prints
`ACCOUNT_MATCH=PASS`.

**PASS when.**

- [ ] Both profiles exist, each with its own permission set, the shared SSO session name and the
  default Region `us-east-1`.
- [ ] Each profile prints `True` twice in
  [Verify the resolved identity](#verify-the-resolved-identity).
- [ ] The account check prints `ACCOUNT_MATCH=PASS` for each profile. Without it the profile is
  configured but not verified, whatever the identity check printed.

**STOP if.**

- The verification prints `False` in either position. Reconfigure the profile before running
  anything further.
- The account check prints `ACCOUNT_MATCH=HOLD`. Follow
  [Recover from a wrong account](#recover-from-a-wrong-account), part A.

**If it fails.** Match the symptom. Only the second-position case below has occurred in this
project (Engineering notes); the other rows have not been observed here.

| Symptom | Cause | What to do |
|---|---|---|
| `AWS accounts (0)` during `aws configure sso` | The user or group has no assignment to the project account. | Assign it ([Set up an operator in Identity Center](#set-up-an-operator-in-identity-center), step 4). |
| The expected permission set is missing from the role list | The permission set was never created, or it is not assigned to this user in this account. | Create or assign it ([Set up an operator in Identity Center](#set-up-an-operator-in-identity-center), steps 3 and 4). |
| The verification prints `False` in the second position | The profile was configured against a different role, and possibly a different account. | Reconfigure it before running anything further (step 1). If a mutating command already ran, follow [Recover from a wrong account](#recover-from-a-wrong-account), part B. |
| The verification prints `False` in the first position | The profile resolved an IAM user rather than a role session, or the wrong profile was named. | Name the intended profile, or reconfigure it (step 1). |

**Evidence to keep.** For each profile, the two verification values and the account verdict from
step 2.

**Next step.** [Sign in](#sign-in).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-08) |
| Published form | not executed as written (the 2026-08-08 configuration is recorded without retained output) |
| Evidence basis | The 2026-08-08 configuration and its caller-identity checks, recorded without retained output; retained private evidence from 2026-09-23 of the Administrator profile resolving the `AdministratorAccess` role in the pinned account, and from 2026-09-24 of credentials exported from it matching the pinned account |
| Authority | None (local configuration) |
| Cost | None |

**Known limitations.** A mis-selected account is the recorded failure mode: on 2026-08-08 the
first ReadOnly profile configuration selected an account other than the project account and
resolved an administrative role there
([Recover from a wrong account](#recover-from-a-wrong-account)).

### Sign in

**Validation:** AWS-VALIDATED (Administrator profile); EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (ReadOnly profile) · **Published command form:** not executed as written

**What this does.** Starts the SSO session both profiles share, through the profile the work needs,
approved in the browser.
The sign-in gives the CLI an SSO access token, which governs issuing new role credentials; a role
credential, once issued, lasts until its own expiry
([Recover from credential expiry mid-run](#recover-from-credential-expiry-mid-run) explains the two
lifetimes).

**Before you start.**

- [ ] [Configure the local CLI profiles](#configure-the-local-cli-profiles).
- [ ] A browser on the workstation to approve the sign-in.
- [ ] `<root-tfvars>` with `allowed_account_id` set to the owner-supplied account ID, for the
  account check in step 2. When the work targets no root, that is the bootstrap root's file
  ([Before you start](#before-you-start)).
- [ ] A bash shell in which you will define `account_check`
  ([Check the account before AWS commands](#check-the-account-before-aws-commands), step 1).

**Safety and authority.** Read-only; no owner grant.

**Steps.**

1. Sign in with the profile the work needs, and approve the sign-in in the browser. The
   authorization flow differs between CLI versions and was not recorded. Run only the line for the
   profile the work needs; for inspection and review, that is `cloud-platform-readonly`:

```
aws sso login --profile cloud-platform-readonly
aws sso login --profile cloud-platform-admin
```

   Both profiles share one SSO session
   ([Configure the local CLI profiles](#configure-the-local-cli-profiles), step 1), so one sign-in
   serves both. Signing in with one line does not limit which role a later command can reach; the
   `--profile` each command names decides, and that is where elevation stays explicit.

2. Run [Verify the resolved identity](#verify-the-resolved-identity) and the
   [Account check](#check-the-account-before-aws-commands) on the profile the work will use. Each
   profile selected its account separately, so one profile's `ACCOUNT_MATCH=PASS` does not cover
   the other.

**Expected result.** After the browser approval, step 2 prints two values, both `True`, and
`ACCOUNT_MATCH=PASS`. No sign-in output is published, because the authorization flow was not
recorded.

**PASS when.**

- [ ] [Verify the resolved identity](#verify-the-resolved-identity) prints `True` twice for this
  profile.
- [ ] The account check prints `ACCOUNT_MATCH=PASS`.

**STOP if.**

- Either check in step 2 does not pass. Nothing further runs.

**If it fails.** Follow [Recover from a wrong account](#recover-from-a-wrong-account), part A,
which routes each failure of the two checks. No procedure is published for a sign-in that fails
in the browser.

**Evidence to keep.** Nothing from the sign-in itself; the checks in step 2 keep their own. The SSO
token and the authorization code are never recorded.

**Next step.** Step 2 ran both checks, so continue from the Next step of
[Check the account before AWS commands](#check-the-account-before-aws-commands).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-23) for the Administrator profile; the ReadOnly profile: EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-08) |
| Published form | not executed as written (sign-in completes in the browser, and no retained output captures the command) |
| Evidence basis | Retained private evidence from 2026-09-23 of an expired SSO session and, minutes later, an `AWSReservedSSO_AdministratorAccess` role session in the pinned account; the sign-in between them is inferred, not captured. The 2026-09-24 records show only an account match on credentials exported from the Administrator profile, and capture no sign-in. The ReadOnly sign-in is recorded for 2026-08-08 without retained output |
| Authority | None |
| Cost | None |

**Known limitations.** The retained evidence covers the Administrator profile only. The retained
read-only checks since 2026-08-08 also ran on the Administrator profile rather than on ReadOnly,
whose sessions last one hour.

### Verify the resolved identity

**Validation:** AWS-VALIDATED · **Published command form:** not executed as written

**What this does.** Confirms which identity the CLI actually resolved before running anything
against AWS. A profile can be pointed at the wrong account or resolve a wider role than intended,
and the returned identity, not the profile name, shows which one is in force. The query prints two
`True` or `False` values and no identifier. It checks the role, not the account: a profile in
another account with a permission set of the same name passes it, which is why the account check
in step 2 follows.

**Before you start.**

- [ ] [Sign in](#sign-in) with the profile you intend to use, or have just authorized it in
  [Configure the local CLI profiles](#configure-the-local-cli-profiles), step 1.
- [ ] The permission set you selected for that profile: `AdministratorAccess` or `ReadOnlyAccess`.

**Safety and authority.** Read-only; no owner grant.

**Steps.**

1. Query the profile you intend to use, naming the permission set you selected
   (`AdministratorAccess` or `ReadOnlyAccess`):

```
aws sts get-caller-identity --profile <profile> \
  --query '[starts_with(UserId, `AROA`), contains(Arn, `:assumed-role/AWSReservedSSO_<permission-set>_`)]' \
  --output text
```

2. Run the [Account check](#check-the-account-before-aws-commands).

> **Warning:** Never print the account number. The account is compared, never read off the output.

**Expected result.** Two values, both `True`. The first shows a role session: a role session's
`UserId` begins with `AROA`, an IAM user's with `AIDA`. The second shows the Identity Center role
of the permission set deliberately selected.

**PASS when.**

- [ ] Both values are `True`.
- [ ] The account check in step 2 prints `ACCOUNT_MATCH=PASS`.

**STOP if.**

- An error: the session is missing or expired.
- Any `False`.

**If it fails.**

- An error: [sign in](#sign-in) again ([Recover from session expiry](#recover-from-session-expiry)).
- Any `False`: fix the profile before continuing
  ([Configure the local CLI profiles](#configure-the-local-cli-profiles)).

[Recover from a wrong account](#recover-from-a-wrong-account), part A, routes both cases.

**Evidence to keep.** The two values and the account verdict.

**Next step.** Step 2 ran the account check, so continue from the Next step of
[Check the account before AWS commands](#check-the-account-before-aws-commands).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-23) |
| Published form | not executed as written (the executed command was `aws sts get-caller-identity --profile cloud-platform-admin` without a projection, and its output was reduced before recording; the boolean projection is derived) |
| Evidence basis | Retained private evidence of the 2026-09-23 certificate plan and apply: the caller was an `AWSReservedSSO_AdministratorAccess` role session in the pinned account. The `UserId` prefix and the `ReadOnlyAccess` form are recorded for 2026-08-08 without retained output |
| Authority | None (read-only) |
| Cost | None |

**Known limitations.** The retained 2026-09-23 records carry the role name only, for
`AdministratorAccess`, and do not record `UserId`. The `UserId` prefix and the `ReadOnlyAccess`
variant are recorded only for 2026-08-08, without retained output.

<a id="account-check-before-aws-commands"></a>

### Check the account before AWS commands

**Validation:** AWS-VALIDATED (PASS verdict); OFFLINE-VALIDATED (HOLD verdict) · **Published command form:** not executed as written

**What this does.** The account check compares the account the credentials resolve with the root's
account pin, `allowed_account_id`, and prints only a verdict. It exists because each root's AWS
provider refuses any account other than `allowed_account_id`, but only when Terraform configures
the provider, as in plan and apply. Backend-only commands such as `terraform init`,
`terraform state` and `terraform force-unlock` never configure it, and AWS CLI calls are outside
Terraform, so nothing else checks the account for them.

The labels rest on a private helper this function is derived from. This function has not run
against AWS, and no retained record shows its HOLD path, offline or live (Engineering notes).

**Before you start.**

- [ ] `<root-tfvars>` exists and sets `allowed_account_id` to the account ID the owner supplied,
  as the root's Input section describes. For work that targets no root, such as sign-in and the
  identity check, it is the bootstrap root's `<inputs-dir>/terraform.tfvars`, copied from the
  tracked `terraform.tfvars.example` ([Before you start](#before-you-start)).
- [ ] [Verify the resolved identity](#verify-the-resolved-identity) passed for the profile, or you
  are inside an [exported shell](#export-role-credentials-once).
- [ ] The bash shell that will do the work.

**Safety and authority.** Read-only; no owner grant.

> **Warning: never print the account number.** The function prints only `ACCOUNT_MATCH=PASS` or
> `ACCOUNT_MATCH=HOLD`. The pin and the caller's account are compared, never printed or recorded.

**Steps.**

1. Define the check in the bash shell that will do the work. It reads the pin from
   `<root-tfvars>` and prints only a verdict:

```
account_check() {
  local pin caller
  pin=$(sed -n 's/^[[:space:]]*allowed_account_id[[:space:]]*=[[:space:]]*"\([0-9]\{12\}\)".*$/\1/p' "$1")
  caller=$(aws sts get-caller-identity "${@:2}" --query Account --output text 2>/dev/null)
  if [[ $pin =~ ^[0-9]{12}$ && $caller == "$pin" ]]; then
    echo "ACCOUNT_MATCH=PASS"
  else
    echo "ACCOUNT_MATCH=HOLD"
    return 3
  fi
}
```

2. Before commands that use a profile:

```
account_check <root-tfvars> --profile <profile>
```

3. Inside an [exported shell](#export-role-credentials-once), where no profile exists:

```
account_check <root-tfvars>
```

**Expected result.** `ACCOUNT_MATCH=PASS`.

**PASS when.**

- [ ] The check prints `ACCOUNT_MATCH=PASS`.

**STOP if.**

- `ACCOUNT_MATCH=HOLD`. A missing or malformed pin, an unavailable or malformed identity and a
  different account all hold, because none of them establishes the account; the verdict does not
  say which. Nothing further runs.

**If it fails.** Follow [Recover from a wrong account](#recover-from-a-wrong-account), part A.

**Evidence to keep.** The verdict line only.

**Next step.** Before a long operation,
[Check session headroom before long operations](#check-session-headroom-before-long-operations),
then, for a long or sensitive operation,
[Export role credentials once](#export-role-credentials-once). Otherwise continue with the work;
Terraform commands follow [terraform-operations.md](terraform-operations.md).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-24) for the PASS verdict; OFFLINE-VALIDATED (2026-09-22, 2026-09-24) for the HOLD verdict, in the private helper's qualification |
| Published form | not executed as written (derived from a private helper, not published, that compared the same caller-account query with the root's `allowed_account_id` and printed only the verdict; this function has not run against AWS) |
| Evidence basis | `allowed_account_ids` in each root's `providers.tf`; retained private evidence of the 2026-09-24 datastore plan, pre-apply gate, apply and read-back, each checked by the private helper after the export and again after the operator configuration was removed; offline qualification of the private helper's refusal paths (2026-09-22 and 2026-09-24) |
| Authority | None (read-only) |
| Cost | None |

**Known limitations.** The retained offline qualification exercised the private helper's refusal
paths, against stubbed responses, not this function: no retained record shows this function's
HOLD path, offline or live. No live HOLD has occurred. The provider's own refusal has not been
exercised against a second account.

<a id="session-headroom-before-long-operations"></a>

### Check session headroom before long operations

**Validation:** AWS-VALIDATED (measuring and proceeding); OFFLINE-VALIDATED (the HOLD); DESIGNED-NOT-EXECUTED (failure handling) · **Published command form:** not executed as written

**What this does.** Before a long operation, confirms that the credential running it outlives the
operation, its verification and any teardown, with a margin. Headroom is the time left, in minutes,
before that credential expires. A role credential cannot be extended once issued, and an exported
one is never refreshed.

The export call in step 2 is the executed form. The expiry filter and the comparison are derived
from a private helper, which printed the recorded headroom lines; the HOLD ran only offline, in
that helper's qualification (Engineering notes).

**Before you start.**

- [ ] [Sign in](#sign-in), [Verify the resolved identity](#verify-the-resolved-identity) and the
  [Account check](#check-the-account-before-aws-commands) passed.
- [ ] The operation's expected duration, from a measured run of the same operation where one
  exists.

**Safety and authority.** Read-only and secret-reading; no owner grant. Step 2 reads a live
credential's expiry without printing the credential.

**Steps.**

1. Set the requirement in minutes: the operation's expected duration, plus its verification or
   teardown, plus a margin. Where the runbook for the work states a minimum session time, use it.
   Use a measured duration of the same operation where one exists. No margin rule has been
   established; the one recorded example is in the Engineering notes below.
2. Read the expiry of the credential that will run the operation, without printing the
   credential. Inside an exported shell, use `expiry=$AWS_CREDENTIAL_EXPIRATION` instead.

> **Warning:** Keep the filter. Without it, the export call prints the live credential.

```
expiry=$(aws configure export-credentials --profile <profile> --format env | sed -n 's/^\(export \)\{0,1\}AWS_CREDENTIAL_EXPIRATION=//p')
```

3. Compare. `-I -S` keeps modules in the current directory and site hooks from loading while a
   credential may be in the environment.

```
python3 -I -S - "$expiry" <required-minutes> <<'PY'
import datetime, sys
try:
    when = datetime.datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00"))
    need = float(sys.argv[2])
except ValueError:
    sys.exit("HOLD: no usable credential expiry or requirement")
if when.tzinfo is None:
    sys.exit("HOLD: the credential expiry carries no time zone")
left = (when - datetime.datetime.now(datetime.timezone.utc)).total_seconds() / 60
print("credential headroom %.1f minute(s), %g required" % (left, need))
sys.exit(0 if left >= need else 3)
PY
```

**Expected result.** `credential headroom <n> minute(s), <required> required`, exit status 0.

**PASS when.**

- [ ] The headroom line is printed and the exit status is 0.

**STOP if.**

- Any other exit status: the expiry is missing or unreadable, or the headroom is below the
  requirement. Do not start the operation.

**If it fails.** [Sign in](#sign-in) again, export again if the work uses an exported shell
([Export role credentials once](#export-role-credentials-once)), and read the expiry again. Proceed
only on a measured value that covers the requirement. If the re-read expiry is unchanged after the
new sign-in, STOP and do not start the operation. This failure handling has never run
([Not yet exercised](#not-yet-exercised)).

**Evidence to keep.** The headroom line.

**Next step.** For a long or sensitive operation,
[Export role credentials once](#export-role-credentials-once); otherwise start the operation.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-24) for measuring and proceeding; OFFLINE-VALIDATED (2026-09-22, 2026-09-24) for the HOLD, in the private helper's qualification; DESIGNED-NOT-EXECUTED (never) for the failure handling |
| Published form | not executed as written (the `aws configure export-credentials --profile <profile> --format env` call is the executed form; the expiry filter and the comparison are derived from a private helper that printed the same headroom line) |
| Evidence basis | Retained private evidence of the headroom lines printed before the 2026-09-24 datastore plan, gate, apply and read-back; offline qualification of the private helper's shortfall detection (2026-09-22 and 2026-09-24) |
| Authority | None (read-only) |
| Cost | None |

**Recorded example.** The 2026-09-24 datastore apply required 50 minutes, a fixed allowance set
before the apply with no published breakdown; that apply then measured about six minutes of
instance creation.

**Known limitations.** A shortfall has never stopped a live operation: its detection ran only
offline, in the private helper's qualification, and the failure handling above has never run.
Whether a new sign-in replaces a cached role credential that is still valid has not been
measured, which is why only the re-read value decides.

### Export role credentials once

**Validation:** AWS-VALIDATED (passing path); OFFLINE-VALIDATED (every refusal) · **Published command form:** not executed as written

**What this does.** Prepares an exported shell: a shell that runs a long or sensitive operation on
one role credential and holds nothing else, with no operator configuration, no stray `AWS_*` or
`TF_*` variable and no default profile. Its credentials cannot change mid-run, and a failed export
leaves nothing behind.

This block is derived from a private wrapper that differed from it. The labels rest on that
wrapper, and no retained record shows this block's HOLD paths, offline or live (Engineering
notes).

**Before you start.**

- [ ] [Sign in](#sign-in), [Verify the resolved identity](#verify-the-resolved-identity) and the
  [Account check](#check-the-account-before-aws-commands) passed for the profile.
- [ ] The AWS CLI does not record command history for the profile, which would write API requests
  and responses to disk: `aws configure get cli_history --profile <profile>` prints nothing or
  `disabled`, and so does `aws configure get cli_history` for the default profile.
- [ ] The absolute path of `<root-tfvars>`.
- [ ] The grant for the work this shell will run. The shell itself needs none.

**Safety and authority.** Read-only and secret-reading: this shell holds a live role credential in
its environment. The work it prepares carries its own grant.

**Steps.**

1. Start a clean shell. Every HOLD below exits it, taking whatever it held.

```
env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc
umask 077
```

2. In this shell, define `account_check`
   ([Check the account before AWS commands](#check-the-account-before-aws-commands), step 1).
3. Export once from the profile, install only the four expected names, remove the operator's
   configuration from every later call, and check the account. Give `<root-tfvars>` as an absolute
   path, because `HOME` changes inside the block. `/var/empty` exists on macOS; elsewhere, use any
   empty directory the shell cannot write to.

> **Warning:** Paste the block as one unit: the braces make the shell read all of it before running
> any of it, so an `exit 3` cannot leave the remaining lines to the shell that started this one.
> The text is parsed, never evaluated: `eval` would run any shell syntax it carried.

```
{
  creds=$(aws configure export-credentials --profile <profile> --format env </dev/null) || exit 3
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    line=${line#export }
    case ${line%%=*} in
      AWS_ACCESS_KEY_ID | AWS_SECRET_ACCESS_KEY | AWS_SESSION_TOKEN | AWS_CREDENTIAL_EXPIRATION)
        export "$line" ;;
      *) echo "HOLD: unexpected line in the export"; exit 3 ;;
    esac
  done <<< "$creds"
  unset creds line
  [ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ] &&
    [ -n "${AWS_SESSION_TOKEN:-}" ] && [ -n "${AWS_CREDENTIAL_EXPIRATION:-}" ] ||
    { echo "HOLD: the export is incomplete"; exit 3; }
  export HOME=/var/empty AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null \
    AWS_REGION=us-east-1 AWS_DEFAULT_REGION=us-east-1 AWS_PAGER="" \
    AWS_CLI_AUTO_PROMPT=off AWS_EC2_METADATA_DISABLED=true
  account_check <root-tfvars> || exit 3
}
```

4. In this shell, run
   [Check session headroom before long operations](#check-session-headroom-before-long-operations)
   step 3 with `expiry=$AWS_CREDENTIAL_EXPIRATION`. If it does not exit 0, `exit` this shell.
5. Run the work in this shell; Terraform commands follow
   [terraform-operations.md](terraform-operations.md).

> **Warning:** Never run `set -x`, print the environment unfiltered or write these variables to a
> file.

6. Exit the shell when the work ends. The credentials end with it.

**Expected result.** `ACCOUNT_MATCH=PASS` and the headroom line, before the work starts.

**PASS when.**

- [ ] Step 3 prints `ACCOUNT_MATCH=PASS` and no HOLD line.
- [ ] Step 4 prints the headroom line and exits 0.

**STOP if.**

- The export fails, is incomplete or carries an unexpected line.
- The headroom falls short.
- The account check holds.

**If it fails.**

- The account check holds: [Recover from a wrong account](#recover-from-a-wrong-account), part A.
- The headroom falls short: the failure handling in
  [Check session headroom before long operations](#check-session-headroom-before-long-operations).
- The export fails on an expired or missing token:
  [Recover from session expiry](#recover-from-session-expiry).
- The export fails otherwise, is incomplete or carries an unexpected line: no recovery procedure
  is published.

**Evidence to keep.** The headroom line, the verdict, and the names of this shell's variables,
never their values:

```
env | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' | sort
```

**Next step.** The operation this shell was prepared for, under that operation's own grant.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-24) for the passing path; OFFLINE-VALIDATED (2026-09-22, 2026-09-24) for every refusal, in the private wrapper's qualification |
| Published form | not executed as written (derived from a private wrapper, not published, that differed as listed under Known limitations; the export call is the executed form) |
| Evidence basis | Retained private evidence of the 2026-09-24 datastore plan, gate, apply and read-back, including the recorded names of the only variables Terraform received, which come from the private wrapper's allowlist, not from this procedure; offline qualification of the private wrapper's refusal paths (2026-09-22 and 2026-09-24) |
| Authority | None; the work it prepares carries its own grant |
| Cost | None |

**Variable names.** The evidence command lists this shell's names. The names recorded for the
2026-09-24 runs are the ones Terraform received after the private wrapper reduced its environment.

**Known limitations.**

- The executed wrapper differed from this form, which reproduces none of the following. It
  started from a fixed `PATH` and ran a script, not an interactive shell, and it refused any
  `TF_*` or other unexpected variable at start. It checked each value's shape and quoting and
  refused a repeated name. It ran the account check before and after removing the operator
  configuration. It ran Terraform in a subshell whose environment was reduced to an allowlist,
  with `TF_CLI_CONFIG_FILE=/dev/null`, `CHECKPOINT_DISABLE=1` and `TF_IN_AUTOMATION=1`. Here, a
  repeated name is installed again rather than refused, and a malformed value is left to fail the
  account check.
- The retained offline qualification exercised the private wrapper's refusal paths (a failed,
  empty or incomplete export, a malformed expiry, shell syntax in a value, an extra or repeated
  name, a short expiry and the wrong account), not this block: no retained record shows this
  block's HOLD paths, offline or live. No refusal has fired live.

### Retire legacy IAM user credentials

**Validation:** EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE · **Published command form:** not executed as written

**What this does.** Retires a human IAM user's access key, meaning the access key ID and secret
access key pair an operator holds, and that user's console password. It does not cover workload
identities, CI federation or the temporary credentials Identity Center issues. Under
[ADR-0005](../decisions/0005-adopt-centralized-identity-and-least-privilege-access.md#decision),
an existing long-lived human key is retired rather than kept as a fallback.

Deactivate before you delete. Deactivation is reversible, so if something still depends on the
key you can re-enable it while you find out what. The sequence below turns an accidental fall back
to the old default credential path into an authentication failure instead of a silent success.

**Before you start.**

- [ ] An explicit owner grant for the IAM credential change.
- [ ] The legacy IAM user's name, `<legacy-user>`, and its access key ID, which stay out of every
  record.
- [ ] Working Identity Center access (step 1).
- [ ] `<root-tfvars>` for the account check in step 2 ([Before you start](#before-you-start)).

**Safety and authority.** Mutating and owner-authorized: an IAM credential change. Step 8, deleting
the key, needs its own separate approval.

**Steps.**

1. Complete [Set up an operator in Identity Center](#set-up-an-operator-in-identity-center),
   [Configure the local CLI profiles](#configure-the-local-cli-profiles) and [Sign in](#sign-in),
   so Identity Center access works.
2. Run [Verify the resolved identity](#verify-the-resolved-identity) with
   `--profile cloud-platform-admin` and `AdministratorAccess`, including its account check,
   `account_check <root-tfvars> --profile cloud-platform-admin`. Both values must be `True`, and
   the account check must print `ACCOUNT_MATCH=PASS`.
3. From that same Administrator session, deactivate the old key. Do not delete it yet. Read
   `<access-key-id>` locally and keep it out of every record:

> **Warning:** The key being retired must never be the credential that performs its own
> deactivation.

```
aws iam list-access-keys --profile cloud-platform-admin --user-name <legacy-user> \
  --query 'AccessKeyMetadata[].AccessKeyId' --output text
aws iam update-access-key --profile cloud-platform-admin --user-name <legacy-user> \
  --access-key-id <access-key-id> --status Inactive
```

4. Remove the user's console password, if it has one:

```
aws iam delete-login-profile --profile cloud-platform-admin --user-name <legacy-user>
```

5. Read both back. Every key listed must show `Inactive`; a second key is a second key to retire.
   The login profile must return `NoSuchEntity`:

```
aws iam list-access-keys --profile cloud-platform-admin --user-name <legacy-user> \
  --query 'AccessKeyMetadata[].Status' --output text
aws iam get-login-profile --profile cloud-platform-admin --user-name <legacy-user> \
  --query 'LoginProfile.CreateDate' --output text
```

6. The deliberate exception to the profile rule in [Before you start](#before-you-start): in a
   fresh shell with no profile set, the default credential path must now fail to authenticate.
   This shows something only if the retired key was what the default path resolved before step 3.
   A missing-credentials error does not prove deactivation; step 5 is the proof of the key's
   status.

```
aws sts get-caller-identity --query 'starts_with(UserId, `AROA`)' --output text
```

7. In that same shell, step 2 must still return both values `True`.
8. Delete the key only after steps 6 and 7 pass, and only as a separately approved cleanup step
   ([Not yet exercised](#not-yet-exercised)).

**Expected result.** Every key listed shows `Inactive`, the login profile returns `NoSuchEntity`,
the default credential path fails to authenticate, and the Administrator profile still returns both
values `True`. A key counts as removed once its deletion has been verified. Until then it is
deactivated, and deactivated is what the evidence supports.

**PASS when.**

- [ ] Step 5: every key `Inactive`, and `NoSuchEntity` for the login profile.
- [ ] Step 6: the default credential path fails to authenticate.
- [ ] Step 7: both values `True`.

**STOP if.**

- The explicit owner grant for the IAM credential change is not in place.
- Step 2 does not return both values `True` and `ACCOUNT_MATCH=PASS`. Nothing is deactivated from
  that session.
- Step 5 shows any key that is not `Inactive`, or step 6 still authenticates. Do not go on to
  step 8.

**If it fails.** A check in step 2 fails:
[Recover from a wrong account](#recover-from-a-wrong-account), part A. If something still depends
on the key, re-enable it while you find out what: deactivation is reversible. No other recovery
procedure is published.

**Evidence to keep.** The outcomes of steps 5 to 7. The user name and the access key ID stay out of
every record.

**Next step.** Deleting the key, and resolving the identity configuration's other deviations from
ADR-0005, each need a separate owner grant.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-08) |
| Published form | not executed as written (the deactivation and login-removal commands were not retained; the commands here come from the AWS CLI reference) |
| Evidence basis | The 2026-08-08 key deactivation from the Administrator session, the closed default credential path and the console-login removal, recorded without retained output |
| Authority | Explicit owner grant (IAM credential change) |
| Cost | None |

**Recorded run.** Recorded on 2026-08-08: the key was set to `Inactive` from the Administrator
session; a shell with no profile no longer authenticated; the login profile was removed, and the
Administrator path still resolved as a role session afterwards. That last check is recorded after
the login removal, not separately after the deactivation. The commands used were not retained. The
refusal text of the recorded run's step 6 was not retained.

**Known limitations.** A working Identity Center session shows that short-lived operator access is
available. It does not show that every long-lived IAM access key in the account has been removed,
which needs its own evidence. In the reference account the key is deactivated, not deleted.

<a id="session-expiry"></a>

### Recover from session expiry

**Validation:** AWS-VALIDATED (steps 1 and 3); DESIGNED-NOT-EXECUTED (step 2) · **Published command form:** not executed as written

**What this does.** Restores access when a command fails because the SSO session has expired or is
missing: sign in again, replace any exported shell, and repeat the identity and account checks.

It is for a command that could not have written state. If the failed command was an apply, a
destroy or a state change, or it failed partway through a run, do not re-run it: use
[Recover from credential expiry mid-run](#recover-from-credential-expiry-mid-run) instead.

**Before you start.**

- [ ] The name of the profile in use.

**Safety and authority.** Read-only and secret-reading (step 2 exports again); no owner grant.

**Steps.**

> **Warning:** Do not re-run a command that wrote state: a lock or a partially applied change may
> remain.

1. When a command fails with an expired or missing token, [sign in](#sign-in) again with the
   profile in use.
2. Credentials already exported into a shell keep their original expiry; a new sign-in does not
   extend them. Exit that shell and [export again](#export-role-credentials-once).
3. Run [Verify the resolved identity](#verify-the-resolved-identity) and the
   [Account check](#check-the-account-before-aws-commands) before the next AWS command.

**Expected result.** After step 3, both verification values `True` and `ACCOUNT_MATCH=PASS`.

**PASS when.**

- [ ] Step 3: both values `True` and `ACCOUNT_MATCH=PASS`.

**STOP if.**

- The failed command was an apply, a destroy or a state change, or it failed partway through a
  run. Do not re-run it; use
  [Recover from credential expiry mid-run](#recover-from-credential-expiry-mid-run).
- A check in step 3 does not pass. Nothing further runs.

**If it fails.** Follow [Recover from a wrong account](#recover-from-a-wrong-account), part A. If
the credential expired while a command was running, follow
[Recover from credential expiry mid-run](#recover-from-credential-expiry-mid-run) instead.

**Evidence to keep.** The two verification values and the account verdict.

**Next step.** Return to the procedure that failed.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-23) for steps 1 and 3; DESIGNED-NOT-EXECUTED (never) for step 2 |
| Published form | not executed as written (the sign-in is not captured in retained output; the retained record shows the expired session before it and a working session after it) |
| Evidence basis | Retained private evidence from 2026-09-23 of an expired SSO token and an expired cached role credential, read from the local credential cache without an AWS call, followed minutes later by an Administrator session in the pinned account. A command failing on an expired token is recorded for 2026-09-07 without retained output |
| Authority | None |
| Cost | None |

**Known limitations.** The retained 2026-09-23 record detected the expiry from the credential
cache, not from a failed command. No recorded run has replaced exported credentials after a new
sign-in (step 2, [Not yet exercised](#not-yet-exercised)). Step 3 rests on the separately
validated checks.

<a id="credential-expiry-mid-run"></a>

### Recover from credential expiry mid-run

**Validation:** DESIGNED-NOT-EXECUTED · **Published command form:** not executed as written

**What this does.** Handles a run that fails because a credential lifetime ran out. Two lifetimes
are in play. The SSO access token from the browser sign-in governs issuing new role credentials. A
role credential, once issued, lasts until its own expiry, 12 hours for Administrator, whatever
happens to the token. In the one recorded case, AWS CLI calls kept working while Terraform's S3
backend failed with `InvalidGrantException` (Engineering notes).

What happens in a shell whose exported credential expires mid-run has not been observed in this
project.
[Check session headroom before long operations](#check-session-headroom-before-long-operations) is
what keeps this from happening.

**Before you start.**

- [ ] The operator's normal shell, for step 2.
- [ ] The shell that failed, if the run used an exported shell.

**Safety and authority.** Read-only and secret-reading for steps 1 to 4; no owner grant.
Recovering an interrupted write carries its own grant. An interrupted apply can leave billable
resources running.

**Steps.**

1. Stop. Do not re-run the failed command or start another.
2. In the operator's normal shell, read both lifetimes without printing any credential. First the
   SSO token expiry, reading only `expiresAt` from the AWS CLI's SSO token cache. `<sso-cache-dir>`
   is that cache directory: `sso/cache` inside the CLI's configuration directory.

```
python3 -I -S - <sso-cache-dir> <<'PY'
import glob, json, os, sys
for path in sorted(glob.glob(os.path.join(sys.argv[1], "*.json"))):
    with open(path) as f:
        entry = json.load(f)
    if "accessToken" in entry:
        print("SSO token expiresAt", entry.get("expiresAt"))
PY
```

   Then the role credential expiry, as in step 2 of
   [Check session headroom before long operations](#check-session-headroom-before-long-operations),
   or `$AWS_CREDENTIAL_EXPIRATION` in the shell that failed.

   With more than one cached SSO session, for example another organization's, this step prints
   one expiry per session, and its output cannot tie a line to the project session. Telling them
   apart means reading each entry's start URL locally, without recording it.
3. [Sign in](#sign-in) again. If the run used an exported shell, exit it and
   [export again](#export-role-credentials-once).
4. Run [Verify the resolved identity](#verify-the-resolved-identity) and the
   [Account check](#check-the-account-before-aws-commands).
5. If the interrupted command wrote state (an apply, a destroy or a state change), follow
   [Stop after a failed or interrupted apply](terraform-operations.md#stop-after-a-failed-or-interrupted-apply).
   A read-only command can simply be re-run.

> **Warning:** Do not re-run a command that wrote state: a lock or a partially applied change may
> remain.

**Expected result.** After step 4, both verification values `True` and `ACCOUNT_MATCH=PASS`.

**PASS when.**

- [ ] Step 4: both values `True` and `ACCOUNT_MATCH=PASS`.
- [ ] An interrupted write is handed to the interrupted-apply procedure, not re-run.

**STOP if.**

- A check in step 4 does not pass. Nothing further runs.

**If it fails.** A check in step 4: [Recover from a wrong account](#recover-from-a-wrong-account),
part A. An interrupted write:
[Stop after a failed or interrupted apply](terraform-operations.md#stop-after-a-failed-or-interrupted-apply).
It was never demonstrated that a new sign-in restores the backend.

**Evidence to keep.** The two verification values and the account verdict from step 4. No cached
session's start URL is recorded.

**Next step.** Re-run a read-only command, or continue a write in
[Stop after a failed or interrupted apply](terraform-operations.md#stop-after-a-failed-or-interrupted-apply).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | DESIGNED-NOT-EXECUTED (never) |
| Published form | not executed as written (derived; of these steps, only the lifetime reads in step 2 ran, once, read-only, on 2026-09-12) |
| Evidence basis | Retained private evidence of the 2026-09-12 read-only diagnosis: an expired SSO token beside a still-valid 12-hour role credential. The backend failure it explained is recorded in narrative only, with no raw capture |
| Authority | None for steps 1 to 4; recovering an interrupted write carries its own grant |
| Cost | None directly; an interrupted apply can leave billable resources running |

**Recorded case.** Once, on 2026-09-11 and 2026-09-12, with the token expired, AWS CLI calls
through the profile kept working on the cached role credential while Terraform's S3 backend failed
with `InvalidGrantException`. That failure was recorded without raw output, and the recorded
interpretation is that the backend tried to refresh the token.

**Known limitations.** The response has never run as a whole, and it was never demonstrated that a
new sign-in restores the backend.

<a id="wrong-account-response"></a>

### Recover from a wrong account

**Validation:** DESIGNED-NOT-EXECUTED (part A); EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (part B) · **Published command form:** not executed as written

**What this does.** Handles two cases. In part A, the identity or account check failed before any
mutating command ran, so nothing changed: find the cause and fix it. In part B, a mutating command
already ran against another account: stop, find and remove what it created, and prove the removal.

**Before you start.**

- [ ] For part B: an explicit grant from the owner of the affected account before any cleanup.

**Safety and authority.** Part A is read-only and needs no grant. Part B is mutating, destructive
and owner-authorized: it deletes what the command created in the affected account. Cost: none
expected; it depends on what the command created.

> **Warning:** Resolve the account and the role before any mutating command, never probe a
> profile's permissions with a mutating command, and never put a mutating command in the same
> block as an unresolved account or role check. This is the lesson the recorded case carries.

**Steps.**

**Part A. The identity or account check failed before any mutating command ran.**

1. Stop. No mutating command ran.
2. Exit any exported shell.
3. Find the cause with the existing checks, in the operator's normal shell:
   - [Verify the resolved identity](#verify-the-resolved-identity) returns an error: the session
     is missing or expired. [Sign in](#sign-in) again
     ([Recover from session expiry](#recover-from-session-expiry)).
   - It prints `False`: the profile resolves the wrong principal or role. Reconfigure it
     ([Configure the local CLI profiles](#configure-the-local-cli-profiles)).
   - It prints both values `True`, but the
     [Account check](#check-the-account-before-aws-commands) holds: the pin is missing, malformed
     or wrong (a typo, or another account's ID), or the profile resolves another account. Check
     `<root-tfvars>` against the root's Input section ([Before you start](#before-you-start)), and
     re-confirm the pin's value with the owner, who supplies it. Never change the pin to match the
     profile: a pin taken from the profile compares the profile with itself. Once the owner has
     confirmed the pin, reconfigure the profile against the project account, selected by that ID
     ([Configure the local CLI profiles](#configure-the-local-cli-profiles)).
4. Repeat [Verify the resolved identity](#verify-the-resolved-identity) and the
   [Account check](#check-the-account-before-aws-commands). Both must pass before anything else
   runs.

**Part B. A mutating command already ran against another account.**

1. Stop every further command.
2. From the same profile, list what the command created or changed, rather than relying on the
   command's own response. The only exercised case is an IAM user created by a known command; no
   method is published or exercised for finding what an arbitrary command changed in another
   account ([Not yet exercised](#not-yet-exercised)).
3. Remove what it created, under the grant above.

> **Warning:** Before deleting an IAM principal, confirm that no access keys, policies or groups
> remain attached to it.

4. Re-query each removed resource and confirm it is absent, a not-found error rather than an
   access-denied one, instead of trusting the delete call.
5. Record what happened without the other account's identifier.
6. Continue with part A, steps 3 and 4.

**Expected result.** Part A: after step 4, both identity values `True` and `ACCOUNT_MATCH=PASS`.
Part B: each removed resource returns a not-found error, not an access-denied one, when
re-queried.

**PASS when.**

- [ ] Part A, step 4: both values `True` and `ACCOUNT_MATCH=PASS`.
- [ ] Part B: what the command created is removed under the grant, each absence is confirmed by a
  not-found error, and the record carries no identifier of the other account.

**STOP if.**

- Part A, step 4: either check still fails. Nothing else runs.
- Part B: the grant from the owner of the affected account is not in place. No cleanup runs.

**If it fails.** No further procedure is published. In particular, no method is published or
exercised for finding what an arbitrary command changed in another account. If part A's account
check still holds after the owner has confirmed the pin and the profile has been reconfigured, the
work stays stopped until a reviewed decision is taken under the owner's explicit approval, as for
any HOLD without a resume procedure ([When something fails](README.md#when-something-fails)).

**Evidence to keep.** Part A: the two identity values and the account verdict. Part B: the record
of what happened, without the other account's identifier.

**Next step.** Once part A, step 4 passes, return to the procedure that stopped.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | Part B: EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-08). Part A: DESIGNED-NOT-EXECUTED (never) |
| Published form | not executed as written (generic steps derived from the one recorded response; no command was retained) |
| Evidence basis | The recorded 2026-08-08 response (part B), without retained output; offline qualification of the private helper's account refusal, which part A depends on |
| Authority | None for part A; for part B, an explicit grant from the owner of the affected account before any cleanup |
| Cost | None expected; depends on what the command created |

**Recorded case.** Part B ran once, on 2026-08-08. A mutating probe, run through a profile that had
resolved an administrative role in an account other than the project account, created an IAM user
there. The user was deleted with nothing attached, its absence was re-queried, nothing billable
was created and the project account was not affected. No output was retained. Part A has never
run; the refusal it depends on has fired only in offline qualification of the private helper.

## Not yet exercised

| Item | Status |
|---|---|
| [Enable Organizations and Identity Center](#enable-organizations-and-identity-center): enabling AWS Organizations and the Identity Center organization instance | UNEXERCISED |
| [Set up an operator in Identity Center](#set-up-an-operator-in-identity-center) run by an identity other than the root user | DESIGNED-NOT-EXECUTED |
| A measured check that MFA is required at sign-in | UNEXERCISED |
| [Recover from a wrong account](#recover-from-a-wrong-account), part A; the account refusal it depends on was qualified only offline, in a private helper | DESIGNED-NOT-EXECUTED |
| Finding what an arbitrary command changed in another account ([Recover from a wrong account](#recover-from-a-wrong-account), part B, step 2) | UNEXERCISED |
| Replacing an exported shell after a new sign-in ([Recover from session expiry](#recover-from-session-expiry), step 2) | DESIGNED-NOT-EXECUTED |
| Recovering from a headroom shortfall: sign in again, export again, re-measure ([Check session headroom before long operations](#check-session-headroom-before-long-operations), failure handling) | DESIGNED-NOT-EXECUTED |
| Obtaining a new role credential while a cached one is still valid | UNEXERCISED |
| [Recover from credential expiry mid-run](#recover-from-credential-expiry-mid-run) | DESIGNED-NOT-EXECUTED |
| The provider's `allowed_account_ids` refusal against a real second account | UNEXERCISED |
| Deleting the deactivated legacy access key and verifying its absence | UNEXERCISED |
| Resolving the identity configuration's deviations from the ADR-0005 target model | UNEXERCISED |
| Break-glass recovery through the account root user ([ADR-0005](../decisions/0005-adopt-centralized-identity-and-least-privilege-access.md#decision)) | UNEXERCISED |
| Verifying the root posture: MFA enabled and no root access keys | UNEXERCISED |
| Revoking operator access: removing the assignment and the user, signing out, and removing local profiles and the SSO cache | UNEXERCISED |
| Access review after privileged or break-glass use and at milestones; the only record is the review of the 2026-08-08 root session | UNEXERCISED |
| Replacing a lost operator MFA device | UNEXERCISED |
| Signing out at the end of work (`aws sso logout`) | UNEXERCISED |

## Reproducibility gaps

What a new engineer cannot reproduce from the public repositories today, the public contract that
does exist, and whether a new public procedure or tool is needed later.

- **The executed export wrapper.**
  - Cannot be reproduced: the controls of the private wrapper the 2026-09-24 runs used. The
    published block reproduces none of them; they are listed in the Engineering notes of
    [Export role credentials once](#export-role-credentials-once).
  - Public contract: the published block, whose export call is the executed form, and the
    variable-name listing kept as evidence.
  - Needed later: a public tool, if the executed controls are to be reproduced. Until then the
    published block is the contract.
- **The executed account check and headroom comparison.**
  - Cannot be reproduced: the private helper that produced the recorded verdicts and headroom
    lines. The published `account_check` function has not run against AWS, and the published
    expiry filter and comparison are derived from the helper.
  - Public contract: the function in
    [Check the account before AWS commands](#check-the-account-before-aws-commands), the expiry
    read and comparison in
    [Check session headroom before long operations](#check-session-headroom-before-long-operations),
    and `allowed_account_ids` in each root's `providers.tf`.
  - Needed later: no new tool; a recorded run of the published forms against the account.
- **The refusal paths.**
  - Cannot be reproduced: the offline qualification that exercised the private helper's refusal
    paths against stubbed responses, and the private wrapper's refusal paths. No retained record
    shows the published function's or block's HOLD paths, offline or live, and a headroom
    shortfall was detected only in the private helper's qualification.
  - Public contract: the HOLD and STOP conditions each procedure documents.
  - Needed later: a public offline qualification of the published forms.
- **When to export, and how much headroom.**
  - Cannot be reproduced: a general rule for what counts as a long or sensitive operation, or for
    the headroom margin. No margin rule has been established.
  - Public contract: the exported-shell and session-time requirements the task runbooks state,
    and the check in
    [Check session headroom before long operations](#check-session-headroom-before-long-operations).
  - Needed later: no tool; a stated rule, if one is decided.
- **Identity Center setup.**
  - Cannot be reproduced: enabling AWS Organizations and the Identity Center instance, which this
    project never performed, and the operator setup, which ran as console steps in a root-user
    session with no command or console output retained. Setup by any other identity has not been
    exercised.
  - Public contract: ADR-0005, the manual, unexercised outline in
    [Enable Organizations and Identity Center](#enable-organizations-and-identity-center) (AWS
    documentation is the source), the console steps in
    [Set up an operator in Identity Center](#set-up-an-operator-in-identity-center), and the exact
    permission-set names and session durations.
  - Needed later: an exercised setup procedure, including a path that avoids a root-user session
    if one is identified. No tool is named for it.
- **Permission-set contents.**
  - Cannot be reproduced: the contents of the `AdministratorAccess` set, which were not recorded.
    The `ReadOnlyAccess` contents are recorded without retained output.
  - Public contract: the two names, the session durations, and ADR-0005, which defers the exact
    contents.
  - Needed later: the deferred ADR-0005 decision on the contents.
- **MFA enforcement.**
  - Cannot be reproduced: a measured check that MFA is required at sign-in. None exists.
  - Public contract: step 2 of
    [Set up an operator in Identity Center](#set-up-an-operator-in-identity-center), an
    instance-wide Identity Center setting.
  - Needed later: a measured check ([Not yet exercised](#not-yet-exercised)).
- **Toolchain versions and platforms.**
  - Cannot be reproduced: the AWS CLI version used, which was not recorded, and the Terraform
    version of every earlier apply. Only `darwin_arm64` was checked, and a direct install from the
    archive has not been exercised.
  - Public contract: Terraform 1.15.5 and its provenance check, each root's `versions.tf`, and the
    committed `.terraform.lock.hcl` pinning `hashicorp/aws` 6.58.0.
  - Needed later: no new tool; the published check run on another platform and from a direct
    archive install.
- **What a command changed in another account.**
  - Cannot be reproduced: finding what an arbitrary command changed in another account. The only
    exercised case is an IAM user created by a known command.
  - Public contract: [Recover from a wrong account](#recover-from-a-wrong-account), part B.
  - Needed later: a new public procedure.
- **Operator access after setup.**
  - Cannot be reproduced: revoking operator access, replacing a lost MFA device, break-glass
    recovery through the root user, verifying the root posture, access review and signing out.
    None has a published procedure.
  - Public contract: ADR-0005 for break-glass recovery; the items in
    [Not yet exercised](#not-yet-exercised).
  - Needed later: new public procedures.
- **Retained evidence.**
  - Cannot be reproduced: inspection of the evidence behind each label, which is private.
  - Public contract: the labels, the evidence-basis rows and the verdict formats in this file;
    [Public and private evidence](evidence-handling.md#public-and-private-evidence).
  - Needed later: none; raw evidence stays private.

## Background prerequisites

- The root user's credentials and MFA device, held for recovery.
- For key retirement only: the legacy IAM user's name and its access key ID, which stay out of
  every record.
