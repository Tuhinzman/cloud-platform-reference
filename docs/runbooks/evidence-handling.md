# Evidence Handling

## Scope

This runbook covers evidence from the moment a command's output is captured until the set is
sealed, exported to the durable evidence destination, and read back after the environment that
produced it is gone. It owns capture, redaction, the identifier sweep and its positive control,
handling sweep hits, sealing, export, read-back, and remediation of an artifact found to carry a
prohibited value.

It links rather than restates:

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
  [final decommission](../../terraform/foundation/README.md#final-decommission).
- [Runtime Validation](../validation/runtime-validation.md): the per-window results that export
  and read-back support. Runtime windows themselves are outside this runbook.
- [operator-access.md](operator-access.md): sessions, the account check, and keeping credential
  values out of evidence.
- [dev-datastore.md](dev-datastore.md): the value-based absence proof for the datastore master secret.
- [cost-and-residue.md](cost-and-residue.md): the orphan census whose output a window's set carries.
- [terraform-operations.md](terraform-operations.md): saved plans and their handling.

Validation labels are defined in the [runbook index](README.md).

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

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22, 2026-09-24) for file modes, UTC stamps, raw output beside the record, and capture of verdicts, counts and digests in place of identifiers. DESIGNED-NOT-EXECUTED (never) for the executed-by field, a 0700 evidence root and a location outside every Git working tree |
| Published form | not executed as written (method only, derived from the 2026-09-22 zero-node observation window set and the 2026-09-24 datastore apply and verification sets) |
| Evidence basis | [ADR-0019](../decisions/0019-bound-immutable-image-controls-for-aws-managed-runtime-images.md) evidence of the 2026-09-22 observation; retained private evidence of that window and of the 2026-09-24 datastore apply, read-back and secret verification |
| Authority | None for the capture itself; the operation it records carries its own authorization |
| Cost | None |

- **Purpose.** One bounded record per campaign that a later reader can check: what ran, on which
  exact inputs, what was expected, what happened, and which claim it supports.
- **Preconditions.** A private evidence root on the operator workstation, outside every Git working
  tree, mode 0700.
