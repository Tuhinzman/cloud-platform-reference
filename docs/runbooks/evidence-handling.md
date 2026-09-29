# Evidence Handling

This runbook keeps a campaign's evidence private, checkable and durable. It starts when a command's
output is captured, and ends when the sealed set has been exported to the durable evidence
destination and read back after the environment that produced it is gone. It does not cover
runtime windows themselves, which create the EKS cluster, its nodes and the NAT gateway, exercise
them and destroy them at close ([runbook index](README.md#scope)), or the separate scan of tracked
content that clears material for publication, which this suite does not document.

> **Current public boundary:** from the public repositories alone you can complete only step 1 of
> the [Normal path](#normal-path). Step 2 cannot start until you supply your own redaction filter,
> and the later steps need your own value-based, archive-aware sweep that fails closed. The
> project's own filter and sweep are private and not published
> ([Before you start](#before-you-start)).

> **Warning:** Secret values and private identifiers must never enter a retained or exported
> evidence set. Private identifiers are the values on the private literal list, such as the account
> ID, the bucket names and the domain; secret values include credentials of any kind. Output is
> redacted before it is written into a set, never afterwards. Saved plans, plan JSON and state
> pulls never enter a set, and debug logs of a root that handles a secret value are never captured.
> A value found before sealing is handled in
> [Handle sweep hits before sealing](#handle-sweep-hits-before-sealing); a value found in a sealed or
> exported set goes to
> [remediation](#remediate-a-prohibited-value-in-retained-or-exported-evidence).

## When to use this runbook

| If you need to | Go to |
|---|---|
| Start a campaign and keep its command output | [Capture a campaign evidence set](#capture-a-campaign-evidence-set) |
| Keep private identifiers out of captured output | [Redact at capture](#redact-at-capture) |
| Check a finished set before sealing it | [Sweep the set before sealing](#sweep-the-set-before-sealing) and [Plant a positive control for the sweep](#plant-a-positive-control-for-the-sweep) |
| Decide what a sweep hit is | [Handle sweep hits before sealing](#handle-sweep-hits-before-sealing) |
| Seal a swept set and verify its manifest | [Seal the set and verify the manifest](#seal-the-set-and-verify-the-manifest) |
| Copy a sealed set out before a teardown | [Export the sealed set before teardown](#export-the-sealed-set-before-teardown) |
| Prove exported evidence survived the teardown | [Read back exported evidence after destruction](#read-back-exported-evidence-after-destruction) |
| Remove a prohibited value from a sealed or exported set | [Remediate a prohibited value in retained or exported evidence](#remediate-a-prohibited-value-in-retained-or-exported-evidence) |

If another runbook sent you here, run the procedure it names, then return to the step that sent
you. The same holds inside this page: for a checklist item that links to another runbook's steps,
run those steps, check the PASS the item gives, then return to the list.

Terms used on this page:

| Term | Meaning |
|---|---|
| Campaign | One bounded operation whose evidence is kept together, for example a datastore apply with its read-back, or a runtime window |
| Set | One campaign's evidence directory: the raw output files, the record, the sweep record and the manifest |
| Record | The campaign's summary: what ran, on which exact inputs, what was expected, what happened, and which claim it supports. It is written from the [record template](#capture-a-campaign-evidence-set), with the raw output files beside it |
| Literal list | The private, untracked list of the project's private values, grouped by class ([Before you start](#before-you-start)) |
| Allowlist | The addresses that pattern masking leaves visible |
| Private-input carrier | A file that can hold a private input, such as a saved plan, plan JSON or a state pull |
| Carrier (of a value) | The file that holds a prohibited value |
| Redaction filter | The filter every captured output passes through before it is written into the set ([Redact at capture](#redact-at-capture)) |
| Sweep | The last check before sealing, over every file's content and names, for listed values, secret shapes, and account-shaped numbers and addresses ([Sweep the set before sealing](#sweep-the-set-before-sealing)) |
| Sweep record | The file in the set that holds the sweep's counts, class labels and the disposition of each hit, never the matched text; the only file written after the sweep apart from the manifest |
| Positive control | A known instance planted where the sweep must find it, on the same run |
| Sealing | Writing the manifest last and verifying it straight away, which fixes the set's content ([Seal the set and verify the manifest](#seal-the-set-and-verify-the-manifest)) |
| Manifest | A file that lists the SHA-256 of every file in the set, written last at sealing |
| Teardown | The destruction of the environment that produced the evidence, such as a runtime window's cluster at close. It runs outside this runbook |
| Prefix | The key path under which an exported set's objects are stored |
| Private record | The record outside every sealed set that holds manifest digests, export prefixes and counts ([Before you start](#before-you-start)) |
| Exported shell | A clean shell that holds one role credential exported once ([Export role credentials once](operator-access.md#export-role-credentials-once)) |

## Normal path

Every campaign runs steps 1 to 7. Steps 8 to 10 run around a teardown. Step 11 runs only when a
prohibited value is found in a sealed or exported set.

> **Warning:** Beyond the public boundary above, every procedure here is a method labelled
> not executed as written. Apart from `umask 077`, none has a published command form, and no exact
> expression is published for any pattern class. The planted positive control that proves any
> sweep has never been executed
> ([Plant a positive control for the sweep](#plant-a-positive-control-for-the-sweep),
> [Reproducibility gaps](#reproducibility-gaps)), and some parts have never run at all
> ([Not yet exercised](#not-yet-exercised)).

1. **Create a private evidence location.** Set up the evidence root once
   ([Before you start](#before-you-start)), then create one directory per campaign
   ([Capture a campaign evidence set](#capture-a-campaign-evidence-set), steps 1 and 2).
2. **Capture** every command's output into the set:
   [Capture a campaign evidence set](#capture-a-campaign-evidence-set).
3. **Redact** each output before it is written, as part of capture:
   [Redact at capture](#redact-at-capture).
4. **Sweep** the finished set: [Sweep the set before sealing](#sweep-the-set-before-sealing),
   steps 1 to 5.
5. **Prove the sweep** on the same run with a planted positive control:
   [Plant a positive control for the sweep](#plant-a-positive-control-for-the-sweep). Its run over
   the set is the sweep's result, not a second run.
6. **Handle findings** from the sweep, if it reported any:
   [Handle sweep hits before sealing](#handle-sweep-hits-before-sealing). Removing a carrier runs
   steps 4 and 5 again. Then write the sweep record and check it
   ([Sweep the set before sealing](#sweep-the-set-before-sealing), step 7).
7. **Seal** the set and verify its manifest:
   [Seal the set and verify the manifest](#seal-the-set-and-verify-the-manifest).
8. **Export** the sealed set before a teardown:
   [Export the sealed set before teardown](#export-the-sealed-set-before-teardown), steps 1 to 9
   (for a campaign that destroyed no environment, see Campaigns that destroyed no environment in
   that procedure).
9. **Export the final set** after the teardown and its orphan census, which run outside this
   runbook ([Run the orphan census](cost-and-residue.md#run-the-orphan-census)): a new set that
   adds the teardown and census records, swept with its positive control, sealed and exported under
   a new prefix ([Export the sealed set before teardown](#export-the-sealed-set-before-teardown),
   step 10).
10. **Read back** every exported prefix after the environment is destroyed:
    [Read back exported evidence after destruction](#read-back-exported-evidence-after-destruction).
11. **Remediate**, only if a prohibited value reached a sealed or exported set:
    [Remediate a prohibited value in retained or exported evidence](#remediate-a-prohibited-value-in-retained-or-exported-evidence).

<a id="hidden-prerequisites"></a>

## Before you start

**Where to run.** Steps 1 to 7 of the Normal path run on the operator workstation and work only
on local files. Export, read-back and remediation run AWS commands in `us-east-1`, each
naming `--profile <profile>` or running in an exported shell.

**Values you supply.**

| Placeholder | What it is | Where it comes from | Handling |
|---|---|---|---|
| `<profile>` | An operator profile for the project account, able to write to and read from the evidence destination | Sessions: [operator-access.md](operator-access.md) | None stated on this page |
| `<root-tfvars>` | The absolute path of the foundation root's filled, untracked `terraform.tfvars`, such as the copy in its `<inputs-dir>` outside every working tree ([terraform-operations.md](terraform-operations.md#before-you-start)) | Your own input file | Every value in it that the repository does not already publish belongs on the literal list |
| `<evidence-bucket>` | The evidence bucket, the durable evidence destination | Held only in the foundation root's untracked input, and resolved by tag at run time ([Export](#export-the-sealed-set-before-teardown), step 3) | Private: never print or record it |
| `<campaign-path>` | The campaign's part of an export prefix | This suite defines no form for it | Kept, as part of the prefix, in the private record |

For every campaign:

- [ ] A private evidence root on the operator workstation, mode 0700 and outside every Git working
  tree, and a separate private run directory for saved plans, plan JSON and state pulls.
- [ ] A private, untracked literal list for redaction and sweeps, grouped by class: the project
  account ID, the `operator_cidr` value, the state and evidence bucket names, the registered domain,
  the hosted-zone ID and its assigned name servers, the GitLab project ID and email addresses. Every
  value in a root's untracked `terraform.tfvars` or `backend.hcl` that the repository does not
  already publish belongs on it.
- [ ] An allowlist for pattern masking: the Dev VPC range
  ([Address plan](../../terraform/dev/README.md#address-plan)); the cluster service range, which no
  root sets, so it is the range EKS assigned when the cluster was created, and which no procedure
  in this suite reads from a cluster; loopback; link-local; the RFC 5737 documentation ranges; the
  default route; and the unspecified and broadcast addresses.
- [ ] A redaction filter and a value-based, archive-aware sweep that read the list, report counts
  only and fail closed on anything they cannot inspect. The project's own are private and not
  published, so a reproducer supplies their own before the first campaign. This suite defines no
  reduced capture without them ([Reproducibility gaps](#reproducibility-gaps)).
- [ ] A SHA-256 tool with a check mode.
- [ ] A private record outside every sealed set that holds each manifest's full digest, the export
  prefix and the export and read-back counts, with the listing results and UTC stamps, and never
  the bucket name. Export step 8 and every read-back compare against the digest it holds, so it
  must outlive the environment that produced the set. This suite defines no format, location or
  retention for it.

For export, read-back and remediation:

- [ ] The AWS CLI for export and read-back.
- [ ] An operator session for the project account able to write to and read from the evidence
  destination ([operator-access.md](operator-access.md)), and `<root-tfvars>` for the account
  check, `account_check`
  ([Check the account before AWS commands](operator-access.md#check-the-account-before-aws-commands)).
- [ ] The evidence bucket name, held only in the foundation root's untracked input and resolved by
  tag at run time.
- [ ] Written owner authorization for each export and for each remediation deletion.

### Public and private evidence

Raw evidence is private. Captured output, records, sweep and disposition records, sealed sets,
exported sets and the destination's name stay out of every repository. Saved plans, plan JSON and
state pulls are never evidence to export or publish, because they can carry private inputs even
where the configuration marks a variable sensitive.

The public repository carries small derived evidence: counts, digests, dates, results and
limitations re-derived from a private set, such as the tables in Runtime Validation and the Status
section of each root README. A public statement says what it rests on without requiring the private
set to be read.

Redaction and a clean sweep make a set safer to keep and to export. They do not clear it for
publication, which is decided by a separate scan of the tracked content; that control is not
documented in this suite. Placeholders such as `<allowed-account-id>`, `<evidence-bucket>` and
`<domain>` stand wherever a real value would appear.

## Procedures

### Capture a campaign evidence set

**Validation:** AWS-VALIDATED (2026-09-22, 2026-09-24) in part; DESIGNED-NOT-EXECUTED (never) in
part · **Published command form:** not executed as written

Builds one evidence set per campaign: one bounded record that a later reader can check, with the
raw output of every command beside it. Where the claim allows, capture keeps verdicts, counts,
serials and digests instead of identifiers and raw listings. Private-input carriers stay outside
the set, and only their digests go in. The steps are a method: apart from `umask 077`, no command
form is published.

**Before you start.**

- [ ] The private evidence root: on the operator workstation, outside every Git working tree, mode
  0700 ([Before you start](#before-you-start)).
- [ ] A separate private run directory for saved plans, plan JSON and state pulls.
- [ ] Your own redaction filter with the literal list and the address allowlist
  ([Redact at capture](#redact-at-capture)).

**Safety and authority.** Local-only. The capture itself needs no authorization; the operation it
records carries its own.

> **Warning:** No captured output enters the set except through redaction. A private-input
> carrier, such as a saved plan, plan JSON or a state pull, stays in the private run directory.

#### Step 1 — Set the file mask

Set `umask 077` before the first command, so every file is created 0600 and every directory 0700.

```
umask 077
```

#### Step 2 — Create the campaign directory

Create one directory per campaign under the evidence root, named for its purpose and UTC start
time.

#### Step 3 — Capture each command's output through redaction

Write each command's stdout and stderr together to its own file as it runs, through
[redaction at capture](#redact-at-capture), with a UTC timestamp (ISO 8601, seconds, `Z`) at the
start and end of each step. Run capture commands with `TZ=UTC`, because a tool that formats
timestamps in host local time otherwise records local time. A file enters the set only after its
re-scan passes ([Redact at capture](#redact-at-capture), step 4).

**Expected:** Every command's stdout and stderr went into the set only through redaction, with UTC
stamps.

> **Warning:** No rule defines where the unredacted output may be held until then, or when it
> is removed ([Handle sweep hits before sealing](#handle-sweep-hits-before-sealing), step 3).
> Files written outside the set are not swept, and no reviewed procedure checks temporary
> directories for identifier-bearing files a run left behind
> ([Not yet exercised](#not-yet-exercised)).

#### Step 4 — Capture verdicts, counts and digests instead of identifiers

Capture by construction where the claim allows: the verdict of the account check rather than the
account ID, and counts, serials and digests rather than raw listings. The account check compares
the caller's account with the root's `allowed_account_id` and prints only a verdict.

#### Step 5 — Keep private-input carriers outside the set

Keep saved plans, plan JSON, state pulls and any other private-input carrier in the separate
private run directory, and record only their SHA-256 digests in the set.

**Expected:** No private-input carrier is in the set; only its SHA-256 digest is.

> **Warning:** Never capture debug logs of a root that handles a secret value (Debug logging in
> the dev-datastore README).

#### Step 6 — Write the record last

Write the record last, from the template below, with the raw output files beside it. It is
written directly, not through the filter; the [sweep](#sweep-the-set-before-sealing) covers it.

| Record field | Holds |
|---|---|
| What was tested | The operation or claim under test, in one sentence |
| Exact inputs | The commit, saved-plan digest, image digest or tool version the run used |
| Expected | The pass criterion, fixed before the run |
| Observed | PASS, FAIL or INDETERMINATE with the measured values; one result is never converted into another |
| Claim supported | The public statement the set supports, or none |
| Executed by | Who ran each step, and the authorization it ran under |
| UTC stamps | Start and end of each step |
| Not exercised | What the run did not cover |
| Raw output | The file names beside the record |

Within a set, files are written in this order: the raw output files, ending with the redaction
verify result ([Redact at capture](#redact-at-capture), step 5), then the record, then the sweep
record, then the manifest. Only the raw output goes through the redaction filter; the other three
are written directly: the sweep covers the record, the pass over the sweep record in
[Sweep the set before sealing](#sweep-the-set-before-sealing), step 7, covers the sweep record,
and the manifest holds only the relative paths and SHA-256 digests of the files it lists.

**Expected:** The record was written last, from the template, with the raw output files beside it.

#### Step 7 — Check file modes, then sweep and seal

Confirm every file is 0600 and every directory 0700, then
[sweep](#sweep-the-set-before-sealing) and [seal](#seal-the-set-and-verify-the-manifest).

**Expected:** Every file is 0600 and every directory 0700.

**Expected result.** One campaign directory holding the record and the raw output files beside it,
UTC stamps at the start and end of each step, and only the digests of files kept outside the set.

**PASS when.**

- [ ] Every command's stdout and stderr went into the set only through redaction, with UTC stamps.
- [ ] No saved plan, plan JSON, state pull or other private-input carrier is in the set; only its
  SHA-256 digest is.
- [ ] The record was written last, from the template, with the raw output files beside it.
- [ ] Every file is 0600 and every directory 0700.

**STOP if.** Capture has no STOP condition of its own. Redaction withholds a file that fails its
re-scan ([Redact at capture](#redact-at-capture)), and any hit stops sealing
([Sweep the set before sealing](#sweep-the-set-before-sealing)).

**If it fails.** A withheld file is handled in [Redact at capture](#redact-at-capture), and a sweep
hit in [Handle sweep hits before sealing](#handle-sweep-hits-before-sealing). No other failure
procedure exists for capture.

**Evidence to keep.** The record, the raw output files, the UTC stamps, and the digests of files
kept outside the set.

**Next step.** [Sweep the set before sealing](#sweep-the-set-before-sealing).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22, 2026-09-24) for file modes, UTC stamps, raw output beside the record, and capture of verdicts, counts and digests in place of identifiers. DESIGNED-NOT-EXECUTED (never) for the executed-by field, a 0700 evidence root and a location outside every Git working tree |
| Published form | not executed as written (method only, derived from the 2026-09-22 zero-node observation window set and the 2026-09-24 datastore apply and verification sets) |
| Evidence basis | [ADR-0019](../decisions/0019-bound-immutable-image-controls-for-aws-managed-runtime-images.md) evidence of the 2026-09-22 observation; retained private evidence of that window and of the 2026-09-24 datastore apply, read-back and secret verification |
| Authority | None for the capture itself; the operation it records carries its own authorization |
| Cost | None |

**Known limitations.**

- No retained set has yet been kept outside every Git working tree. The executed-by field is new:
  some earlier records name no executor, and they are not rewritten.
- Earlier sets were not captured uniformly: some carry 0644 files, and some have no manifest.
- Some retained sets hold saved plans, including one sealed on 2026-09-23, and one 2026-09-17 set
  holds raw state pulls with 0644 files. Those sets are not export-ready under this runbook.
- One raw read in the 2026-09-24 datastore apply set printed timestamps in host local time. A
  second read with `TZ=UTC` recorded the UTC values; the first read was left unchanged.
- Files a tool writes outside the set are not swept. On 2026-09-22 a failed cleanup trap left a
  short-lived cluster configuration file carrying account-linked identifiers in the temporary
  directory; it was found during the window, removed by hand, and never entered the set.

### Redact at capture

**Validation:** AWS-VALIDATED (2026-09-22) in part; DESIGNED-NOT-EXECUTED (never) in part ·
**Published command form:** not executed as written

Keeps private identifiers out of the set from its first byte, so no unredacted copy has to be found
and cleaned later. Every captured output passes through a redaction filter before it is written
into the set. The filter reads the literal list and the allowlist: listed values become labels
naming their class, and account-shaped numbers and addresses outside the allowlist are masked. The
steps are a method; no command form is published.

**Before you start.**

- [ ] The private literal list and the address allowlist ([Before you start](#before-you-start)).
- [ ] A redaction filter that reads the list and fails closed. The project's own is private and not
  published.

**Safety and authority.** Local-only. No authorization is needed.

#### Step 1 — Redact before writing

Pass every captured output, stdout and stderr together, through redaction before it is written
into the set.

**Expected:** No output was written into the set before redaction.

> **Warning:** Never write raw output into the set and redact it in place.

#### Step 2 — Replace listed values with class labels

Replace every value on the literal list with a label naming its class, such as `<account-id>` or
`<evidence-bucket>`, longest value first, and mask the account field of every ARN.

#### Step 3 — Mask account-shaped numbers and addresses outside the allowlist

Mask any remaining account-shaped 12-digit sequence, and any IPv4 address or CIDR outside the
allowlist. Here, account-shaped means exactly 12 digits with no letter or digit directly before or
after them, the shape of an AWS account ID. A 12-digit run inside a digest, a timestamp or any
longer run is not account-shaped and passes unchanged, because capture keeps digests.

#### Step 4 — Re-scan before writing the file

Re-scan the redacted text for every listed value and pattern.

**Expected:** Nothing remains, and the file is written into the set.

**If not:** STOP for that file: do not write it. Keep a note that it was withheld and why, without
the value, and put it in the record's Raw output and Not exercised fields when the record is
written ([Capture a campaign evidence set](#capture-a-campaign-evidence-set), step 6). This suite
names no place to hold the note until then.

#### Step 5 — Verify every text artifact after the last command

After the campaign's last command, and before the record is written, run the same check over every
text artifact in the set. Its output is the verify result, the last raw output file.

**Expected:** Every retained file reports zero remaining candidates.

**If not:** Redaction has not passed, and the set is not sealed until the hit is handled
(**STOP if.** below).

**PASS when.**

- [ ] No output was written into the set before redaction.
- [ ] Every retained file reports zero remaining candidates in the check of step 5.
- [ ] Every withheld file is recorded, with the reason and without the value.

**STOP if.**

- The re-scan of step 4 finds anything: do not write that file.
- The check of step 5 finds a candidate: redaction has not passed. The sweep looks for the same
  listed values and patterns with no allowlist, so it reports the candidate as a hit, and the set
  is not sealed until that hit is handled in
  [Handle sweep hits before sealing](#handle-sweep-hits-before-sealing).

**If it fails.** A file that fails its re-scan is withheld and recorded, not written. A candidate
from step 5 has no separate procedure: it is a [sweep](#sweep-the-set-before-sealing) hit, handled
in [Handle sweep hits before sealing](#handle-sweep-hits-before-sealing). When that procedure
removes a carrier, it runs the sweep again, not this check, so the verify result stays as written;
the removed carrier is no longer a retained file, and the record's Raw output and Not exercised
fields say so.

**Evidence to keep.** The verify result beside the files it covers, and the record of each withheld
file and why, without the value. A file name that says "redacted" is not evidence of redaction; the
verify result beside it is.

**Next step.** When every file of the campaign is written,
[sweep the set](#sweep-the-set-before-sealing).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22) for pattern masking with a post-campaign pattern verify (the zero-node observation window), and for list-based replacement with a per-file residue check (the foundation apply). DESIGNED-NOT-EXECUTED (never) for one filter that applies the list and the patterns together, and for withholding a file that fails its re-scan |
| Published form | not executed as written (method only; the two validated runs used different filters, and no capture has applied the list, the patterns and the withhold rule together) |
| Evidence basis | Retained private evidence of the 2026-09-22 window, whose verify pass reported zero unmasked candidates in every text and JSON artifact present when it ran (two files written later were not verified; see [Sweep the set before sealing](#sweep-the-set-before-sealing)), and of the 2026-09-22 foundation apply, whose retained logs record redaction counts by class and zero residual for each retained file |
| Authority | None |
| Cost | None |

**Known limitations.**

- The pattern filter used in the 2026-09-22 window masks two classes and reads no list. The
  list-based filter used in the 2026-09-22 foundation apply replaces listed values and ARN
  account fields only, with no 12-digit or address-pattern masking and no retained check over
  the whole set afterwards. Its withhold path never fired.
- In the 2026-09-22 window, two captured JSON files were written into the set unredacted and
  then redacted in place, contrary to step 1. Had the redaction failed, the raw file would have
  stayed in the set.
- Pattern masking covers two classes only. A private literal of any other class passes it
  unchanged unless it is on the literal list, and the list catches only what it holds.

### Sweep the set before sealing

**Validation:** OFFLINE-VALIDATED (2026-09-14, 2026-09-22) in part; DESIGNED-NOT-EXECUTED (never)
in part · **Published command form:** not executed as written

The sweep is the last check before sealing, over every file the set will contain. Steps 2 to 5
say what it scans for; it fails on anything it cannot inspect and reports counts, never the matched
text. A clean result counts only after a planted positive control, on the same run, shows that the
sweep detects what it claims to cover. The steps are a method; no command form is published.

Order: steps 1 to 5, then step 6
([Plant a positive control for the sweep](#plant-a-positive-control-for-the-sweep)), then
[Handle sweep hits before sealing](#handle-sweep-hits-before-sealing) if there are hits, then
step 7.

**Before you start.**

- [ ] Every other file of the set is written, including the record
  ([Capture a campaign evidence set](#capture-a-campaign-evidence-set), step 6).
- [ ] A value-based, archive-aware sweep that reads the literal list, reports counts only and fails
  closed on anything it cannot inspect. The project's own is private and not published.

**Safety and authority.** Local-only, and read-only over the set until the sweep record is written.
No authorization is needed.

> **Warning:** In every scan (steps 2 to 5), report counts per class and per file, never the
> matched text.

#### Step 1 — Write every other file first

Write every other file first, including the record. The sweep record of step 7 is the only file
written after the sweep.

#### Step 2 — Scan for listed values

Scan every file's content, and every file and directory name, for every value on the literal list.

**Expected:** Zero value hits.

**If not:** The sweep has not passed. Record the counts and continue with steps 3 to 6; value hits
are handled after the positive control and before step 7, as step 6 says.

#### Step 3 — Scan for fixed secret and credential patterns

Scan the same content and names for fixed patterns: AWS access key ID shapes, private-key headers,
credential environment assignments, JSON Web Token shapes and email addresses.

**Expected:** See step 4, which judges pattern hits from steps 3 and 4 together.

#### Step 4 — Scan for account-shaped numbers and addresses

Scan for account-shaped 12-digit sequences, and for IPv4 addresses and CIDRs with no allowlist
applied. Every hit is explained in the sweep record.

**Expected:** Every pattern hit from steps 3 and 4 is counted. Each is explained in the sweep
record through [Handle sweep hits before sealing](#handle-sweep-hits-before-sealing), after
step 6.

#### Step 5 — Inspect archives member by member

Inspect archives and compressed files member by member; a saved plan, for example, is a zip
archive. A file or member the sweep cannot inspect fails the sweep and is never counted as clean.

**Expected:** Zero uninspectable files or archive members.

**If not:** STOP: the sweep fails (**If it fails.** below).

#### Step 6 — Prove the result with the positive control

Run the [planted positive control](#plant-a-positive-control-for-the-sweep) before accepting a
clean result. If the set has hits, [handle them](#handle-sweep-hits-before-sealing) before step 7.

**Expected:** Every planted instance is detected.

**If not:** STOP: the sweep is not trusted, and the set is not sealed.

#### Step 7 — Write the sweep record and check it

Write the sweep record into the set, holding only counts, class labels and the disposition of each
hit ([handling sweep hits](#handle-sweep-hits-before-sealing)). Then run steps 2 to 4 over the
sweep record alone, printing counts to the terminal only. The pass must print a count for every
class checked in steps 2 to 4, zero included, and finish without error.

**Expected:** A zero count for every class, and no error. Then seal straight away.

**If not:** Any hit stops sealing. No counts, a missing class, or an error means the pass did not
run: STOP and do not seal. Never read that as zero hits.

**PASS when.**

- [ ] Zero value hits.
- [ ] Every pattern hit is explained in the sweep record.
- [ ] Zero uninspectable files or archive members.
- [ ] Every planted instance of the positive control was detected.
- [ ] Steps 2 to 4 over the sweep record alone report a zero count for every class, and the pass
  finishes without error.

**STOP if.**

- A file or archive member cannot be inspected: the sweep fails.
- The positive control does not behave as expected: the sweep is not trusted, and the set is not
  sealed.
- A value hit or an unexplained pattern hit: the sweep has not passed, so the set is not sealed.
- Any hit in the pass over the sweep record: sealing stops.
- The pass over the sweep record prints no counts, leaves out a class, or ends in an error: the
  pass did not run, so sealing stops. It is never read as zero hits.

**If it fails.** Hits go to [Handle sweep hits before sealing](#handle-sweep-hits-before-sealing).
No procedure is written for correcting a sweep that cannot inspect a file or that misses a planted
instance; the set stays unsealed, and work stays stopped until a reviewed decision is taken under
explicit approval ([When to stop](README.md#when-to-stop)).

**Evidence to keep.** The sweep record in the set: counts, class labels and the disposition of each
hit, with the positive control's counts. The pass over the sweep record prints to the terminal only.

**Next step.** [Seal the set and verify the manifest](#seal-the-set-and-verify-the-manifest),
straight away.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | OFFLINE-VALIDATED (2026-09-22) for the pattern pass. OFFLINE-VALIDATED (2026-09-14) for a single-value, archive-aware, fail-closed scan. DESIGNED-NOT-EXECUTED (never) for sweeping after the final file, and for a value pass over the whole literal list, per class, as a pre-seal step |
| Published form | not executed as written (method only; the value pass and the pattern pass have not run together as one pre-seal step, and the sweep has not run after the final file; step 7's rule that the pass over the sweep record must print a count for every class, zero included, is added and has not been run) |
| Evidence basis | Retained private evidence of the 2026-09-22 zero-node window's sweep record, and of the 2026-09-14 scan of the whole private evidence tree for one prohibited value, run to verify a remediation |
| Authority | None |
| Cost | None |

**Known limitations.**

- In the retained 2026-09-22 example the sweep ran before the record and one other file
  were written, so those two files were never swept. Its pattern pass read no literal list and
  matched one mail domain rather than email addresses in general.
- Two pattern-only sweeps recorded as passes have since been found to have missed a private
  literal of a class their patterns do not cover. One, on one retained set, is open and awaits
  separate authorization. The other, a pre-export sweep on 2026-09-13, skipped some file types
  and any file it could not read; the value it missed was later removed under
  [remediation](#remediate-a-prohibited-value-in-retained-or-exported-evidence).
- Sweeps with a positive control are recorded for later 2026-09 sets, but none of those sets
  retains the sweep output, so they are not counted as execution.

### Plant a positive control for the sweep

**Validation:** DESIGNED-NOT-EXECUTED (never) · **Published command form:** not executed as written

A sweep that reports nothing proves nothing unless it is shown, on the same run, to detect what it
claims to cover. You plant known values into a copy of the set, run the unchanged sweep over the
copy and over the set, and check that the counts differ by exactly what you planted. The steps are
a method; no command form is published.

**Before you start.**

- [ ] The set is complete apart from the sweep record
  ([Sweep the set before sealing](#sweep-the-set-before-sealing), step 1).
- [ ] The sweep and the literal list.

**Safety and authority.** Local-only. No authorization is needed.

#### Step 1 — Copy the set

Copy the set to a private scratch directory, mode 0700.

#### Step 2 — Plant known instances into the copy

Plant into the copy:

- one instance of each value class: a copy of a listed value;
- one instance of each pattern class: a synthetic value of that shape that is not on the literal
  list;
- one listed value inside an archive member;
- one near-miss value, close to a listed value but not equal to it, which must not be reported.
  Take it from a literal class whose shape no pattern class covers, unlike the account ID or an
  email address (step 3), so neither the value pass nor the pattern pass reports it.

> **Warning:** Never plant into the set being sealed.

#### Step 3 — Write down the expected increase per class

Before the run, write down the expected increase per class. A planted listed value whose shape a
pattern class also covers, such as the account ID or an email address, is expected once as a value
hit and once as a pattern hit.

#### Step 4 — Run the sweep over the copy and the set

Run the sweep, unchanged, over the copy and over the set. The run over the set is the sweep's
result ([Sweep the set before sealing](#sweep-the-set-before-sealing), steps 2 to 5), not a second
run.

**Expected:** The copy's counts exceed the set's by exactly the expected increase in every class,
the archive-member instance is reported with its member, and the near-miss is not reported.

**If not:** STOP: the sweep is not trusted and the set is not sealed.

#### Step 5 — Check that an uninspectable file fails the sweep

In a second copy, add one file the sweep cannot inspect, and run the sweep over it.

**Expected:** The sweep over the second copy fails.

**If not:** STOP: the sweep is not trusted and the set is not sealed.

#### Step 6 — Delete both copies

Delete both copies.

#### Step 7 — Keep the counts

Keep the reports' counts in the sweep record.

**Expected:** The counts are in the sweep record, and both copies are deleted.

**PASS when.**

- [ ] Every class shows exactly the expected increase.
- [ ] The archive-member instance is reported with its member.
- [ ] The near-miss value is not reported.
- [ ] The sweep over the second copy fails.
- [ ] Both copies are deleted, and the counts are in the sweep record.

**STOP if.** Any per-class result other than the expected increase, a reported near-miss, or an
uninspectable file that does not fail the sweep: the sweep is not trusted and the set is not
sealed.

**If it fails.** The set is not sealed. No procedure is written for correcting the sweep and
running the control again, so work stays stopped until a reviewed decision is taken under explicit
approval ([When to stop](README.md#when-to-stop)).

**Evidence to keep.** The reports' counts, in the sweep record.

**Next step.** If the sweep reported hits in the set, handle them first:
[Handle sweep hits before sealing](#handle-sweep-hits-before-sealing). Then finish the sweep:
write the sweep record and check it
([Sweep the set before sealing](#sweep-the-set-before-sealing), step 7).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | DESIGNED-NOT-EXECUTED (never) |
| Published form | not executed as written (never run; derived from the planted-copy rule of the secret-absence proof in [dev-datastore.md](dev-datastore.md) and from the synthetic controls, including a fail-closed case, that the 2026-09-14 scan ran before its real scope) |
| Evidence basis | None for this step. The 2026-09-14 scan's synthetic controls were not planted in a set under sweep |
| Authority | None |
| Cost | None |

### Handle sweep hits before sealing

**Validation:** OFFLINE-VALIDATED (2026-09-22) in part; DESIGNED-NOT-EXECUTED (never) in part; UNEXERCISED (never) in part ·
**Published command form:** not executed as written

Decides, for each sweep hit, whether it is harmless or a prohibited value, and records the decision
without the matched text. The carrier of a prohibited value is removed from the set before sealing,
and the whole sweep runs again. Classification can explain a pattern hit. It cannot clear a value
hit, because the sweep passes only with zero value hits
([Sweep the set before sealing](#sweep-the-set-before-sealing), PASS when). The steps are a method;
no command form is published.

**Before you start.**

- [ ] A sweep reported hits, and the set is not yet sealed (sealed or exported: see step 5).

**Safety and authority.** Local-only, inside the private set. No authorization is needed.

#### Step 1 — Inspect each hit inside the private set

Inspect each hit inside the private set.

> **Warning:** Treat every hit as a value until inspection shows otherwise, and never copy the
> matched text out of the private set.

#### Step 2 — Classify each hit

Classify each hit as one of:

- a name or reference, not a value: a field name, a secret key reference, a query path;
- a documented platform value on the allowlist;
- a prohibited value.

**Expected:** Every hit has one of these three classifications.

#### Step 3 — Remove the carrier of a prohibited value

For a prohibited value, remove the carrier from the set, update the record's Raw output and Not
exercised fields to say so, and run the whole sweep again. This step is UNEXERCISED.

> **Warning:** No rule defines where an unredacted source may legitimately exist, so
> regenerating a carrier from one is not defined.

**Expected:** No prohibited value is left in the set.

#### Step 4 — Record the disposition

Record the disposition in the sweep record: counts per class and per file, and the classification
of each hit, without the matched text. The sweep record is written at
[Sweep the set before sealing](#sweep-the-set-before-sealing), step 7.

**Expected:** The sweep record holds counts and classifications without the matched text.

#### Step 5 — Send a hit in a sealed or exported set to remediation

A hit in a set that is already sealed or exported goes to
[remediation](#remediate-a-prohibited-value-in-retained-or-exported-evidence).

**PASS when.**

- [ ] Every hit is classified and recorded in the sweep record, without the matched text.
- [ ] Every carrier of a prohibited value is removed, and the record's Raw output and Not exercised
  fields say so.
- [ ] If step 3 removed a carrier, the whole sweep, with its positive control, has run again.

**STOP if.**

- The hit is in a set that is already sealed or exported: stop here and go to
  [remediation](#remediate-a-prohibited-value-in-retained-or-exported-evidence).

**If it fails.** A repeated sweep that still reports a value hit or an unexplained pattern hit
comes back to this procedure. A pattern hit explained in the sweep record, such as an address on
the allowlist, does not. No procedure defines how to regenerate a removed carrier.

**Evidence to keep.** The disposition in the sweep record: counts per class and per file, and the
classification of each hit, without the matched text.

**Next step.** When the sweep passes, repeated with its positive control if step 3 removed a
carrier, finish the sweep: write the sweep record and check it
([Sweep the set before sealing](#sweep-the-set-before-sealing), step 7). Then
[seal the set and verify the manifest](#seal-the-set-and-verify-the-manifest).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | OFFLINE-VALIDATED (2026-09-22) for inspecting one pattern hit, classifying it as a documented platform value on the allowlist, and recording that classification in the sweep record before sealing. DESIGNED-NOT-EXECUTED (never) for classifying a name or reference hit or a prohibited value before sealing, and for recording counts per class and per file without the matched text. UNEXERCISED (never) for correcting a carrier and sweeping again |
| Published form | not executed as written (method only, derived from the 2026-09-22 sweep record and from the 2026-09-11 and 2026-09-13 dispositions, which were written after their sets were exported) |
| Evidence basis | Retained private sweep record of the 2026-09-22 zero-node window, written before its manifest. The 2026-09-11 and 2026-09-13 disposition records were written after their sets were exported and accepted account-ID hits; they are the precedent this procedure replaces, not validation of it |
| Authority | None |
| Cost | None |

**Known limitations.** The retained dispositions of account-ID hits, on 2026-09-11 and
2026-09-13, were written after their sets were sealed and exported, and accepted the hits as
private raw runtime output. Both predate redaction at capture, and this procedure allows neither.
The 2026-09-22 sweep record names the matched allowlisted value and gives no per-file count.

### Seal the set and verify the manifest

**Validation:** OFFLINE-VALIDATED (2026-09-24) · **Published command form:** not executed as written

Sealing fixes the set's content. A manifest shows that a set is unchanged since sealing. It says
nothing about whether the content was clean when sealed, which is why sealing comes only after the
sweep has passed. The steps are a method; no command form is published.

**Before you start.**

- [ ] The sweep passed, with its positive control, and the sweep record is written
  ([Sweep the set before sealing](#sweep-the-set-before-sealing)).
- [ ] A SHA-256 tool with a check mode.
- [ ] The private record outside every sealed set ([Before you start](#before-you-start)).

**Safety and authority.** Local-only. No authorization is needed.

#### Step 1 — Confirm the sweep passed

Seal only after the sweep has passed.

#### Step 2 — Write the manifest

Write a manifest holding the SHA-256 of every file in the set by relative path, sorted, excluding
only the manifest itself. It is the last file written, mode 0600.

#### Step 3 — Verify the manifest

Verify it straight away in SHA-256 check mode.

**Expected:** Every entry reports OK.

**If not:** STOP. The set stays unsealed (**If it fails.** below).

#### Step 4 — Confirm the set holds no unlisted file

Confirm the set holds no file the manifest does not list, because check mode verifies only the
files it lists.

> **Warning:** Never add an unlisted file by rewriting the manifest. Apart from the manifest,
> only the sweep record is written after the sweep, so any other file the manifest does not
> list may never have been swept.

**Expected:** The file list equals the manifest's entries.

**If not:** STOP. The set stays unsealed (**If it fails.** below).

#### Step 5 — Record the manifest digest outside the set

Record the manifest's full SHA-256 in the private record outside the set
([Before you start](#before-you-start)), which later also holds the export prefix and counts. This
suite defines no format, location or retention for that record.

**Expected:** The manifest's full SHA-256 is in the private record outside the set.

#### Step 6 — Leave the sealed set unchanged

Do not edit a sealed set. A correction is a new record beside it, sealed on its own.

> **Warning:** Never regenerate a sealed manifest in place.

**PASS when.**

- [ ] Every manifest entry reports OK in check mode.
- [ ] The set holds no file the manifest does not list.
- [ ] The manifest's full SHA-256 is in the private record outside the set.

**STOP if.**

- A manifest entry does not report OK.
- The set holds a file the manifest does not list.

**If it fails.** The set stays unsealed and is not exported: it does not meet the precondition for
[export](#export-the-sealed-set-before-teardown). Do not rewrite the manifest or change the set to
make the check pass. No procedure is written for a set that fails its manifest check, so work stays
stopped until a reviewed decision is taken under explicit approval
([When to stop](README.md#when-to-stop)).

**Evidence to keep.** The manifest, inside the set, and its full SHA-256 in the private record
outside the set.

**Next step.** Before a teardown,
[export the sealed set](#export-the-sealed-set-before-teardown).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | OFFLINE-VALIDATED (2026-09-24) for writing the manifest and verifying it in check mode |
| Published form | not executed as written (method only, derived from the manifests of the 2026-09-22 and 2026-09-24 sets and the set-membership check in the 2026-08-24 export tool) |
| Evidence basis | Retained private evidence sets sealed on 2026-09-22 and 2026-09-24; every manifest in the retained private evidence re-verified cleanly in a read-only check on 2026-09-24 |
| Authority | None |
| Cost | None |

**Known limitations.**

- Some earlier sets have no manifest.
- For the cited 2026-09-22 and 2026-09-24 sets, no retained record shows the file-list check of
  step 4, and their manifest digests are not recorded outside the sets. The only retained
  implementation of the file-list check is the 2026-08-24 export tool, whose run output is not
  retained.
- The 2026-09-11 and 2026-09-13 windows regenerated a sealed manifest in place for their
  post-teardown export, contrary to step 6. The pre-teardown manifests now exist locally only
  as digests in records written beside the set; the manifests themselves remain as exported
  objects.

### Export the sealed set before teardown

**Validation:** AWS-VALIDATED (2026-09-11, 2026-09-13) in part; EXECUTED — RECORDED ONLY; RETAINED
EXECUTION EVIDENCE NOT AVAILABLE (2026-08-24, 2026-08-26, 2026-09-11, 2026-09-13) in part;
DESIGNED-NOT-EXECUTED (never) for the published step set as a whole · **Published command form:** not executed as written

Evidence that must survive the environment leaves it before teardown
([ADR-0011](../decisions/0011-define-the-backup-and-recovery-model.md)). This procedure copies a
swept, sealed and verified set to the durable evidence destination, the versioned evidence bucket
that the foundation root creates. The steps are a method; no command form is published.

**Before you start.**

- [ ] The set is swept, sealed and verified
  ([Seal the set and verify the manifest](#seal-the-set-and-verify-the-manifest)).
- [ ] It holds no saved plan, plan JSON, state pull or other private-input carrier.
- [ ] An operator session for the project account, and
  [Check the account before AWS commands](operator-access.md#check-the-account-before-aws-commands)
  passed against the foundation root's `<root-tfvars>` ([Before you start](#before-you-start)):
  `account_check <root-tfvars> --profile <profile>`, or the same without
  `--profile` inside an exported shell, printed `ACCOUNT_MATCH=PASS`. Stop on
  `ACCOUNT_MATCH=HOLD`. The tag match below does not establish the account, because any account
  where the foundation root was applied carries the same tags.
- [ ] Every AWS command names `--profile <profile>` or runs in an exported shell, in `us-east-1`
  ([providers.tf](../../terraform/foundation/providers.tf)). `<profile>` must be able to write to
  the evidence destination ([Before you start](#before-you-start)). For an exported shell, follow
  [Export role credentials once](operator-access.md#export-role-credentials-once), steps 1 to 4
  (PASS: `ACCOUNT_MATCH=PASS` with no HOLD line, and the headroom line with exit 0).
- [ ] [Check session headroom before long operations](operator-access.md#check-session-headroom-before-long-operations)
  passed, steps 1 to 3 (PASS: the headroom line is printed and the exit status is 0), with a
  requirement that covers the copy and its checks, steps 6 to 8. No measured export duration and
  no margin rule are published; set the requirement as its step 1 describes. A copy that stops
  part-way leaves a prefix that may never be reused or deleted.
- [ ] The evidence destination exists: `terraform/foundation` is applied. On a build from nothing
  it does not exist until the certificate-stage plan, which has no reviewed shape
  ([What these runbooks are](README.md#scope)).
- [ ] The cost gate for this billable write, in the exported shell:
  [Read back the budget and its alert states](cost-and-residue.md#read-back-the-budget-and-its-alert-states),
  steps 1 to 6 (PASS: as its **PASS when** lists; an `ALARM` follows
  [Budget threshold response](cost-and-residue.md#budget-threshold-response)), then
  [Re-check prices before billable work](cost-and-residue.md#re-check-prices-before-billable-work).
  - The price re-check stops, because the price table has no S3 storage rate: the owner approves a
    re-estimate before the export. No written re-estimation procedure exists.
- [ ] Explicit owner grant for the write.

**Safety and authority.** Mutating, owner-authorized and billable: it writes objects to the
evidence destination, and S3 request and storage charges apply. It needs an explicit owner grant for
the write. Each export needs its own written authorization, so the final set's export (step 10) is
not covered by the grant for the pre-teardown set. This suite does not define what the grant must
name, so no step checks the set against it.

> **Warning:** Never print or record the bucket name. Never overwrite, delete or reuse a prefix.

#### Step 1 — Re-verify the manifest

Re-verify the manifest and confirm the set's file list equals its entries.

**Expected:** As in [Seal](#seal-the-set-and-verify-the-manifest), steps 3 and 4: every entry
reports OK, and the file list equals the manifest's entries.

#### Step 2 — Stage a copy of the set

Stage a copy of the set in a private scratch directory, mode 0700, verify the copy against the
manifest, and upload only from the copy, so nothing that changes after the check is exported.

**Expected:** As in [Seal](#seal-the-set-and-verify-the-manifest), step 3: every entry of the
staged copy reports OK.

#### Step 3 — Resolve the destination by its six tags

Resolve the destination at run time by an exact match on all six mandatory tags the foundation root
applies to it ([providers.tf](../../terraform/foundation/providers.tf)):
`Project=cloud-platform-reference`, `Environment=shared`, `Component=evidence-store`,
`Lifecycle=persistent`, `Owner=platform-engineer` and `ManagedBy=terraform`, the six tags
[Read back the evidence-store controls](persistent-foundations.md#read-back-the-evidence-store-controls)
expects. No command form is published for this match, and this suite does not define how a bucket
with no tag set, or with tags beyond these six, is treated
([Reproducibility gaps](#reproducibility-gaps)).

> **Warning:** Never print or record its name; refer to it as `<evidence-bucket>`. Hold the
> resolved name only in a shell or process variable and never echo it, suppress per-object
> transfer output (`--only-show-errors`) so only errors print, and route stdout and stderr
> together through [redaction at capture](#redact-at-capture) with the bucket name on the
> literal list. An errored listing or tag read is a STOP, never a count of zero.

**Expected:** Exactly one bucket matches.

**If not:** STOP if no bucket or more than one matches, or if a listing or tag read errors.

The set being exported is sealed and never changes, so this captured output does not enter it.
This runbook names no set or location for it, so it is not swept. What must be kept from it, the
counts and the listing result, goes into the private record (step 9).

#### Step 4 — Build a new prefix

Build a new prefix for the set, in UTC:
`<campaign-path>/<YYYYMMDDTHHMMSSZ>-<first 12 hex characters of the manifest SHA-256>`.
One set, one prefix. `<campaign-path>` is the campaign's part of the key; this suite defines no
form for it ([Before you start](#before-you-start)).

> **Warning:** Never overwrite, delete or reuse a prefix.

#### Step 5 — Check that the prefix is empty

List the prefix's current objects, object versions and delete markers. The destination is
versioned ([evidence-store.tf](../../terraform/foundation/evidence-store.tf)), so a listing of
current objects alone can show a used prefix as empty.

**Expected:** Zero objects, zero versions and zero delete markers.

**If not:** STOP if the prefix holds any object, version or delete marker, or if the listing
errors.

#### Step 6 — Copy the staged files in

Copy the staged files in.

> **Warning:** Use copy, never sync, which can delete.

#### Step 7 — List the prefix again

List the prefix again.

**Expected:** The object count equals the staged file count, which is the manifest's entries plus
the manifest; every manifest entry is present, and no object the manifest does not list.

**If not:** STOP. A copy that stopped part-way fails here (**If it fails.** below).

#### Step 8 — Compare the manifest digest

Download the manifest object and compare its SHA-256 with the digest recorded at sealing.

**Expected:** The two digests are equal.

**If not:** STOP.

#### Step 9 — Delete the staged copy and record the results

Delete the staged copy. Record the prefix, the counts and the listing result in the private record
that holds the manifest digest, not in the sealed set.

**Expected:** The staged copy is deleted, and the prefix, counts and listing result are in the
private record.

**After the teardown.** The teardown and its orphan census
([cost-and-residue.md](cost-and-residue.md#run-the-orphan-census)) run outside this runbook.

#### Step 10 — Make and export the final set

Make a final set in a new directory: a copy of the exported set's files plus the teardown and
census records, swept, with its positive control, and sealed with its own manifest. Leave the
earlier set and its manifest unchanged. The teardown and census records enter only through
[redaction at capture](#redact-at-capture), and the final set has its own record from the
[template](#capture-a-campaign-evidence-set). Its own sweep record and manifest must not replace
the copied ones; this suite defines no file names for either. Export the final set under a new
prefix in the same way, steps 1 to 9, with its own grant, then
[read back](#read-back-exported-evidence-after-destruction) every prefix exported for the window.

**Expected:** The same results as steps 5, 7 and 8, for the final set's prefix.

**PASS when.**

- [ ] Exactly one bucket matched all six tags, and its name was never printed or recorded.
- [ ] The new prefix held zero objects, versions and delete markers before the copy.
- [ ] After the copy, the object count equals the manifest's entries plus the manifest, with no
  missing or unlisted object.
- [ ] The downloaded manifest's SHA-256 equals the digest recorded at sealing.
- [ ] The staged copy is deleted, and the prefix, counts and listing result are in the private
  record.
- [ ] Only when a teardown occurred: after the teardown and its census, the final set is swept with
  its positive control, sealed with its own manifest and exported under a new prefix in the same
  way, and the earlier set and its manifest are unchanged.

**STOP if.**

- The account check prints `ACCOUNT_MATCH=HOLD`.
- No bucket or more than one matches the tags.
- A listing or read errors.
- The prefix holds any object, version or delete marker.
- A count or the listing differs.
- The manifest digest differs.

**If it fails.**

- `ACCOUNT_MATCH=HOLD` goes to
  [Recover from a wrong account](operator-access.md#recover-from-a-wrong-account), part A. Once its
  step 4 passes, return to the first item of this procedure's **Before you start** and repeat every
  item from there, because part A exits any exported shell.
- For every other STOP, no procedure exists yet: the response to a refusal, including ADR-0013's
  stop condition for an unavailable evidence destination, has no written halt, continue or resume
  rule yet. Where no resume procedure is written, work stays stopped until a reviewed decision is
  taken under explicit approval ([When to stop](README.md#when-to-stop)).
- A copy that stops part-way, for example on an expired credential, is one of these STOPs: its
  prefix fails step 7. Never copy into that prefix again, and never overwrite, delete or reuse it;
  its counts and listing difference go into the private record, as under Evidence to keep.

**Evidence to keep.** The prefix, the manifest digest, the before and after counts, the listing
difference and UTC stamps, in the private record outside the set. Never the bucket name.

**Campaigns that destroyed no environment.** A campaign such as a foundation or datastore apply has
no rule saying when its set is due for export. Until one exists, its set stays only in the private
evidence root, with no durable copy, unless the owner authorizes its export in writing, as every
export requires. With that authorization, steps 1 to 9 and their PASS items apply; step 10 and its
PASS item follow a teardown and do not. No rule says whether or when such a prefix is read back,
because [read-back](#read-back-exported-evidence-after-destruction) follows a teardown.

**Next step.** After teardown and its census, export the final set (step 10), then
[read back exported evidence after destruction](#read-back-exported-evidence-after-destruction).
For a campaign that destroyed no environment, this runbook defines no next step.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-11, 2026-09-13) for run-time resolution of the destination by a name match that took the first result, recursive copy, a listing check for missing manifest entries only, and the manifest digest round trip. EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-09-11, 2026-09-13) for an empty-prefix check of current objects only, which discarded listing errors, so a zero count cannot tell an empty prefix from a failed listing, with a zero count kept for the pre-teardown exports and none for the post-teardown exports; (2026-08-24, 2026-08-26) for the staged copy and equal counts; and (2026-08-24) for the exact six-tag match with exactly one result. DESIGNED-NOT-EXECUTED (never) for the published step set as a whole |
| Published form | not executed as written (method only; the six-tag match, the staged copy and the equal-count rule are derived from the 2026-08-24 export tool, and no export has yet shipped a set redacted at capture with saved plans, plan JSON and state pulls excluded) |
| Evidence basis | Retained private evidence of the 2026-09-11 and 2026-09-13 exports, with their tooling and run output; the retained 2026-08-24 export tool without its run output; recorded results for 2026-08-24 and 2026-08-26 |
| Authority | Explicit owner grant for the write |
| Cost | Not measured separately: S3 request and storage charges for the set, which no retention rule bounds yet |

**Design.** Each set goes to its own new, empty prefix. After the copy, the prefix is listed and
the manifest object's SHA-256 is compared with the digest recorded at sealing, so a missing or
extra object, or a changed manifest, is caught before the environment is gone. The content of every
other object is compared with the manifest only at
[read-back](#read-back-exported-evidence-after-destruction), after destruction.

**Past exports and carriers.** The validated exports excluded saved plan files by name pattern
only. Plan JSON from the 2026-09-11 window was exported in both of that window's sets, and no
removal is recorded. A plan JSON file from the 2026-09-13 window was exported and later removed
under remediation.

**Refusals as executed.** The full refusal set exists only in the 2026-08-24 export tool, whose run
output is not retained. The 2026-09-11 and 2026-09-13 exports stopped only on an unresolved
destination or a non-empty prefix, and recorded the other outcomes without stopping. No refusal is
recorded as having fired live.

**Known limitations.**

- The 2026-09-11 and 2026-09-13 exports took the first bucket a name match returned, with no
  uniqueness check, uploaded from the live directory with no staged copy, listed current objects
  only, and discarded listing errors, so a failed listing would have read as zero objects.
- Their figures would not meet step 7. On 2026-09-11 the manifest held 437 entries and the prefix
  440 objects; on 2026-09-13, 618 and 621. The manifest listed a saved plan the copy excluded,
  and files written after the manifest were copied without being listed in it.
- The 2026-09-11 and 2026-09-13 exports predate redaction at capture and carry account-linked
  identifiers in raw runtime output. They remain private.
- Who may read or write the destination is not expressed in Terraform, and retention is not
  decided (both in the foundation README, linked under
  [Background prerequisites](#background-prerequisites)). The weekly evidence-retention review
  ADR-0013 sets has not been recorded as run.
- Evidence of campaigns that destroyed no environment, the 2026-09 foundation, DNS, certificate
  and datastore applies, has not been exported to the durable destination.

### Read back exported evidence after destruction

**Validation:** AWS-VALIDATED (2026-08-14) in part; EXECUTED — RECORDED ONLY; RETAINED EXECUTION
EVIDENCE NOT AVAILABLE (2026-08-24, 2026-08-26) in part; AWS-VALIDATED (2026-09-11, 2026-09-13)
for an object count and the manifest digest only · **Published command form:** not executed as
written

[ADR-0011](../decisions/0011-define-the-backup-and-recovery-model.md) requires exported evidence
to be read back from its destination after the environment is destroyed. It is a required
verification in every window. This procedure downloads every object under every prefix exported for
the window and compares each one with the sealed manifest. The steps are a method; no command form
is published.

**Before you start.**

- [ ] The environment's teardown, its orphan census and the final export are complete.
- [ ] [Check the account before AWS commands](operator-access.md#check-the-account-before-aws-commands)
  passes against the foundation root's `<root-tfvars>`, run as in
  [Export](#export-the-sealed-set-before-teardown):
  `account_check <root-tfvars> --profile <profile>` prints
  `ACCOUNT_MATCH=PASS`. Every AWS command names `--profile <profile>` or runs in an exported shell,
  in `us-east-1`.
- [ ] Every prefix exported for the window, both the pre-teardown set's and the final set's
  ([Export](#export-the-sealed-set-before-teardown), step 10), with their manifest digests, from
  the private record outside the set.

**Safety and authority.** Read-only and billable: S3 request charges only. No authorization is
needed for the read-only calls.

> **Warning:** Recovering an evidence object from a prior version, described in the
> [foundation README](../../terraform/foundation/README.md#recovery), restores that version into
> the destination. It is a recovery action that needs written owner approval
> ([Approvals](README.md#approvals)), and it has not been exercised. It is not a step of this
> procedure.

#### Step 1 — Download every object under each prefix

For every prefix exported for the window, resolve the destination as in
[Export](#export-the-sealed-set-before-teardown) step 3 and download every object under the prefix
into a private scratch directory, mode 0700.

> **Warning:** The bucket name is never printed or recorded, exactly as in Export step 3.

#### Step 2 — Compare each file with its manifest entry

Compute the SHA-256 of each downloaded file and compare it with its manifest entry.

**Expected:** Every downloaded file matches its manifest entry.

**If not:** STOP (see **If it fails.** below).

#### Step 3 — Compare the manifest digest

Confirm the downloaded manifest's SHA-256 equals the digest recorded at sealing.

**Expected:** The digests are equal.

**If not:** STOP.

#### Step 4 — Check the object count

Confirm the object count equals the manifest's entries plus the manifest, with no object the
manifest does not list. An errored listing is a STOP, never a count.

**Expected:** Zero missing or extra objects.

**If not:** STOP.

#### Step 5 — Delete the scratch directory

Delete the scratch directory.

**Expected:** The scratch directory is deleted.

**Expected result.** Every object matches, with zero mismatched, missing or extra objects and an
equal manifest digest, for every prefix.

**PASS when.**

- [ ] Every downloaded file matches its manifest entry.
- [ ] Zero mismatched, missing or extra objects, for every prefix.
- [ ] Each downloaded manifest's SHA-256 equals the digest recorded at sealing.
- [ ] The scratch directory is deleted.

**STOP if.** Any mismatch, missing or extra object, errored listing, or a differing manifest
digest: the set is not treated as durable.

**If it fails.** Stop, and do not treat the set as durable. No halt, continue or resume rule is
written for a failed read-back, so work stays stopped until a reviewed decision is taken under
explicit approval ([When to stop](README.md#when-to-stop)). A set changed by remediation reports
each removed object as missing, and no procedure yet verifies it against its remediation record.

**Evidence to keep.** The matched, mismatched and missing counts, the manifest digest comparison,
the prefix and UTC stamps, in the private record outside the set.

**Next step.** None for the window in this runbook. A prohibited value found later in a sealed or
exported set goes to
[Remediate a prohibited value in retained or exported evidence](#remediate-a-prohibited-value-in-retained-or-exported-evidence).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-08-14) for per-object read-back of two of 48 objects. EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-24, 2026-08-26) for per-object read-back of every object. AWS-VALIDATED (2026-09-11, 2026-09-13) for an object count and the manifest digest only |
| Published form | not executed as written (method only, derived from the per-object comparison in the retained 2026-08-24 export tool, whose run output is not retained) |
| Evidence basis | Retained private evidence of the 2026-08-14 read-back, with the two downloaded objects, and of the 2026-09-11 and 2026-09-13 count and digest read-backs; recorded results without run output for 2026-08-24 and 2026-08-26 |
| Authority | None (read-only calls). The validated runs used the administrator session; a read-only session has not been exercised for read-back |
| Cost | None measured; S3 request charges only |

**Captured output.** As at export, no set or location is named for the read-back's captured output
(step 1), so it is not swept. What must be kept from it, the counts and comparisons under Evidence
to keep, goes into the private record.

**Known limitations.**

- Per-object read-back with retained evidence covers two of 48 uploaded objects, on 2026-08-14:
  the integrity manifest and one runtime evidence file matched their local source byte for byte
  after the runtime was destroyed. On 2026-08-24 and 2026-08-26 every object of the final export
  is recorded as downloaded and matched, but the run output was not retained.
- On 2026-09-11 and 2026-09-13 only a listing count and a round trip of the manifest's digest
  were read back; no other object was downloaded and compared. Runtime Validation's 440 for
  2026-09-11 is the pre-teardown set's object count after teardown, against 437 manifest
  entries. Its 661 for 2026-09-13 is the final export's manifest-entry count, with 662 objects
  listed; the pre-teardown set was read back after teardown as 621 objects plus its manifest
  digest.
- No export or read-back is recorded for the 2026-09-22 zero-node observation window.
- A set changed by remediation no longer matches its sealed manifest, so a read-back reports each
  removed object as missing.

### Remediate a prohibited value in retained or exported evidence

**Validation:** EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-09-13, 2026-09-14) for the authorization, deletions, checks and scan; OFFLINE-VALIDATED (2026-09-14) for the remediation record; DESIGNED-NOT-EXECUTED (never) for the account check and the version and delete-marker counts · **Published command form:** not executed as written

Removes a prohibited value that reached a sealed or exported set without destroying the record of
what happened. The local carrier and every exported copy are deleted, the deletion is proven, the
whole private evidence tree is scanned, and a remediation record is written beside the set. The
sealed manifest and earlier records stay unchanged. The steps are a method; no command form is
published.

**Before you start.**

- [ ] Deletion is justified only when all five hold: a written evidence rule is violated; the
  artifact itself carries the prohibited value; sanitizing it in place would destroy its
  provenance; keeping it would continue the violation; and a stricter remedy than retention is
  required.
- [ ] [Check the account before AWS commands](operator-access.md#check-the-account-before-aws-commands)
  passes against the foundation root's `<root-tfvars>`, run as in
  [Export](#export-the-sealed-set-before-teardown):
  `account_check <root-tfvars> --profile <profile>` prints
  `ACCOUNT_MATCH=PASS`. Every AWS command names `--profile <profile>` or runs in an exported shell,
  in `us-east-1`, and the destination is resolved as in
  [Export](#export-the-sealed-set-before-teardown) step 3.
- [ ] A value-based, archive-aware scan that fails closed on anything it cannot inspect, with
  synthetic controls that include a fail-closed case. No such scan is published in this
  repository. Synthetic controls are known test inputs run before the real scope, including one
  file the scan cannot inspect, which must make it fail;
  [Plant a positive control for the sweep](#plant-a-positive-control-for-the-sweep) describes the
  same kind of control for the sweep.

**Safety and authority.** Destructive, mutating and owner-authorized: it deletes evidence locally
and in the destination. It needs an explicit owner grant naming each artifact and the remedy.

> **Warning:** Deletion is never permission to delete evidence for tidiness, appearance, a failed
> measurement or ordinary cleanup.

#### Step 1 — Stop using the artifact and record the finding

Stop using the artifact. Record the finding without the value: the artifact, its digest and size,
the class of value, and where copies exist.

#### Step 2 — Obtain written authorization

Obtain written authorization naming each artifact and the remedy.

**If not:** STOP. No deletion runs without it.

#### Step 3 — Record the counts before deletion

Record each affected prefix's object, version and delete-marker counts.

#### Step 4 — Delete the local carrier

Delete the local carrier.

> **Warning:** Steps 4 and 5 destroy evidence. Delete only the artifacts the written
> authorization of step 2 names; anything else is a STOP.

#### Step 5 — Delete each exported copy by version ID

Delete each exported copy by its explicit object version ID.

> **Warning:** A plain delete only adds a delete marker and leaves the version in place
> ([Final decommission](../../terraform/foundation/README.md#final-decommission)).

#### Step 6 — Prove the deletion

For each key, confirm that a head request returns not found, that no version and no delete marker
remains, and that the prefix's object count fell from the count recorded in step 3 by exactly the
removed objects.

**Expected:** Not found for each key, no version and no delete marker left, and each count lower
by exactly the removed objects.

**If not:** STOP. Do not retry or widen a deletion (**If it fails.** below).

#### Step 7 — Scan the whole private evidence tree

Scan the whole private evidence tree with a value-based, archive-aware scan that fails closed on
anything it cannot inspect, after its synthetic controls, including a fail-closed case, behave as
expected. The value may remain only where it must, such as the detector's own private pattern
input.

**Expected:** The value appears nowhere outside its allowed location, and zero files are
uninspectable.

**If not:** STOP (**If it fails.** below).

#### Step 8 — Write the remediation record

Write a remediation record beside the set: what was removed and why, the authorization date, the
removed digests and sizes, the manifest lines deliberately left unchanged, the counts before and
after, and the scan result. Do not edit the sealed manifest or earlier records.

**Expected:** The remediation record is beside the set, and the sealed manifest and earlier records
are unchanged.

**PASS when.**

- [ ] For each removed key, a head request returns not found, and no version and no delete marker
  remains.
- [ ] Each prefix's object count fell by exactly the removed objects.
- [ ] The scan's synthetic controls behaved as expected, the value appears nowhere outside its
  allowed location, and zero files are uninspectable.
- [ ] The remediation record is written beside the set, and the sealed manifest and earlier records
  are unchanged.

**STOP if.**

- Any of the five conditions for deletion does not hold.
- No written authorization names the artifact and the remedy.
- The account check prints `ACCOUNT_MATCH=HOLD`.
- A post-state check of step 6 or the scan of step 7 fails.

**If it fails.** `ACCOUNT_MATCH=HOLD` goes to
[Recover from a wrong account](operator-access.md#recover-from-a-wrong-account), part A. No
procedure is written for a remediation whose post-state checks or scan fail, so work stays stopped
until a reviewed decision is taken under explicit approval, and no deletion is retried or widened
to make a check pass ([When to stop](README.md#when-to-stop)).

**Evidence to keep.** The remediation record beside the set, holding what step 8 lists.

**Next step.** None in this runbook. The remediated set no longer matches its sealed manifest, so
a later [read-back](#read-back-exported-evidence-after-destruction) reports each removed object as
missing.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-09-13) for the written authorization, and (2026-09-14) for the object counts before and after, the local deletion, the deletion of each exported copy by version ID, the post-state checks and the whole-tree scan; OFFLINE-VALIDATED (2026-09-14) for the remediation record written beside the set, with the finding recorded without the value and the sealed manifest and earlier records left unchanged; DESIGNED-NOT-EXECUTED (never) for the account check before the deletions, and for recording each prefix's version and delete-marker counts before deletion |
| Published form | not executed as written (method only, derived from the 2026-09-14 remediation record; neither the deletion commands nor the raw output of the post-state checks were retained) |
| Evidence basis | Retained private remediation record of 2026-09-14, authorized 2026-09-13, which states the post-state results without their raw output |
| Authority | Explicit owner grant naming each artifact and the remedy |
| Cost | None |

**Known limitations.**

- The remediated set no longer matches its sealed manifest, and no procedure yet verifies a
  remediated set against its remediation record.
- No procedure scans exported objects for other copies of a value; step 1 finds copies only
  through records and local scans.
- The 2026-09-14 record states the deletions, the post-state checks and the count changes, but
  their raw output was not retained. Its scan reached zero uninspectable files only after one
  archive member that first failed closed was inspected out of band and the scanner was extended
  to that format.
- Plan JSON from the 2026-09-11 window remains in both of that window's exported sets. It is a
  carrier this runbook keeps out of every export, and no remediation of it is recorded.

## Not yet exercised

| Item | Status | Where |
|---|---|---|
| Executed-by field, 0700 evidence root, location outside every Git working tree | DESIGNED-NOT-EXECUTED | [Capture a campaign evidence set](#capture-a-campaign-evidence-set) |
| One redaction filter applying the list and the patterns together, and withholding a file that fails its re-scan | DESIGNED-NOT-EXECUTED | [Redact at capture](#redact-at-capture) |
| Sweep after the final file, with a value pass over the whole literal list per class, as one pre-seal step | DESIGNED-NOT-EXECUTED | [Sweep the set before sealing](#sweep-the-set-before-sealing) |
| Planted positive control for the sweep, with archive, fail-closed and near-miss cases | DESIGNED-NOT-EXECUTED | [Plant a positive control for the sweep](#plant-a-positive-control-for-the-sweep) |
| Classifying a name or reference hit, or a prohibited value, before sealing, and recording counts per class and per file without the matched text | DESIGNED-NOT-EXECUTED | [Handle sweep hits before sealing](#handle-sweep-hits-before-sealing) |
| Correcting a carrier found by the sweep and sweeping again | UNEXERCISED | [Handle sweep hits before sealing](#handle-sweep-hits-before-sealing) |
| Export as published: a set redacted at capture, with saved plans, plan JSON and state pulls excluded | DESIGNED-NOT-EXECUTED | [Export the sealed set before teardown](#export-the-sealed-set-before-teardown) |
| Empty-prefix check that counts current objects, object versions and delete markers and stops on an errored listing | DESIGNED-NOT-EXECUTED | [Export the sealed set before teardown](#export-the-sealed-set-before-teardown), step 5 |
| Export of evidence from campaigns that destroyed no environment | UNEXERCISED | No rule says when it is due; [Export the sealed set before teardown](#export-the-sealed-set-before-teardown) |
| Response to an unavailable destination or a failed read-back | UNEXERCISED | [ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md) stop conditions; no halt, continue or resume rule is written |
| Weekly evidence-retention review | UNEXERCISED | [ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md); not recorded as run |
| Account check before the remediation deletions, and each prefix's version and delete-marker counts recorded before deletion | DESIGNED-NOT-EXECUTED | [Remediate a prohibited value](#remediate-a-prohibited-value-in-retained-or-exported-evidence) |
| Verifying a remediated set against its remediation record | UNEXERCISED | [Remediate a prohibited value](#remediate-a-prohibited-value-in-retained-or-exported-evidence) |
| Scanning exported objects for other copies of a prohibited value | UNEXERCISED | [Remediate a prohibited value](#remediate-a-prohibited-value-in-retained-or-exported-evidence) |
| Checking temporary directories for identifier-bearing files a run left behind | UNEXERCISED | No reviewed procedure exists |
| Recovering an evidence object from a prior version | UNEXERCISED | [Foundation README, Recovery](../../terraform/foundation/README.md#recovery) |

## Reproducibility gaps

What a new engineer cannot reproduce from the public repositories today, taken from the facts
above.

| What cannot be reproduced | Public contract that exists | Needed later |
|---|---|---|
| The redaction filter and the value-based, archive-aware sweep. The project's own are private and not published. No exact expression is published for any pattern class, and the positive control that would prove a home-built sweep has never been executed. | The methods in [Redact at capture](#redact-at-capture) and [Sweep the set before sealing](#sweep-the-set-before-sealing): read the literal list, report counts only, fail closed. [Plant a positive control for the sweep](#plant-a-positive-control-for-the-sweep) defines how any sweep is proven. | A public filter and sweep, with their pattern expressions and a runnable positive control, executed as written. |
| The literal list and the allowlist values. The list holds private values; the cluster service range is set by EKS, no root sets it, and no procedure in this suite reads it from a cluster. | The list's classes and the allowlist ranges in [Before you start](#before-you-start). | No tool for the list, which stays private by design. A procedure that reads the cluster service range is needed. |
| Export as a runnable command. The six-tag match, the staged copy and the equal-count rule come from the 2026-08-24 export tool, and the full refusal set exists only in that tool, whose run output is not retained. | The method in [Export the sealed set before teardown](#export-the-sealed-set-before-teardown). | A published export command form or tool, executed as written. |
| Read-back as a runnable command. The per-object comparison comes from the same 2026-08-24 export tool. | The method in [Read back exported evidence after destruction](#read-back-exported-evidence-after-destruction). | A published read-back command form, executed as written. |
| Remediation as a runnable command, and the value-based, archive-aware scan it needs, which is not published. Neither the deletion commands nor the raw output of the post-state checks were retained. | The method in [Remediate a prohibited value](#remediate-a-prohibited-value-in-retained-or-exported-evidence). | A published command form, and procedures that verify a remediated set against its remediation record and scan exported objects for other copies of a value. |
| The private record of manifest digests, export prefixes and counts, and a place for the captured output of export and read-back. | What the record must hold ([Before you start](#before-you-start)). This suite defines no format, location or retention for it, and names no set or location for that output ([Export](#export-the-sealed-set-before-teardown), step 3). | A defined format, location and retention, and a place for that output. |
| The response to an export refusal, an unavailable destination or a failed read-back. | The STOP conditions above and ADR-0013's stop condition for an unavailable evidence destination. | A written halt, continue and resume rule. |
| When evidence from a campaign that destroyed no environment is exported, and whether its prefix is read back. | None: no rule says when it is due, and read-back follows a teardown. | A rule. |
| The weekly evidence-retention review. | [ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md) sets it; it has not been recorded as run. | A review procedure. |
| Checking temporary directories for identifier-bearing files a run left behind. | None. | A reviewed procedure. |
| Clearing a set for publication. | The rule that redaction and a clean sweep do not clear a set for publication ([Public and private evidence](#public-and-private-evidence)). The separate scan of tracked content is not documented in this suite. | A published procedure for that scan. |
| The evidence destination's access model and retention. | The [foundation README](../../terraform/foundation/README.md#what-the-protections-do-and-what-they-do-not): who may read or write evidence is not expressed in Terraform, and [retention is not decided](../../terraform/foundation/README.md#evidence-retention-is-not-decided-yet). | An access definition and a retention rule, outside this runbook. |
| The retained private evidence behind every label. | Small derived evidence in the public repository, such as the tables in Runtime Validation and each root README's Status section ([Public and private evidence](#public-and-private-evidence)). | None: raw evidence is private by design. |

## Background prerequisites

These records and runbooks hold the decisions and neighbouring procedures this runbook relies on.
None is needed to begin.

- [ADR-0011](../decisions/0011-define-the-backup-and-recovery-model.md): why exported evidence is
  designated recoverable state, and why it is read back after an environment is destroyed.
- [ADR-0010](../decisions/0010-define-the-observability-model.md): evidence is captured before an
  ephemeral environment is destroyed.
- [ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md): an unavailable evidence
  destination is a stop condition, and the record sets a weekly evidence-retention review.
- The [foundation root](../../terraform/foundation/README.md): what the destination is,
  [what its protections do and do not do](../../terraform/foundation/README.md#what-the-protections-do-and-what-they-do-not),
  [undecided retention](../../terraform/foundation/README.md#evidence-retention-is-not-decided-yet),
  [recovery from object versions](../../terraform/foundation/README.md#recovery) and
  [final decommission](../../terraform/foundation/README.md#final-decommission), which is an order
  only, with no command-level procedure.
- [Runtime Validation](../validation/runtime-validation.md): the per-window results that export
  and read-back support. Runtime windows themselves are outside this runbook.
- [operator-access.md](operator-access.md): sessions, the account check, and keeping credential
  values out of evidence.
- [dev-datastore.md](dev-datastore.md): the value-based absence proof for the datastore master secret.
- [cost-and-residue.md](cost-and-residue.md): the orphan census whose output a window's set carries.
- [terraform-operations.md](terraform-operations.md): saved plans and their handling.
- Validation labels are defined in the [runbook index](README.md).
