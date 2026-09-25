# Operator Access

## Scope

This runbook owns human access to the project AWS account: the workstation toolchain, the IAM
Identity Center setup and local CLI profiles, sign-in, the identity and account checks that come
before AWS commands, credential lifetime and hygiene, the response to work that reached the wrong
account, and the retirement of legacy IAM user credentials.

Human access runs through AWS IAM Identity Center, as decided in
[ADR-0005](../decisions/0005-adopt-centralized-identity-and-least-privilege-access.md), which
holds the reasoning, the alternatives and the boundaries. This file is the procedure only.

Linked, not repeated here:

- `allowed_account_id`, the account pin each root reads from its untracked `terraform.tfvars`: the
  Input sections of the [bootstrap](../../terraform/bootstrap/README.md#input),
  [foundation](../../terraform/foundation/README.md#input) and
  [dev](../../terraform/dev/README.md#input) roots, and the inputs of the
  [dev-datastore](../../terraform/dev-datastore/README.md#what-it-creates) root.
- Terraform commands, locks and interrupted applies: [terraform-operations.md](terraform-operations.md).
- Evidence capture and redaction: [evidence-handling.md](evidence-handling.md).
- Validation labels and the task order: the [runbook index](README.md).
- Runtime windows, including credential handling inside a window, are outside this suite.
  [Runtime Validation](../validation/runtime-validation.md) summarizes the windows that ran.

Conventions for every procedure below:

- Every AWS CLI command names its profile with `--profile`, or runs inside a shell prepared by
  [Export role credentials once](#export-role-credentials-once), where no profile is configured.
  No command relies on a default profile or an inherited `AWS_PROFILE`, except the deliberate
  default-path check in [Retire legacy IAM user credentials](#retire-legacy-iam-user-credentials),
  step 6.
- No SSO token, authorization code, access key, secret key, session token, ARN or account ID goes
  into documentation, evidence, commit messages or issue text. Neither does a hash of an account
  ID: hashing a twelve-digit number does not anonymize it. Checks print verdicts.
- `<root-tfvars>` is the path to the filled, untracked `terraform.tfvars` of the root the work
  targets (`terraform/bootstrap`, `terraform/foundation`, `terraform/dev` or
  `terraform/dev-datastore`): `./terraform.tfvars` from inside `terraform/<root>`, or the copy
  kept outside the repository ([terraform-operations.md](terraform-operations.md)).
- An explicit owner grant, where an Authority row names one, is written approval given before the
  step by the person accountable for the AWS account.

## Procedures

### Workstation toolchain

| Field | Value |
|---|---|
| Validation status | OFFLINE-VALIDATED (2026-09-24) |
| Published form | not executed as written (the executed check verified the `darwin_arm64` archive against the signed checksum file with a standard-library OpenPGP verifier, because `gpg` was not installed, and compared the extracted and installed binaries byte for byte; `gpg` and `shasum` are the conventional equivalent) |
| Evidence basis | Each root's `versions.tf` and committed `.terraform.lock.hcl`; retained private evidence of the 2026-09-24 Terraform provenance check, with three retained negative controls |
| Authority | None (local) |
| Cost | None |

**Purpose.** Run the Terraform binary and provider the recorded applies used, and show that the
binary is HashiCorp's release.

**Inputs.**

- Terraform 1.15.5, the version recorded for the 2026-09-23 and 2026-09-24 applies. Every root
  accepts `>= 1.11, < 2.0`, but later releases have not been exercised. A package manager may now
  resolve a later release, so install 1.15.5 explicitly from HashiCorp's release archive.
- The AWS provider `hashicorp/aws` 6.58.0, pinned by the committed lock file in every root.
  `terraform init` checks it against that file ([terraform-operations.md](terraform-operations.md)).
- AWS CLI version 2 with IAM Identity Center support: `aws configure sso` with an SSO session,
  `aws sso login` and `aws configure export-credentials`. The CLI version used was not recorded.
- `bash`, `python3` and `sed` for the checks in this file; `curl`, `gpg`, `unzip` and `shasum`
  (`sha256sum` where `shasum` is absent) for the provenance check.

**Procedure.**

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
5. Tie the installed binary to that archive:

```
unzip -p "terraform_${v}_${p}.zip" terraform | shasum -a 256
shasum -a 256 "$(command -v terraform)"
terraform version
```

**Expected result.** A good signature from the key with the published fingerprint, `OK` for the
archive, equal hashes for the extracted and the installed binary, and Terraform v1.15.5.

**Evidence to retain.** The three results and the Terraform and provider versions, without local
paths.

**STOP conditions.** A different fingerprint, a bad signature, a checksum mismatch or unequal
binary hashes. Do not run that binary against the account.

**Known limitations.**

- Only `darwin_arm64` was checked.
- The recorded install came through a package-manager formula that installs the official archive,
  not directly from the archive as step 4 does, and that formula now resolves a later release.
  Installing directly from the archive has not been exercised.
- Provider binaries are checked only by `terraform init` against the lock file. The Terraform
  version is not recorded for every earlier apply.

### First-time Identity Center prerequisites

| Field | Value |
|---|---|
| Validation status | UNEXERCISED (never) |
| Published form | not executed as written (no command form is published; the AWS Organizations and IAM Identity Center documentation is the source for these steps) |
| Evidence basis | ADR-0005. The reference account was already an organization management account when first inventoried on 2026-08-06, and its Identity Center organization instance is first recorded on 2026-08-07; who enabled the instance is not recorded |
| Authority | Explicit owner grant (organization and identity changes) |
| Cost | None |

**Purpose.** Put in place what [Operator setup in Identity Center](#operator-setup-in-identity-center)
assumes. This project did not perform these steps, so they are a manual prerequisite, not a
validated procedure.

**Prerequisite steps (manual, unexercised).**

1. In the account that will hold the platform, enable AWS Organizations, within the scope
   [ADR-0005](../decisions/0005-adopt-centralized-identity-and-least-privilege-access.md#decision)
   sets for it.
2. Enable the IAM Identity Center organization instance with its built-in identity store. Keep
   its start URL and Region in local CLI configuration only.
3. Decide which identity performs the operator setup. No Identity Center user exists yet, and
   this project identified and exercised no path that avoids a root-user session for first-time
   setup: the reference setup ran in a root-user session, recorded and reviewed as a deviation
   from ADR-0005. Any root session is recorded and reviewed as
   [ADR-0005](../decisions/0005-adopt-centralized-identity-and-least-privilege-access.md#decision)
   requires.

### Operator setup in Identity Center

| Field | Value |
|---|---|
| Validation status | EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-08) |
| Published form | not executed as written (console steps; the recorded setup ran in a root-user session, and no command or console output was retained) |
| Evidence basis | ADR-0005; the 2026-08-08 setup is recorded without retained output; retained private evidence of a 2026-09-12 read-only read-back of the permission-set session durations |
| Authority | Explicit owner grant (identity change) |
| Cost | None |

**Purpose.** Give one operator a user, MFA and two permission sets on the project account. Done
once per operator.

**Preconditions.**

- [First-time Identity Center prerequisites](#first-time-identity-center-prerequisites).
- An identity that can administer Identity Center. The recorded setup used a root-user session;
  setup by any other identity has not been exercised.

**Procedure.**

1. Create the operator's user in IAM Identity Center. The user needs an email address, and sets a
   password, from the emailed invitation or a one-time password, before registering MFA.
2. Register an MFA device for that user. Requiring MFA at sign-in is an Identity Center setting
   for every user of the instance, not a per-user one.
3. Create or select two permission sets named exactly `ReadOnlyAccess` and `AdministratorAccess`.
   [Verify the resolved identity](#verify-the-resolved-identity) matches the role name Identity
   Center derives from the permission-set name, so any other name fails it.
   [ADR-0005](../decisions/0005-adopt-centralized-identity-and-least-privilege-access.md#decision)
   sets what each serves. Set the `AdministratorAccess` session duration to 12 hours instead of
   Identity Center's default of one hour, so that a long apply, its verification and any teardown
   finish on one exported credential. The reference account keeps `ReadOnlyAccess` at one hour.
   Its `ReadOnlyAccess` set is recorded, from a 2026-08-08 inspection without retained output, as
   holding only the AWS managed `ReadOnlyAccess` policy, with no inline policy, customer managed
   policy or permissions boundary. The contents of its `AdministratorAccess` set were not
   recorded; ADR-0005
   [defers](../decisions/0005-adopt-centralized-identity-and-least-privilege-access.md#deferred-decisions)
   the exact contents of the permission sets.
4. Assign the user, or a group containing the user, to the project AWS account with both
   permission sets.

**Validation.** The 2026-09-12 read-back retained the session durations: 12 hours for
`AdministratorAccess` and one hour for `ReadOnlyAccess`. The retained 2026-09-23 runs resolved
the `AdministratorAccess` role in the pinned account
([Verify the resolved identity](#verify-the-resolved-identity)).

**Known limitations.**

- MFA registration and enforcement rest on what was observed at sign-in. No measured check
  exists.
- Setup by an identity other than the root user has not been executed.
- Current identity configuration contains unresolved deviations from the
  [ADR-0005](../decisions/0005-adopt-centralized-identity-and-least-privilege-access.md) target
  model. Resolve those deviations before treating the identity baseline as conformant.

### Local CLI profiles

| Field | Value |
|---|---|
| Validation status | EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-08) |
| Published form | not executed as written (the 2026-08-08 configuration is recorded without retained output) |
| Evidence basis | The 2026-08-08 configuration and its caller-identity checks, recorded without retained output; retained private evidence from 2026-09-23 of the Administrator profile resolving the `AdministratorAccess` role in the pinned account, and from 2026-09-24 of credentials exported from it matching the pinned account |
| Authority | None (local configuration) |
| Cost | None |

**Purpose.** One local profile per permission set, so that elevation is explicit. Reaching for
`cloud-platform-admin` is a deliberate choice that stays visible in the command that used it,
rather than a permission level already held by default.

**Procedure.**

1. Configure the two profiles:

```
aws configure sso --profile cloud-platform-readonly
aws configure sso --profile cloud-platform-admin
```

   The CLI may first ask for an SSO session name, then for the Identity Center start URL, its
   Region and the registration scope. It opens a browser for authorization, then lists the AWS
   accounts and roles available to the user. That list can show more than one account: select the
   project account and the intended permission set deliberately for each profile. Prompt order and
   wording differ between CLI versions. Set the default Region to `us-east-1`. The start URL,
   account ID and role names belong in local configuration, not in this repository.
2. Before any other command, run [Verify the resolved identity](#verify-the-resolved-identity) for
   each profile, and the [Account check](#account-check-before-aws-commands) once a root's filled
   `terraform.tfvars` exists. Never test a profile with a mutating command.

**Failure handling.** Only the second-position case below has occurred in this project (Known
limitations); the other rows have not been observed here.

| Symptom | Cause |
|---|---|
| `AWS accounts (0)` during `aws configure sso` | The user or group has no assignment to the project account. |
| The expected permission set is missing from the role list | The permission set was never created, or it is not assigned to this user in this account. |
| The verification prints `False` in the second position | The profile was configured against a different role, and possibly a different account. Reconfigure it before running anything further. |
| The verification prints `False` in the first position | The profile resolved an IAM user rather than a role session, or the wrong profile was named. |

**Known limitations.** A mis-selected account is the recorded failure mode: on 2026-08-08 the
first ReadOnly profile configuration selected an account other than the project account and
resolved an administrative role there ([Wrong-account response](#wrong-account-response)).

### Sign in

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-23) for the Administrator profile; the ReadOnly profile: EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-08) |
| Published form | not executed as written (sign-in completes in the browser, and no retained output captures the command) |
| Evidence basis | Retained private evidence from 2026-09-23 of an expired SSO session and, minutes later, an `AWSReservedSSO_AdministratorAccess` role session in the pinned account; the sign-in between them is inferred, not captured. The 2026-09-24 records show only an account match on credentials exported from the Administrator profile, and capture no sign-in. The ReadOnly sign-in is recorded for 2026-08-08 without retained output |
| Authority | None |
| Cost | None |

**Procedure.**

1. Sign in with the profile the work needs, and approve the sign-in in the browser. The
   authorization flow differs between CLI versions and was not recorded. Inspection and review
   run on the ReadOnly profile.

```
aws sso login --profile cloud-platform-readonly
aws sso login --profile cloud-platform-admin
```

2. Run [Verify the resolved identity](#verify-the-resolved-identity) and the
   [Account check](#account-check-before-aws-commands).

**Known limitations.** The retained evidence covers the Administrator profile only. The retained
read-only checks since 2026-08-08 also ran on the Administrator profile rather than on ReadOnly,
whose sessions last one hour.

### Verify the resolved identity

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-23) |
| Published form | not executed as written (the executed command was `aws sts get-caller-identity --profile cloud-platform-admin` without a projection, and its output was reduced before recording; the boolean projection is derived) |
| Evidence basis | Retained private evidence of the 2026-09-23 certificate plan and apply: the caller was an `AWSReservedSSO_AdministratorAccess` role session in the pinned account. The `UserId` prefix and the `ReadOnlyAccess` form are recorded for 2026-08-08 without retained output |
| Authority | None (read-only) |
| Cost | None |

**Purpose.** Confirm which identity the CLI actually resolved before running anything against
AWS. A profile can be pointed at the wrong account or resolve a wider role than intended, and the
returned identity, not the profile name, shows which one is in force.

**Procedure.**

1. Query the profile you intend to use, naming the permission set you selected
   (`AdministratorAccess` or `ReadOnlyAccess`):

```
aws sts get-caller-identity --profile <profile> \
  --query '[starts_with(UserId, `AROA`), contains(Arn, `:assumed-role/AWSReservedSSO_<permission-set>_`)]' \
  --output text
```

2. Run the [Account check](#account-check-before-aws-commands). The account is compared, never
   read off the output.

**Expected result.** Two values, both `True`. The first shows a role session: a role session's
`UserId` begins with `AROA`, an IAM user's with `AIDA`. The second shows the Identity Center role
of the permission set deliberately selected.

**Evidence to retain.** The two values and the account verdict.

**STOP conditions.** An error: the session is missing or expired; [sign in](#sign-in) again
([Session expiry](#session-expiry)). Any `False`: fix the profile before continuing
([Local CLI profiles](#local-cli-profiles)).

**Known limitations.** The retained 2026-09-23 records carry the role name only, for
`AdministratorAccess`, and do not record `UserId`. The `UserId` prefix and the `ReadOnlyAccess`
variant are recorded only for 2026-08-08, without retained output.

### Account check before AWS commands

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-24) for the PASS verdict; OFFLINE-VALIDATED (2026-09-22, 2026-09-24) for the HOLD verdict, in the private helper's qualification |
| Published form | not executed as written (derived from a private helper, not published, that compared the same caller-account query with the root's `allowed_account_id` and printed only the verdict; this function has not run against AWS) |
| Evidence basis | `allowed_account_ids` in each root's `providers.tf`; retained private evidence of the 2026-09-24 datastore plan, pre-apply gate, apply and read-back, each checked by the private helper after the export and again after the operator configuration was removed; offline qualification of the private helper's refusal paths (2026-09-22 and 2026-09-24) |
| Authority | None (read-only) |
| Cost | None |

**Purpose.** Each root's AWS provider refuses any account other than `allowed_account_id`, but
only when Terraform configures the provider, as in plan and apply. Backend-only commands such as
`terraform init`, `terraform state` and `terraform force-unlock` never configure it, and AWS CLI
calls are outside Terraform, so nothing else checks the account for them.

**Preconditions.** `<root-tfvars>` exists and sets `allowed_account_id`, as the root's Input
section describes ([Scope](#scope)).

**Procedure.**

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

**Evidence to retain.** The verdict line only.

**STOP conditions.** `ACCOUNT_MATCH=HOLD`. A missing or malformed pin, an unavailable or malformed
identity and a different account all hold, because none of them establishes the account; the
verdict does not say which. Nothing further runs; follow
[Wrong-account response](#wrong-account-response), part A.

**Known limitations.** The retained offline qualification exercised the private helper's refusal
paths, against stubbed responses, not this function: no retained record shows this function's
HOLD path, offline or live. No live HOLD has occurred. The provider's own refusal has not been
exercised against a second account.

### Session headroom before long operations

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-24) for measuring and proceeding; OFFLINE-VALIDATED (2026-09-22, 2026-09-24) for the HOLD, in the private helper's qualification; DESIGNED-NOT-EXECUTED (never) for the failure handling |
| Published form | not executed as written (the `aws configure export-credentials --profile <profile> --format env` call is the executed form; the expiry filter and the comparison are derived from a private helper that printed the same headroom line) |
| Evidence basis | Retained private evidence of the headroom lines printed before the 2026-09-24 datastore plan, gate, apply and read-back; offline qualification of the private helper's shortfall detection (2026-09-22 and 2026-09-24) |
| Authority | None (read-only) |
| Cost | None |

**Purpose.** A role credential cannot be extended once issued, and an exported one is never
refreshed. Before a long operation, confirm that the credential running it outlives the
operation, its verification and any teardown, with a margin.

**Procedure.**

1. Set the requirement in minutes: the operation's expected duration, plus its verification or
   teardown, plus a margin. Use a measured duration of the same operation where one exists. No
   margin rule has been established. The 2026-09-24 datastore apply required 50 minutes, a fixed
   allowance set before the apply with no published breakdown; that apply then measured about six
   minutes of instance creation.
2. Read the expiry of the credential that will run the operation, without printing the
   credential. Inside an exported shell, use `expiry=$AWS_CREDENTIAL_EXPIRATION` instead.

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

**Evidence to retain.** The headroom line.

**STOP conditions.** Any other exit status: the expiry is missing or unreadable, or the headroom
is below the requirement. Do not start the operation.

**Failure handling.** [Sign in](#sign-in) again, export again if the work uses an exported shell,
and read the expiry again. Proceed only on a measured value that covers the requirement. If the
re-read expiry is unchanged after the new sign-in, STOP and do not start the operation.

**Known limitations.** A shortfall has never stopped a live operation: its detection ran only
offline, in the private helper's qualification, and the failure handling above has never run.
Whether a new sign-in replaces a cached role credential that is still valid has not been
measured, which is why only the re-read value decides.

### Export role credentials once

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-24) for the passing path; OFFLINE-VALIDATED (2026-09-22, 2026-09-24) for every refusal, in the private wrapper's qualification |
| Published form | not executed as written (derived from a private wrapper, not published, that differed as listed under Known limitations; the export call is the executed form) |
| Evidence basis | Retained private evidence of the 2026-09-24 datastore plan, gate, apply and read-back, including the recorded names of the only variables Terraform received, which come from the private wrapper's allowlist, not from this procedure; offline qualification of the private wrapper's refusal paths (2026-09-22 and 2026-09-24) |
| Authority | None; the work it prepares carries its own grant |
| Cost | None |

**Purpose.** Run a long or sensitive operation on one role credential, in a shell that holds
nothing else: no operator configuration, no stray `AWS_*` or `TF_*` variable and no default
profile. Its credentials cannot change mid-run, and a failed export leaves nothing behind.

**Preconditions.**

- [Sign in](#sign-in), [Verify the resolved identity](#verify-the-resolved-identity) and the
  [Account check](#account-check-before-aws-commands) passed for the profile.
- The AWS CLI does not record command history for the profile, which would write API requests
  and responses to disk: `aws configure get cli_history --profile <profile>` prints nothing or
  `disabled`, and so does `aws configure get cli_history` for the default profile.

**Procedure.**

1. Start a clean shell. Every HOLD below exits it, taking whatever it held.

```
env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc
umask 077
```

2. In this shell, define `account_check`
   ([Account check before AWS commands](#account-check-before-aws-commands), step 1).
3. Export once from the profile, install only the four expected names, remove the operator's
   configuration from every later call, and check the account. Paste the block as one unit: the
   braces make the shell read all of it before running any of it, so an `exit 3` cannot leave the
   remaining lines to the shell that started this one. The text is parsed, never evaluated:
   `eval` would run any shell syntax it carried. Give `<root-tfvars>` as an absolute path, because
   `HOME` changes inside the block.

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

4. In this shell, run [Session headroom before long operations](#session-headroom-before-long-operations)
   step 3 with `expiry=$AWS_CREDENTIAL_EXPIRATION`. If it does not exit 0, `exit` this shell.
5. Run the work in this shell; Terraform commands follow
   [terraform-operations.md](terraform-operations.md). Never run `set -x`, print the environment
   unfiltered or write these variables to a file.

**Expected result.** `ACCOUNT_MATCH=PASS` and the headroom line, before the work starts.

**Evidence to retain.** The headroom line, the verdict, and the names of this shell's variables,
never their values:

```
env | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' | sort
```

These are the shell's names. The names recorded for the 2026-09-24 runs are the ones Terraform
received after the private wrapper reduced its environment.

**STOP conditions.** The export fails, is incomplete or carries an unexpected line; the headroom
falls short; the account check holds.

**Teardown / decommission.** Exit the shell when the work ends. The credentials end with it.

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
- `/var/empty` exists on macOS; elsewhere, use any empty directory the shell cannot write to.

### Session expiry

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-23) for steps 1 and 3; DESIGNED-NOT-EXECUTED (never) for step 2 |
| Published form | not executed as written (the sign-in is not captured in retained output; the retained record shows the expired session before it and a working session after it) |
| Evidence basis | Retained private evidence from 2026-09-23 of an expired SSO token and an expired cached role credential, read from the local credential cache without an AWS call, followed minutes later by an Administrator session in the pinned account. A command failing on an expired token is recorded for 2026-09-07 without retained output |
| Authority | None |
| Cost | None |

**Procedure.**

1. When a command fails with an expired or missing token, [sign in](#sign-in) again with the
   profile in use.
2. Credentials already exported into a shell keep their original expiry; a new sign-in does not
   extend them. Exit that shell and [export again](#export-role-credentials-once).
3. Run [Verify the resolved identity](#verify-the-resolved-identity) and the
   [Account check](#account-check-before-aws-commands) before the next AWS command.

**Known limitations.** The retained 2026-09-23 record detected the expiry from the credential
cache, not from a failed command. No recorded run has replaced exported credentials after a new
sign-in (step 2, [Not yet exercised](#not-yet-exercised)). Step 3 rests on the separately
validated checks.

### Credential expiry mid-run

| Field | Value |
|---|---|
| Validation status | DESIGNED-NOT-EXECUTED (never) |
| Published form | not executed as written (derived; of these steps, only the lifetime reads in step 2 ran, once, read-only, on 2026-09-12) |
| Evidence basis | Retained private evidence of the 2026-09-12 read-only diagnosis: an expired SSO token beside a still-valid 12-hour role credential. The backend failure it explained is recorded in narrative only, with no raw capture |
| Authority | None for steps 1 to 4; recovering an interrupted write carries its own grant |
| Cost | None directly; an interrupted apply can leave billable resources running |

**Purpose.** Two lifetimes are in play. The SSO access token from the browser sign-in governs
issuing new role credentials. A role credential, once issued, lasts until its own expiry, 12 hours
for Administrator, whatever happens to the token. Once, on 2026-09-11 and 2026-09-12, with the
token expired, AWS CLI calls through the profile kept working on the cached role credential while
Terraform's S3 backend failed with `InvalidGrantException`. That failure was recorded without raw
output, and the recorded interpretation is that the backend tried to refresh the token. What
happens in a shell whose exported credential expires mid-run has not been observed in this
project. [Session headroom before long operations](#session-headroom-before-long-operations) is
what keeps this from happening.

**Procedure.**

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
   [Session headroom before long operations](#session-headroom-before-long-operations), or
   `$AWS_CREDENTIAL_EXPIRATION` in the shell that failed.
3. [Sign in](#sign-in) again. If the run used an exported shell, exit it and
   [export again](#export-role-credentials-once).
4. Run [Verify the resolved identity](#verify-the-resolved-identity) and the
   [Account check](#account-check-before-aws-commands).
5. If the interrupted command wrote state (an apply, a destroy or a state change), do not re-run
   it: a lock or a partially applied change may remain. Follow the interrupted-apply procedure in
   [terraform-operations.md](terraform-operations.md). A read-only command can simply be re-run.

**Expected result.** After step 4, both verification values `True` and `ACCOUNT_MATCH=PASS`.

**Known limitations.**

- The response has never run as a whole, and it was never demonstrated that a new sign-in
  restores the backend.
- With more than one cached SSO session, for example another organization's, step 2 prints one
  expiry per session, and its output cannot tie a line to the project session. Telling them apart
  means reading each entry's start URL locally, without recording it.

### Wrong-account response

| Field | Value |
|---|---|
| Validation status | Part B: EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-08). Part A: DESIGNED-NOT-EXECUTED (never) |
| Published form | not executed as written (generic steps derived from the one recorded response; no command was retained) |
| Evidence basis | The recorded 2026-08-08 response (part B), without retained output; offline qualification of the private helper's account refusal, which part A depends on |
| Authority | None for part A; for part B, an explicit grant from the owner of the affected account before any cleanup |
| Cost | None expected; depends on what the command created |

**Procedure.**

A. The identity or account check failed before any mutating command ran:

1. Stop. No mutating command ran.
2. Exit any exported shell.
3. Find the cause with the existing checks, in the operator's normal shell:
   - [Verify the resolved identity](#verify-the-resolved-identity) returns an error: the session
     is missing or expired. [Sign in](#sign-in) again ([Session expiry](#session-expiry)).
   - It prints `False`: the profile resolves the wrong principal or role. Reconfigure it
     ([Local CLI profiles](#local-cli-profiles)).
   - It prints both values `True`, but the [Account check](#account-check-before-aws-commands)
     holds: the pin is missing or malformed, or the profile resolves another account. Check
     `<root-tfvars>` against the root's Input section ([Scope](#scope)). If the pin is present,
     reconfigure the profile against the project account ([Local CLI profiles](#local-cli-profiles)).
4. Repeat [Verify the resolved identity](#verify-the-resolved-identity) and the
   [Account check](#account-check-before-aws-commands). Both must pass before anything else runs.

B. A mutating command already ran against another account:

1. Stop every further command.
2. From the same profile, list what the command created or changed, rather than relying on the
   command's own response. The only exercised case is an IAM user created by a known command; no
   method is published or exercised for finding what an arbitrary command changed in another
   account ([Not yet exercised](#not-yet-exercised)).
3. Remove what it created, under the grant above. Before deleting an IAM principal, confirm that
   no access keys, policies or groups remain attached to it.
4. Re-query each removed resource and confirm it is absent, a not-found error rather than an
   access-denied one, instead of trusting the delete call.
5. Record what happened without the other account's identifier.
6. Continue with part A, steps 3 and 4.

**Validation.** Part B ran once, on 2026-08-08. A mutating probe, run through a profile that had
resolved an administrative role in an account other than the project account, created an IAM user
there. The user was deleted with nothing attached, its absence was re-queried, nothing billable
was created and the project account was not affected. No output was retained. Part A has never
run; the refusal it depends on has fired only in offline qualification of the private helper.

**Known limitations.** The lesson the recorded case carries: resolve the account and the role
before any mutating command, never probe a profile's permissions with a mutating command, and
never put a mutating command in the same block as an unresolved account or role check.

### Retire legacy IAM user credentials

| Field | Value |
|---|---|
| Validation status | EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-08) |
| Published form | not executed as written (the deactivation and login-removal commands were not retained; the commands here come from the AWS CLI reference) |
| Evidence basis | The 2026-08-08 key deactivation from the Administrator session, the closed default credential path and the console-login removal, recorded without retained output |
| Authority | Explicit owner grant (IAM credential change) |
| Cost | None |

**Purpose.** This covers a human IAM user's access key, meaning the access key ID and secret
access key pair an operator holds, and that user's console password. It does not cover workload
identities, CI federation or the temporary credentials Identity Center issues. Under
[ADR-0005](../decisions/0005-adopt-centralized-identity-and-least-privilege-access.md#decision),
an existing long-lived human key is retired rather than kept as a fallback.

Deactivate before you delete. Deactivation is reversible, so if something still depends on the
key you can re-enable it while you find out what. The sequence below turns an accidental fall back
to the old default credential path into an authentication failure instead of a silent success.

**Procedure.**

1. Complete [Operator setup in Identity Center](#operator-setup-in-identity-center),
   [Local CLI profiles](#local-cli-profiles) and [Sign in](#sign-in), so Identity Center access
   works.
2. Run [Verify the resolved identity](#verify-the-resolved-identity) with
   `--profile cloud-platform-admin` and `AdministratorAccess`. Both values must be `True`.
3. From that same Administrator session, deactivate the old key. The key being retired must never
   be the credential that performs its own deactivation. Do not delete it yet. Read
   `<access-key-id>` locally and keep it out of every record:

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

6. The deliberate exception to the profile rule in [Scope](#scope): in a fresh shell with no
   profile set, the default credential path must now fail to authenticate. This shows something
   only if the retired key was what the default path resolved before step 3. A missing-credentials
   error does not prove deactivation; step 5 is the proof of the key's status. The refusal text of
   the recorded run was not retained.

```
aws sts get-caller-identity --query 'starts_with(UserId, `AROA`)' --output text
```

7. In that same shell, step 2 must still return both values `True`.
8. Delete the key only after steps 6 and 7 pass, and only as a separately approved cleanup step
   ([Not yet exercised](#not-yet-exercised)).

A key counts as removed once its deletion has been verified. Until then it is deactivated, and
deactivated is what the evidence supports.

**Validation.** Recorded on 2026-08-08: the key was set to `Inactive` from the Administrator
session; a shell with no profile no longer authenticated; the login profile was removed, and the
Administrator path still resolved as a role session afterwards. That last check is recorded after
the login removal, not separately after the deactivation. The commands used were not retained.

**Known limitations.** A working Identity Center session shows that short-lived operator access is
available. It does not show that every long-lived IAM access key in the account has been removed,
which needs its own evidence. In the reference account the key is deactivated, not deleted.

**Next gate.** Deleting the key, and resolving the identity configuration's other deviations from
ADR-0005, each need a separate owner grant.

## Not yet exercised

| Item | Status |
|---|---|
| [First-time Identity Center prerequisites](#first-time-identity-center-prerequisites): enabling AWS Organizations and the Identity Center organization instance | UNEXERCISED |
| [Operator setup in Identity Center](#operator-setup-in-identity-center) run by an identity other than the root user | DESIGNED-NOT-EXECUTED |
| A measured check that MFA is required at sign-in | UNEXERCISED |
| [Wrong-account response](#wrong-account-response), part A; the account refusal it depends on was qualified only offline, in a private helper | DESIGNED-NOT-EXECUTED |
| Finding what an arbitrary command changed in another account ([Wrong-account response](#wrong-account-response), part B, step 2) | UNEXERCISED |
| Replacing an exported shell after a new sign-in ([Session expiry](#session-expiry), step 2) | DESIGNED-NOT-EXECUTED |
| Recovering from a headroom shortfall: sign in again, export again, re-measure ([Session headroom before long operations](#session-headroom-before-long-operations), failure handling) | DESIGNED-NOT-EXECUTED |
| Obtaining a new role credential while a cached one is still valid | UNEXERCISED |
| [Credential expiry mid-run](#credential-expiry-mid-run) | DESIGNED-NOT-EXECUTED |
| The provider's `allowed_account_ids` refusal against a real second account | UNEXERCISED |
| Deleting the deactivated legacy access key and verifying its absence | UNEXERCISED |
| Resolving the identity configuration's deviations from the ADR-0005 target model | UNEXERCISED |
| Break-glass recovery through the account root user ([ADR-0005](../decisions/0005-adopt-centralized-identity-and-least-privilege-access.md#decision)) | UNEXERCISED |
| Verifying the root posture: MFA enabled and no root access keys | UNEXERCISED |
| Revoking operator access: removing the assignment and the user, signing out, and removing local profiles and the SSO cache | UNEXERCISED |
| Access review after privileged or break-glass use and at milestones; the only record is the review of the 2026-08-08 root session | UNEXERCISED |
| Replacing a lost operator MFA device | UNEXERCISED |
| Signing out at the end of work (`aws sso logout`) | UNEXERCISED |

## Hidden prerequisites

- A dedicated AWS account for the platform. Its ID goes only into each root's untracked
  `terraform.tfvars`, as `allowed_account_id`, and into local AWS CLI configuration; never into
  the repository.
- An AWS Organizations management account with an IAM Identity Center organization instance
  ([First-time Identity Center prerequisites](#first-time-identity-center-prerequisites)).
- An identity for the first Identity Center setup; in the reference account it was the root user,
  and no other path was exercised. The root user's credentials and MFA device, held for recovery.
- The Identity Center start URL, its Region and the SSO session name, kept only in local AWS CLI
  configuration.
- An Identity Center user for each operator, with an email address the operator can read and the
  operator's own MFA device.
- The two permission sets, named exactly `ReadOnlyAccess` and `AdministratorAccess`, assigned to
  the account. Their generated role-name suffixes stay out of every record.
- A browser on the workstation to approve the sign-in.
- The toolchain in [Workstation toolchain](#workstation-toolchain).
- An approver for every step whose Authority row names an explicit owner grant: the person
  accountable for the AWS account ([Scope](#scope)).
- For key retirement only: the legacy IAM user's name and its access key ID, which stay out of
  every record.