- **Procedure.**
  1. Set `umask 077` before the first command, so every file is created 0600 and every directory
     0700.
  2. Create one directory per campaign under the evidence root, named for its purpose and UTC start
     time.
  3. Write each command's stdout and stderr together to its own file as it runs, through
     [redaction at capture](#redact-at-capture), with a UTC timestamp (ISO 8601, seconds, `Z`) at
     the start and end of each step. Run capture commands with `TZ=UTC`, because a tool that
     formats timestamps in host local time otherwise records local time.
  4. Capture by construction where the claim allows: the verdict of the account check rather than
     the account ID ([operator-access.md](operator-access.md)), and counts, serials and digests
     rather than raw listings.
  5. Keep saved plans, plan JSON, state pulls and any other private-input carrier in a separate
     private run directory, and record only their SHA-256 digests in the set. Never capture debug
     logs of a root that handles a secret value
     ([dev-datastore Debug logging](../../terraform/dev-datastore/README.md#debug-logging)).
  6. Write the record last, from the template below, with the raw output files beside it.
  7. Confirm every file is 0600 and every directory 0700, then
     [sweep](#sweep-the-set-before-sealing) and [seal](#seal-the-set-and-verify-the-manifest).

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

- **Evidence to retain.** The record, the raw output files, the UTC stamps, and the digests of
  files kept outside the set.
- **Known limitations.**
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

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22) for pattern masking with a post-campaign pattern verify (the zero-node observation window), and for list-based replacement with a per-file residue check (the foundation apply). DESIGNED-NOT-EXECUTED (never) for one filter that applies the list and the patterns together, and for withholding a file that fails its re-scan |
| Published form | not executed as written (method only; the two validated runs used different filters, and no capture has applied the list, the patterns and the withhold rule together) |
| Evidence basis | Retained private evidence of the 2026-09-22 window, whose verify pass reported zero unmasked candidates in every text and JSON artifact present when it ran (two files written later were not verified; see [Sweep the set before sealing](#sweep-the-set-before-sealing)), and of the 2026-09-22 foundation apply, whose retained logs record redaction counts by class and zero residual for each retained file |
| Authority | None |
| Cost | None |

- **Purpose.** Keep private identifiers out of the set from its first byte, so no unredacted copy
  has to be found and cleaned later.
- **Inputs.** The private literal list and the address allowlist (see
  [Hidden prerequisites](#hidden-prerequisites)).
- **Procedure.**
  1. Pass every captured output, stdout and stderr together, through redaction before it is
     written into the set. Never write raw output into the set and redact it in place.
  2. Replace every value on the literal list with a label naming its class, such as `<account-id>`
     or `<evidence-bucket>`, longest value first, and mask the account field of every ARN.
  3. Mask any remaining account-shaped 12-digit sequence, and any IPv4 address or CIDR outside the
     allowlist.
  4. Re-scan the redacted text for every listed value and pattern. If anything remains, do not
     write the file; record that it was withheld and why, without the value.
  5. After the campaign, run the same check over every text artifact in the set.
- **Expected result.** Every retained file reports zero remaining candidates.
- **Known limitations.**
  - The pattern filter used in the 2026-09-22 window masks two classes and reads no list. The
    list-based filter used in the 2026-09-22 foundation apply replaces listed values and ARN
    account fields only, with no 12-digit or address-pattern masking and no retained check over
    the whole set afterwards. Its withhold path never fired.
  - In the 2026-09-22 window, two captured JSON files were written into the set unredacted and
    then redacted in place, contrary to step 1. Had the redaction failed, the raw file would have
    stayed in the set.
  - Pattern masking covers two classes only. A private literal of any other class passes it
    unchanged unless it is on the literal list, and the list catches only what it holds.
  - A file name that says "redacted" is not evidence of redaction; the verify result beside it is.

### Sweep the set before sealing

| Field | Value |
|---|---|
| Validation status | OFFLINE-VALIDATED (2026-09-22) for the pattern pass. OFFLINE-VALIDATED (2026-09-14) for a single-value, archive-aware, fail-closed scan. DESIGNED-NOT-EXECUTED (never) for sweeping after the final file, and for a value pass over the whole literal list, per class, as a pre-seal step |
| Published form | not executed as written (method only; the value pass and the pattern pass have not run together as one pre-seal step, and the sweep has not run after the final file) |
| Evidence basis | Retained private evidence of the 2026-09-22 zero-node window's sweep record, and of the 2026-09-14 scan of the whole private evidence tree for one prohibited value, run to verify a remediation |
| Authority | None |
| Cost | None |

- **Purpose.** The last check before sealing, over every file the set will contain.
- **Procedure.**
  1. Write every other file first, including the closing record. The sweep record of step 7 is
     the only file written after the sweep.
  2. Scan every file's content, and every file and directory name, for every value on the literal
     list. Report counts per class and per file, never the matched text.
  3. Scan the same content and names for fixed patterns: AWS access key ID shapes, private-key
     headers, credential environment assignments, JSON Web Token shapes and email addresses.
  4. Scan for account-shaped 12-digit sequences, and for IPv4 addresses and CIDRs with no allowlist
     applied. Every hit is explained in the sweep record.
  5. Inspect archives and compressed files member by member; a saved plan, for example, is a zip
     archive. A file or member the sweep cannot inspect fails the sweep and is never counted as
     clean.
  6. Run the [planted positive control](#plant-a-positive-control-for-the-sweep) before accepting a
     clean result.
  7. Write the sweep record into the set, holding only counts, class labels and the disposition of
     each hit ([handling sweep hits](#handle-sweep-hits-before-sealing)). Then run steps 2 to 4
     over the sweep record alone, printing counts to the terminal only. Any hit stops sealing;
     otherwise seal straight away.
- **Expected result.** Zero value hits, no unexplained pattern hit, zero uninspectable files,
  every planted instance detected, and a clean pass over the sweep record.
- **Known limitations.**
  - In the retained 2026-09-22 example the sweep ran before the closing record and one other file
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

| Field | Value |
|---|---|
| Validation status | DESIGNED-NOT-EXECUTED (never) |
| Published form | not executed as written (never run; derived from the planted-copy rule of the secret-absence proof in [dev-datastore.md](dev-datastore.md) and from the synthetic controls, including a fail-closed case, that the 2026-09-14 scan ran before its real scope) |
| Evidence basis | None for this step. The 2026-09-14 scan's synthetic controls were not planted in a set under sweep |
| Authority | None |
| Cost | None |

- **Purpose.** A sweep that reports nothing proves nothing unless it is shown, on the same run, to
  detect what it claims to cover.
- **Procedure.**
  1. Copy the set to a private scratch directory, mode 0700.
  2. Plant into the copy:
     - one instance of each value class: a copy of a listed value;
     - one instance of each pattern class: a synthetic value of that shape that is not on the
       literal list;
     - one listed value inside an archive member;
     - one near-miss value, close to a listed value but not equal to it, which must not be
       reported.
  3. Before the run, write down the expected increase per class. A planted listed value whose shape
     a pattern class also covers, such as the account ID or an email address, is expected once as
     a value hit and once as a pattern hit.
  4. Run the sweep, unchanged, over the copy and over the set. The copy's counts must exceed the
     set's by exactly the expected increase in every class, and the archive-member instance must be
     reported with its member.
  5. In a second copy, add one file the sweep cannot inspect. The sweep over it must fail.
  6. Delete both copies. Never plant into the set being sealed.
  7. Keep the reports' counts in the sweep record.
- **STOP conditions.** Any per-class result other than the expected increase, a reported near-miss,
  or an uninspectable file that does not fail the sweep: the sweep is not trusted and the set is
  not sealed.

### Handle sweep hits before sealing

| Field | Value |
|---|---|
| Validation status | OFFLINE-VALIDATED (2026-09-13, 2026-09-22) for inspecting, classifying and recording each hit. UNEXERCISED (never) for correcting a carrier and sweeping again |
| Published form | not executed as written (method only, derived from the 2026-09-13 pre-export disposition and the 2026-09-22 sweep record) |
| Evidence basis | Retained private disposition records of the 2026-09-11 and 2026-09-13 windows, and the 2026-09-22 zero-node window's sweep record |
| Authority | None |
| Cost | None |

- **Procedure.**
  1. Treat every hit as a value until inspection shows otherwise. Inspect it inside the private
     set, and do not copy the matched text anywhere else.
  2. Classify each hit as one of:
     - a name or reference, not a value: a field name, a secret key reference, a query path;
     - a documented platform value on the allowlist;
     - a prohibited value.
  3. For a prohibited value, remove the carrier from the set, update the record's Raw output and
     Not exercised fields to say so, and run the whole sweep again. No rule defines where an
     unredacted source may legitimately exist, so regenerating a carrier from one is not defined.
     This step is UNEXERCISED.
  4. Record the disposition in the sweep record: counts per class and per file, and the
     classification of each hit, without the matched text.
  5. A hit in a set that is already sealed or exported goes to
     [remediation](#remediate-a-prohibited-value-in-retained-or-exported-evidence).
- **Known limitations.** The retained dispositions of account-ID hits, on 2026-09-11 and
  2026-09-13, accepted them as private raw runtime output. Both predate redaction at capture, and
  this procedure does not allow it.

### Seal the set and verify the manifest

| Field | Value |
|---|---|
| Validation status | OFFLINE-VALIDATED (2026-09-24) for writing the manifest and verifying it in check mode |
| Published form | not executed as written (method only, derived from the manifests of the 2026-09-22 and 2026-09-24 sets and the set-membership check in the 2026-08-24 export tool) |
| Evidence basis | Retained private evidence sets sealed on 2026-09-22 and 2026-09-24; every manifest in the retained private evidence re-verified cleanly in a read-only check on 2026-09-24 |
| Authority | None |
| Cost | None |

- **Procedure.**
  1. Seal only after the sweep has passed.
  2. Write a manifest holding the SHA-256 of every file in the set by relative path, sorted,
     excluding only the manifest itself. It is the last file written, mode 0600.
  3. Verify it straight away in SHA-256 check mode; every entry must report OK.
  4. Confirm the set holds no file the manifest does not list, because check mode verifies only
     the files it lists.
  5. Record the manifest's full SHA-256 in a private record outside the set, which later also
     holds the export prefix and counts. This suite defines no format, location or retention for
     that record.
  6. Do not edit a sealed set. A correction is a new record beside it, sealed on its own.
- **Expected result.** Every entry OK, and the file list equal to the manifest's entries.
- **Known limitations.**
  - Some earlier sets have no manifest. A manifest shows that a set is unchanged since sealing; it
    says nothing about whether its content was clean when sealed.
  - For the cited 2026-09-22 and 2026-09-24 sets, no retained record shows the file-list check of
    step 4, and their manifest digests are not recorded outside the sets. The only retained
    implementation of the file-list check is the 2026-08-24 export tool, whose run output is not
    retained.
  - The 2026-09-11 and 2026-09-13 windows regenerated a sealed manifest in place for their
    post-teardown export, contrary to step 6. The pre-teardown manifests now exist locally only
    as digests in records written beside the set; the manifests themselves remain as exported
    objects.

### Export the sealed set before teardown

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-11, 2026-09-13) for run-time resolution of the destination by a name match that took the first result, an empty-prefix check that passed, recursive copy, a listing check for missing manifest entries only, and the manifest digest round trip. EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-24, 2026-08-26) for the staged copy and equal counts, and (2026-08-24) for the exact six-tag match with exactly one result. DESIGNED-NOT-EXECUTED (never) for the published step set as a whole |
| Published form | not executed as written (method only; the six-tag match, the staged copy and the equal-count rule are derived from the 2026-08-24 export tool, and no export has yet shipped a set redacted at capture with saved plans, plan JSON and state pulls excluded) |
| Evidence basis | Retained private evidence of the 2026-09-11 and 2026-09-13 exports, with their tooling and run output; the retained 2026-08-24 export tool without its run output; recorded results for 2026-08-24 and 2026-08-26 |
| Authority | Explicit owner grant for the write |
| Cost | Not measured separately: S3 request and storage charges for the set, which no retention rule bounds yet |

- **Purpose.** Evidence that must survive the environment leaves it before teardown
  ([ADR-0011](../decisions/0011-define-the-backup-and-recovery-model.md)).
- **Preconditions.**
  - The set is swept, sealed and verified.
  - It holds no saved plan, plan JSON, state pull or other private-input carrier. The validated
    exports excluded saved plan files by name pattern only. Plan JSON from the 2026-09-11 window
    was exported in both of that window's sets, and no removal is recorded. A plan JSON file from
    the 2026-09-13 window was exported and later removed under remediation.
  - An operator session for the project account, and the Account check before AWS commands in
    [operator-access.md](operator-access.md) passed against
    `terraform/foundation/terraform.tfvars`; stop on `ACCOUNT_MATCH=HOLD`. The tag match below
    does not establish the account, because any account where the foundation root was applied
    carries the same tags.
  - Every AWS command names `--profile <profile>` or runs in an exported shell, in `us-east-1`
    ([providers.tf](../../terraform/foundation/providers.tf)).
- **Procedure.**
  1. Re-verify the manifest and confirm the set's file list equals its entries.
  2. Stage a copy of the set in a private scratch directory, mode 0700, verify the copy against
     the manifest, and upload only from the copy, so nothing that changes after the check is
     exported.
  3. Resolve the destination at run time by an exact match on all six mandatory tags the
     foundation root applies ([providers.tf](../../terraform/foundation/providers.tf)). Exactly one
     bucket must match. Never print or record its name; refer to it as `<evidence-bucket>`. Hold
     the resolved name only in a shell or process variable and never echo it, suppress per-object
     transfer output (`--only-show-errors`) so only errors print, and route stdout and stderr
     together through [redaction at capture](#redact-at-capture) with the bucket name on the
     literal list. An errored listing or tag read is a STOP, never a count of zero.
  4. Build a new prefix for the set, in UTC:
     `<campaign-path>/<YYYYMMDDTHHMMSSZ>-<first 12 hex characters of the manifest SHA-256>`.
     One set, one prefix.
  5. List the prefix's current objects, object versions and delete markers; all three must be
     zero. The destination is versioned
     ([evidence-store.tf](../../terraform/foundation/evidence-store.tf)), so a listing of current
     objects alone can show a used prefix as empty.
  6. Copy the staged files in. Use copy, never sync, which can delete.
  7. List the prefix again. The object count must equal the staged file count, which is the
     manifest's entries plus the manifest; every manifest entry must be present, and no object the
     manifest does not list.
  8. Download the manifest object and compare its SHA-256 with the digest recorded at sealing.
  9. Delete the staged copy. Record the prefix, the counts and the listing result in the private
     record that holds the manifest digest, not in the sealed set.
  10. After teardown, make a final set in a new directory: a copy of the exported set's files plus
      the teardown and census records, swept and sealed with its own manifest. Leave the earlier
      set and its manifest unchanged. Export the final set under a new prefix in the same way,
      then [read back](#read-back-exported-evidence-after-destruction) every prefix exported for
      the window.
- **Expected result.** Zero objects, versions and delete markers before the copy; afterwards,
  equal counts, no missing or unlisted object, and a matching manifest digest.
- **Evidence to retain.** The prefix, the manifest digest, the before and after counts, the listing
  difference and UTC stamps, in the private record outside the set. Never the bucket name.
- **STOP conditions.** The account check holds; no bucket or more than one matches the tags; a
  listing or read errors; the prefix holds any object, version or delete marker; a count or the
  listing differs; the manifest digest differs. Never overwrite, delete or reuse a prefix. The
  full refusal set exists only in the 2026-08-24 export tool, whose run output is not retained.
  The 2026-09-11 and 2026-09-13 exports stopped only on an unresolved destination or a non-empty
  prefix, and recorded the other outcomes without stopping. No refusal is recorded as having fired
  live. The response to a refusal, including ADR-0013's stop condition for an unavailable evidence
  destination, has no written halt, continue or resume rule yet.
- **Known limitations.**
  - The 2026-09-11 and 2026-09-13 exports took the first bucket a name match returned, with no
    uniqueness check, uploaded from the live directory with no staged copy, listed current objects
    only, and discarded listing errors, so a failed listing would have read as zero objects.
  - Their figures would not meet step 7. On 2026-09-11 the manifest held 437 entries and the prefix
    440 objects; on 2026-09-13, 618 and 621. The manifest listed a saved plan the copy excluded,
    and files written after the manifest were copied without being listed in it.
  - The 2026-09-11 and 2026-09-13 exports predate redaction at capture and carry account-linked
    identifiers in raw runtime output. They remain private.
  - Who may read or write the destination is not expressed in Terraform, and retention is not
    decided (both in the foundation README, linked in Scope). The weekly evidence-retention review
    ADR-0013 sets has not been recorded as run.
  - Evidence of campaigns that destroyed no environment, the 2026-09 foundation, DNS, certificate
    and datastore applies, has not been exported to the durable destination.

### Read back exported evidence after destruction

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-08-14) for per-object read-back of two of 48 objects. EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-24, 2026-08-26) for per-object read-back of every object. AWS-VALIDATED (2026-09-11, 2026-09-13) for an object count and the manifest digest only |
| Published form | not executed as written (method only, derived from the per-object comparison in the retained 2026-08-24 export tool, whose run output is not retained) |
| Evidence basis | Retained private evidence of the 2026-08-14 read-back, with the two downloaded objects, and of the 2026-09-11 and 2026-09-13 count and digest read-backs; recorded results without run output for 2026-08-24 and 2026-08-26 |
| Authority | None (read-only calls). The validated runs used the administrator session; a read-only session has not been exercised for read-back |
| Cost | None measured; S3 request charges only |

- **Purpose.** [ADR-0011](../decisions/0011-define-the-backup-and-recovery-model.md) requires
  exported evidence to be read back from its destination after the environment is destroyed. It is
  a required verification in every window.
- **Preconditions.**
  - The environment's teardown, its orphan census and the final export are complete.
  - The Account check before AWS commands ([operator-access.md](operator-access.md)) passes against
    `terraform/foundation/terraform.tfvars`. Every AWS command names `--profile <profile>` or runs
    in an exported shell, in `us-east-1`.
- **Procedure.**
  1. For every prefix exported for the window, resolve the destination as in
     [Export](#export-the-sealed-set-before-teardown) step 3 and download every object under the
     prefix into a private scratch directory, mode 0700.
  2. Compute the SHA-256 of each downloaded file and compare it with its manifest entry.
  3. Confirm the downloaded manifest's SHA-256 equals the digest recorded at sealing.
  4. Confirm the object count equals the manifest's entries plus the manifest, with no object the
     manifest does not list. An errored listing is a STOP, never a count.
  5. Delete the scratch directory.
- **Expected result.** Every object matches, with zero mismatched, missing or extra objects and an
  equal manifest digest, for every prefix.
- **Evidence to retain.** The matched, mismatched and missing counts, the manifest digest
  comparison, the prefix and UTC stamps, in the private record outside the set.
- **STOP conditions.** Any mismatch, missing or extra object, errored listing, or a differing
  manifest digest: the set is not treated as durable.
- **Known limitations.**
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

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-14) |
| Published form | not executed as written (method only, derived from the 2026-09-14 remediation record; neither the deletion commands nor the raw output of the post-state checks were retained) |
| Evidence basis | Retained private remediation record of 2026-09-14, authorized 2026-09-13, which states the post-state results without their raw output |
| Authority | Explicit owner grant naming each artifact and the remedy |
| Cost | None |

- **Purpose.** Remove a prohibited value that reached a sealed or exported set without destroying
  the record of what happened.
- **Preconditions.**
  - Deletion is justified only when all five hold: a written evidence rule is violated; the
    artifact itself carries the prohibited value; sanitizing it in place would destroy its
    provenance; keeping it would continue the violation; and a stricter remedy than retention is
    required. It is never permission to delete evidence for tidiness, appearance, a failed
    measurement or ordinary cleanup.
  - The Account check before AWS commands ([operator-access.md](operator-access.md)) passes against
    `terraform/foundation/terraform.tfvars`. Every AWS command names `--profile <profile>` or runs
    in an exported shell, in `us-east-1`, and the destination is resolved as in
    [Export](#export-the-sealed-set-before-teardown) step 3.
- **Procedure.**
  1. Stop using the artifact. Record the finding without the value: the artifact, its digest and
     size, the class of value, and where copies exist.
  2. Obtain written authorization naming each artifact and the remedy.
  3. Record each affected prefix's object, version and delete-marker counts.
  4. Delete the local carrier.
  5. Delete each exported copy by its explicit object version ID. A plain delete only adds a delete
     marker and leaves the version in place
     ([Final decommission](../../terraform/foundation/README.md#final-decommission)).
  6. For each key, confirm that a head request returns not found, that no version and no delete
     marker remains, and that the prefix's object count fell from the count recorded in step 3 by
     exactly the removed objects.
  7. Scan the whole private evidence tree with a value-based, archive-aware scan that fails closed
     on anything it cannot inspect, after its synthetic controls, including a fail-closed case,
     behave as expected. The value may remain only where it must, such as the detector's own
     private pattern input.
  8. Write a remediation record beside the set: what was removed and why, the authorization date,
     the removed digests and sizes, the manifest lines deliberately left unchanged, the counts
     before and after, and the scan result. Do not edit the sealed manifest or earlier records.
- **Expected result.** The value appears nowhere outside its allowed location, and zero files are
  uninspectable.
- **Known limitations.**
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
| Correcting a carrier found by the sweep and sweeping again | UNEXERCISED | [Handle sweep hits before sealing](#handle-sweep-hits-before-sealing) |
| Export as published: a set redacted at capture, with saved plans, plan JSON and state pulls excluded | DESIGNED-NOT-EXECUTED | [Export the sealed set before teardown](#export-the-sealed-set-before-teardown) |
| Export of evidence from campaigns that destroyed no environment | UNEXERCISED | No rule says when it is due; [Export the sealed set before teardown](#export-the-sealed-set-before-teardown) |
| Response to an unavailable destination or a failed read-back | UNEXERCISED | [ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md) stop conditions; no halt, continue or resume rule is written |
| Weekly evidence-retention review | UNEXERCISED | [ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md); not recorded as run |
| Verifying a remediated set against its remediation record | UNEXERCISED | [Remediate a prohibited value](#remediate-a-prohibited-value-in-retained-or-exported-evidence) |
| Scanning exported objects for other copies of a prohibited value | UNEXERCISED | [Remediate a prohibited value](#remediate-a-prohibited-value-in-retained-or-exported-evidence) |
| Checking temporary directories for identifier-bearing files a run left behind | UNEXERCISED | No reviewed procedure exists |
| Recovering an evidence object from a prior version | UNEXERCISED | [Foundation README, Recovery](../../terraform/foundation/README.md#recovery) |

## Hidden prerequisites

- A private evidence root on the operator workstation, mode 0700 and outside every Git working
  tree, and a separate private run directory for saved plans, plan JSON and state pulls.
- A private, untracked literal list for redaction and sweeps, grouped by class: the project account
  ID, the `operator_cidr` value, the state and evidence bucket names, the registered domain, the
  hosted-zone ID and its assigned name servers, the GitLab project ID and email addresses. Every
  value in a root's untracked `terraform.tfvars` or `backend.hcl` that the repository does not
  already publish belongs on it.
- An allowlist for pattern masking: the Dev VPC range
  ([Address plan](../../terraform/dev/README.md#address-plan)); the cluster service range, which no
  root sets, so it is the range EKS assigned when the cluster was created, and which no procedure
  in this suite reads from a cluster; loopback; link-local; the RFC 5737 documentation ranges; the
  default route; and the unspecified and broadcast addresses.
- A redaction filter and a value-based, archive-aware sweep that read the list, report counts only
  and fail closed on anything they cannot inspect. The project's own are private and not published.
- A SHA-256 tool with a check mode, and the AWS CLI for export and read-back.
- An operator session for the project account able to write to and read from the evidence
  destination, and the foundation root's untracked `terraform.tfvars` for the account check
  ([operator-access.md](operator-access.md)).
- The evidence bucket name, held only in the foundation root's untracked input and resolved by tag
  at run time.
- A private record outside every sealed set that holds each manifest's full digest, the export
  prefix and the export and read-back counts. This suite defines no format, location or retention
  for it.
- Written owner authorization for each export and for each remediation deletion.
