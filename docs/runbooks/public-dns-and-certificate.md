# Public DNS and Certificate Runbook

This runbook operates the public hosted zone, its delegation from the registrar, and the ACM
certificate validated through that zone. `terraform/foundation` declares the zone and the
certificate, in [`dns.tf`](../../terraform/foundation/dns.tf) and
[`certificate.tf`](../../terraform/foundation/certificate.tf); the delegation is a registrar-side
setting, outside Terraform and outside AWS. It does not cover environment DNS records, the record
controller or binding the certificate to a load balancer. Those belong to runtime windows, the
periods that create the EKS cluster and its runtime resources, exercise them and destroy them at
close, which this suite does not cover ([runtime validation](../validation/runtime-validation.md)).
[ADR-0018](../decisions/0018-define-the-public-entry-implementation-dns-and-certificate-model.md)
is the decision, [ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md) sets the
persistent-foundation obligations and the cost rules, and
[Public DNS](../../terraform/foundation/README.md#public-dns) says what the root creates and why.
Validation labels and the published-form rule are defined in the [runbook index](README.md).

## Normal path

Run these in order. The zone comes first because the certificate's DNS validation depends on the
registrar delegating to the zone.

1. [Build the zone on its own](#build-the-zone-on-its-own): plan and apply the hosted zone alone,
   with approval.
2. [Read back the hosted zone](#read-back-the-hosted-zone): confirm the zone and read its four
   name servers.
3. [Pre-cutover checks](#pre-cutover-checks): see what the parent delegates to now, check for a
   DS record, and confirm Route 53 already answers. Then establish the registrar's lock status
   ([Registrar lock check](#registrar-lock-check)), which has no reviewed procedure.
4. [Change the name servers at the registrar](#change-the-name-servers-at-the-registrar): a manual
   registrar change, with approval.
5. [Verify delegation](#verify-delegation): repeat until every parent server refers to Route 53.
6. [CAA check](#caa-check): confirm that no CAA record at `<apex>` or its parent stops Amazon's
   certificate authority. It has no reviewed procedure. It comes after delegation, not before the
   registrar change, because until then the previous provider still answers for `<apex>`.
7. [Plan and apply the certificate](#plan-and-apply-the-certificate): plan the whole root, verify
   delegation again, then apply, with approval. Its plan shape assumes the rest of the foundation
   is already applied; on a build from nothing no reviewed shape exists, and the plan stops at
   its step 2.
8. [Read back the certificate](#read-back-the-certificate): confirm the issued certificate.

> **Warning:** On a build from nothing, this path currently ends at step 7, before any
> certificate exists. The certificate-stage plan also adds the evidence store, the registry
> repositories and the CI identity. That combined plan has never run and has no reviewed shape, so
> [Plan and apply the certificate](#plan-and-apply-the-certificate) stops at its step 2, and no
> published procedure builds those resources first
> ([persistent-foundations.md](persistent-foundations.md#reproducibility-gaps)). By then the zone
> exists and bills, and the domain is delegated to it. Work stays stopped there until a reviewed
> decision is taken under explicit approval ([When to stop](README.md#when-to-stop)). Know this
> before step 1, which creates the billable zone: on a build from nothing, the owner accepts it in
> writing before step 1 starts ([Build the zone on its own](#build-the-zone-on-its-own)).
> On a build from nothing, step 1 is also the foundation root's first apply, and it can stop
> earlier, at its binding check, before any zone exists: what that check's state read prints
> against a state object never yet written has not been recorded
> ([Bind the saved plan](terraform-operations.md#bind-the-saved-plan-to-its-hash-and-to-state)). The owner's acceptance covers either stop point.

Run these only when their trigger occurs:

- [Roll back the delegation](#roll-back-the-delegation): only on its named triggers after the
  registrar change. Designed, never executed.
- [Retire the hosted zone](#retire-the-hosted-zone): at project end only. The order is designed
  and has never run; the destroy step is not designed.

> **Warning:** The rollback depends on a private export of the zone the previous provider serves,
> kept with its sha256, and on the previous name-server set. Have both before step 4.

> **Warning:** Retirement runs in a fixed order: the registrar first, then the wait, the
> certificate before the zone, and `prevent_destroy` lifted only in a reviewed change
> ([Public DNS](../../terraform/foundation/README.md#public-dns)).

## Before you start

- [ ] A registered apex domain at an external registrar, controlled by the operator, with a known
  renewal posture. Registration and renewal sit outside AWS and outside the AWS budget.
- [ ] Registrar access, with multi-factor sign-in, that can replace the domain's name-server set,
  plus knowledge of the domain's lock status and of whether the parent holds a DS record.
- [ ] Before the registrar change: a private export of the zone the previous provider serves, kept
  with its sha256, and the previous name-server set, both kept for rollback. Every record in that
  export stops resolving once Route 53 answers: this runbook publishes no record migration, and
  a record that must keep resolving is a STOP
  ([Change the name servers at the registrar](#change-the-name-servers-at-the-registrar)).
- [ ] The dedicated AWS account and an administrative operator session
  ([operator-access.md](operator-access.md)).
- [ ] Two shells. The budget read-back and the price re-check that the zone build requires run in
  the [exported shell](operator-access.md#export-role-credentials-once) of
  [cost-and-residue.md](cost-and-residue.md#before-you-start): a clean shell that holds one role
  credential and no profile. This page's Terraform and AWS CLI commands name `<profile>`, which
  that shell does not have, so run them, the applies included, in a shell where `<profile>` is
  signed in. No published rule requires an exported shell for this page's own steps. If you run
  one of them in an exported shell, as [terraform-operations.md](terraform-operations.md) does
  for a long or sensitive operation, drop `AWS_PROFILE=<profile>` and `--profile <profile>` from
  it.
- [ ] The four foundation inputs in an untracked `terraform.tfvars` and the state bucket in an
  untracked `backend.hcl` ([Input](../../terraform/foundation/README.md#input)).
- [ ] Tools: the workstation toolchain in [operator-access.md](operator-access.md) (Terraform, the
  AWS provider and the AWS CLI); `jq`, `unzip` and `shasum` (or `sha256sum`) for the plan review
  and binding in [terraform-operations.md](terraform-operations.md); `dig`; and `curl` for the
  RDAP read, which is optional in [Verify delegation](#verify-delegation) and is the source this
  page names for the lock status the [Registrar lock check](#registrar-lock-check) needs. RDAP is
  the registry's public registration-data service.
- [ ] A private directory outside every Git working tree for saved plans
  ([terraform-operations.md](terraform-operations.md)).
- [ ] The evidence tooling for this page's three campaigns
  ([evidence-handling.md](evidence-handling.md#before-you-start)): a private evidence root and a
  private run directory, a private literal list that holds the domain, the zone ID and the name
  servers, an address allowlist, and a redaction filter and a value-based, archive-aware sweep
  that fail closed. The project's own filter and sweep are not published, so you supply your own
  before the first campaign. Without them the evidence path stops at its step 2
  ([Normal path](evidence-handling.md#normal-path)).
- [ ] An approver for each mutating step: the zone apply, the registrar change, the certificate
  apply, and any rollback, retirement or destroy. This page calls the approver the owner (see
  [Conventions](#conventions)). Before the zone build the owner also gives two more decisions: on
  a build from nothing, written acceptance, before step 1, of where the normal path then ends;
  and approval of a price re-estimate, because the Route 53 price re-check stops for a zone build
  ([Build the zone on its own](#build-the-zone-on-its-own)).

### Shared steps this page links to

- Login, caller verification and session headroom: [operator-access.md](operator-access.md).
- Backend initialization, the reviewed saved-plan workflow, apply and the convergence plan:
  [terraform-operations.md](terraform-operations.md).
- The Route 53 pricing re-check and the orphan census: [cost-and-residue.md](cost-and-residue.md).
- Evidence capture, redaction and sealing: [evidence-handling.md](evidence-handling.md).
- What the root creates, its inputs, the zone-first, rebuild and retirement order, the cost and the
  write-access boundary: [Public DNS](../../terraform/foundation/README.md#public-dns); measured
  outcomes: [Status](../../terraform/foundation/README.md#status).

### Placeholders

- `<profile>` is the administrative profile. Terraform commands run in `terraform/foundation`,
  prefixed with `AWS_PROFILE=<profile>` as in [terraform-operations.md](terraform-operations.md).
- `<plan-file>` and `<private-dir>` are defined in
  [terraform-operations.md](terraform-operations.md): a saved plan lives outside every Git working
  tree.
- `<apex>` is the registered domain supplied as `public_domain`. `<parent>` is the zone that
  delegates `<apex>`, and `<parent-server>` each of its authoritative servers. In the validated
  deployment `<parent>` was the top-level domain; an apex under a multi-label public suffix, where
  the delegating zone sits below the top-level domain, has never been exercised. `<tld>` is the
  top-level domain, used only to find the registry's RDAP service.
- `<route53-ns>` is each of the four name servers Route 53 assigned, `<previous-ns>` each name
  server of the provider that served the domain before the cutover, and `<resolver>` a public
  resolver. `<rdap-base>` is the registry's RDAP base URL without its trailing `/`.

### Conventions

- A **saved plan** is a plan written to a file, reviewed, bound to its hash and to the state it was
  made from, and then applied exactly as reviewed
  ([terraform-operations.md](terraform-operations.md)).
- The **account check** compares the caller's account with the root's `allowed_account_id` and
  prints only a verdict
  ([Check the account before AWS commands](operator-access.md#check-the-account-before-aws-commands)).
- The **owner** is the approver: the person accountable for the AWS account, who gives written
  approval before each mutating step ([runbook index](README.md#conventions)).
- The six mandatory tags: the keys are set by
  [ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md), under Tagging and
  attribution, and the values by `default_tags` in
  [`providers.tf`](../../terraform/foundation/providers.tf), with `Component` overridden to `dns`
  in `dns.tf` and `certificate.tf`. A plan shows the default tags under `tags_all`, not `tags`, so
  the plan checks below read `tags_all`.
- No command prints an ARN or an account number. The zone ID and the certificate ARN are held in
  shell variables and never written down, and the domain and the name servers stay out of shared
  records.
- **Evidence campaigns.** A campaign is one bounded operation whose evidence set is kept together
  ([evidence-handling.md](evidence-handling.md#normal-path)). This page uses three: the zone
  build, from its plan to its read-back; the cutover, from the
  [Pre-cutover checks](#pre-cutover-checks) through the registrar change to the
  [Verify delegation](#verify-delegation) round that passes; and the certificate, from its plan,
  through the delegation check before its apply, to its read-backs and convergence plan. Sweep and
  seal each set when its campaign ends (steps 4 to 7 of the
  [evidence-handling.md Normal path](evidence-handling.md#normal-path)).
- **Raw DNS output.** Raw `dig` and RDAP output names the domain and the name servers, which are
  on the private literal list, so it is a private-input carrier: keep it outside the set, in the
  private run directory, and record only its sha256 in the set, with the results, classes and
  times each procedure names
  ([Capture a campaign evidence set](evidence-handling.md#capture-a-campaign-evidence-set),
  step 5).

## Procedures

### Build the zone on its own

**Validation:** DESIGNED-NOT-EXECUTED (never) · **Published command form:** not executed as written

**What this does.** It creates the hosted zone alone, so the certificate is not requested before
the registrar delegates to the zone.

Use it for a first build, for a rebuild from nothing, and for any rebuild that creates a new zone,
because a new zone gets new name servers.

Recovering the zone after a deletion outside Terraform is not covered: no reviewed sequence
exists, and re-delegation is urgent (see [Not yet exercised](#not-yet-exercised)). Stop and take
it to the owner ([When to stop](README.md#when-to-stop)).

**Before you start.**

- [ ] On a build from nothing: before step 1, the owner has accepted in writing that the normal
  path then ends at step 2 of [Plan and apply the certificate](#plan-and-apply-the-certificate),
  before any certificate exists, with this zone billing and the domain delegated to it (see the
  warning under [Normal path](#normal-path)). Without that acceptance, do not start.
- [ ] An administrative session, with the caller verified and enough session headroom
  ([Verify the resolved identity](operator-access.md#verify-the-resolved-identity),
  [Check session headroom before long operations](operator-access.md#check-session-headroom-before-long-operations)).
- [ ] Steps 1 to 5 of the [terraform-operations.md Normal path](terraform-operations.md#normal-path)
  done for `terraform/foundation` at the commit under review: the root's inputs and a new
  `<private-dir>` prepared, the [static checks](terraform-operations.md#run-the-static-checks) run,
  the root [initialized against its backend](terraform-operations.md#initialize-a-root-against-the-state-backend),
  [state inspected](terraform-operations.md#inspect-state-without-writing-it) with its serial,
  lineage and address digest recorded, and
  [debug logging kept off](terraform-operations.md#keep-terraform-debug-logging-off). Every plan
  of this root needs all four [inputs](../../terraform/foundation/README.md#input), DNS-only work
  included.
- [ ] The campaign's evidence set opened
  ([Capture a campaign evidence set](evidence-handling.md#capture-a-campaign-evidence-set)).
- [ ] The budget read back before this billable change
  ([Read back the budget and its alert states](cost-and-residue.md#read-back-the-budget-and-its-alert-states)),
  in the exported shell, not the shell that runs this procedure's commands
  ([Before you start](#before-you-start)).
- [ ] Route 53 pricing re-checked immediately before the apply
  ([Re-check prices before billable work](cost-and-residue.md#re-check-prices-before-billable-work)),
  also in the exported shell. For a zone build that re-check always stops: its price table has the
  zone rate but not the Route 53 query rate the zone also bills. So the owner approves a
  re-estimate before the apply. No written re-estimation procedure exists.
- [ ] No hosted zone for `<apex>` exists: step 1 of
  [Read back the hosted zone](#read-back-the-hosted-zone) returns `0`.
- [ ] The owner available to approve this apply: explicit written approval of the reviewed saved
  plan, identified by its sha256, given after step 2 and before step 3 (see the Next step of
  [Bind the saved plan to its hash and to state](terraform-operations.md#bind-the-saved-plan-to-its-hash-and-to-state)).

**Safety and authority.** Mutating, billable, owner-authorized. The zone costs 0.50 USD a month
from creation, not prorated, plus query charges. It is persistent; retiring it is
[Retire the hosted zone](#retire-the-hosted-zone), which has never run.

**Steps.**

1. Plan the zone alone into a saved plan. Terraform warns that resource targeting is in effect;
   that is expected for this step only. `-lock=false` is used only under the conditions in
   [Plan without taking the state lock](terraform-operations.md#plan-without-taking-the-state-lock).

   ```
   AWS_PROFILE=<profile> terraform plan -lock=false -input=false -no-color -detailed-exitcode -target=aws_route53_zone.public -out=<plan-file>
   echo $?
   ```

   Exit 2 means the plan has changes, as expected here; exit 0 or 1 is a STOP. Go on only if the
   plan output also contains the summary line `Plan: 1 to add, 0 to change, 0 to destroy.` and
   Terraform's warning that resource targeting is in effect.

2. Review the saved plan with [Review the saved plan](terraform-operations.md#review-the-saved-plan)
   against this shape:
   - exactly one resource to add, `aws_route53_zone.public`, and 0 to change, destroy or replace;
   - the zone is public (no VPC association), named `<apex>`, with `force_destroy` false;
   - the six mandatory tags in `tags_all`, with `Component` set to `dns`;
   - no `aws_acm_*` and no `aws_route53_record` address;
   - output changes: `public_zone_name_servers` created. What this targeted form shows for
     `public_certificate_arn` is unmeasured (see the Engineering notes). If
     `public_certificate_arn` appears among the output changes, the reviewed shape does not cover
     it: that is a STOP.

   Terraform marks a targeted plan incomplete, as the retained targeted plans of `terraform/dev`
   show on Terraform 1.15.5
   ([Build only the retained baseline](dev-network.md#build-only-the-retained-baseline)); this
   root's targeted form has never run. So this plan is expected to show `complete` as `false`.
   That is the one exception to the review's criteria: `applyable` must still be `true` and
   `errored` `false`, and every other criterion applies.

   Read the zone's attributes and tags in the plan text that step 1 of
   [Review the saved plan](terraform-operations.md#review-the-saved-plan) prints
   (`terraform show -no-color <plan-file>`).

   > **Warning:** Any `aws_acm_*` address in this plan is a STOP. Design-review reasoning, not
   > measurement: a certificate requested before delegation waits out Terraform's validation step
   > and is left in `PENDING_VALIDATION`, a class ADR-0018 names for the orphan scan, the check
   > for leftover resources that nothing owns
   > ([Run the orphan census](cost-and-residue.md#run-the-orphan-census), which has no ACM class
   > yet).

3. Bind the saved plan to its hash and to state, then apply exactly that plan, without
   re-planning ([Bind the saved plan to its hash and to state](terraform-operations.md#bind-the-saved-plan-to-its-hash-and-to-state),
   [Apply the reviewed saved plan](terraform-operations.md#apply-the-reviewed-saved-plan)).

   > **Warning:** This apply creates the billable zone. Run it only with explicit approval of this
   > plan, after the Route 53 price re-check, and with the owner's approval of its re-estimate.

   After this apply, go to step 4, not to the apply procedure's next step,
   [Confirm convergence](terraform-operations.md#confirm-convergence). Until
   [Plan and apply the certificate](#plan-and-apply-the-certificate) completes, a plain plan of
   this root is expected to show the certificate's three addresses as pending, and on a build
   from nothing the rest of the foundation as well, so the convergence check applies only after
   the certificate apply.

4. Run [Read back the hosted zone](#read-back-the-hosted-zone).

**Expected result.** The plan prints `Plan: 1 to add, 0 to change, 0 to destroy.` with the
targeting warning, and its review shows `applyable` `true`, `errored` `false` and `complete`
`false`. The apply reports 1 added, 0 changed, 0 destroyed, matching the reviewed
plan. One public hosted zone with four assigned name servers, and public DNS still answered by the
previous provider. After the validated apply, the live delegation had no name server in common with
the four assigned.

**PASS when.**

- [ ] The plan exited 2, printed `Plan: 1 to add, 0 to change, 0 to destroy.` with the targeting
  warning, and matched the shape in step 2 exactly.
- [ ] The review showed `applyable` `true` and `errored` `false`, and every review criterion held
  apart from `complete`, which is `false` for this targeted plan.
- [ ] The apply's counts equal the reviewed plan.
- [ ] [Read back the hosted zone](#read-back-the-hosted-zone) passed.

**STOP if.**

- The plan exits 0 or 1.
- The plan differs from the shape above in any way.
- The review shows `applyable` `false` or `errored` `true`, or any review criterion other than
  `complete` fails.
- A hosted zone for `<apex>` already exists.
- Any `aws_acm_*` address would be created.
- On a build from nothing, the owner has not accepted in writing where the normal path then ends.
- On a build from nothing, the binding check's state read prints nothing: this is the root's first
  apply, and an empty result is a mismatch no published procedure resolves
  ([Bind the saved plan](terraform-operations.md#bind-the-saved-plan-to-its-hash-and-to-state)).
- The Route 53 price re-check stopped, and the owner has not approved a re-estimate.

**If it fails.** A plan that differs from the shape is not approved; correct and plan again as in
[Review the saved plan](terraform-operations.md#review-the-saved-plan). A failed or interrupted
apply follows
[Stop after a failed or interrupted apply](terraform-operations.md#stop-after-a-failed-or-interrupted-apply).

**Evidence to keep.** The saved plan's sha256, the plan-shape result, the apply result line and the
read-back results, captured as in [evidence-handling.md](evidence-handling.md). Raw plan and apply
output of this root prints private values, including the evidence bucket name, the zone ID and the
name servers, so it stays private. This campaign ends when the read-back passes: sweep and seal
its set then ([Conventions](#conventions)).

**Next step.** [Pre-cutover checks](#pre-cutover-checks).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | DESIGNED-NOT-EXECUTED (never) |
| Published form | not executed as written (derived from the zone-first order in [Public DNS](../../terraform/foundation/README.md#public-dns), whose `terraform apply -target` sentence gives the order only; this saved-plan form is the procedure. The plan command is the plan form of [terraform-operations.md](terraform-operations.md) with `-target` added. The one validated zone build, executed 2026-09-23, applied a reviewed saved plan made from commit `69c5770`, whose configuration declared the zone and no certificate, so it needed no `-target`. It was applied from that commit before the merge, and the same foundation tree was confirmed on merged main afterwards) |
| Evidence basis | [Status](../../terraform/foundation/README.md#status), zone paragraph; commit `69c5770`; retained private evidence of the 2026-09-22 saved plan and the 2026-09-23 apply and read-back |
| Authority | Explicit owner approval of the zone apply |
| Cost | 0.50 USD a month from creation, not prorated, plus query charges ([Public DNS](../../terraform/foundation/README.md#public-dns)) |

**Known limitations.**

- The `-target` form has never run. Until
  [Plan and apply the certificate](#plan-and-apply-the-certificate) completes, a plain plan of
  this root is expected to show the certificate's three addresses as pending, and on a build
  from nothing the rest of the foundation as well, so the no-drift convergence check applies
  only after the certificate apply.
- The validated zone plan showed `public_zone_name_servers` created. It was made from a
  configuration without `certificate.tf`, so how a targeted plan on the current configuration
  shows `public_certificate_arn` has never been observed.

### Read back the hosted zone

**Validation:** AWS-VALIDATED (2026-09-23) · **Published command form:** not executed as written

**What this does.** It confirms that the zone is the one this root declares and holds nothing
unexpected, and it obtains the four assigned name servers. Other procedures reuse its steps: step 1
before the build, step 5 for the name servers, and steps 2 and 4 after the certificate and before
retirement.

**Before you start.**

- [ ] A session with the identity and account checks passed
  ([Verify the resolved identity](operator-access.md#verify-the-resolved-identity),
  [Check the account before AWS commands](operator-access.md#check-the-account-before-aws-commands)).

**Safety and authority.** Read-only; no approval needed.

> **Warning:** Nothing else checks the account for these AWS CLI calls, and a `0` at step 1 says
> nothing about the intended account without that check.

**Steps.**

1. Count the hosted zones named `<apex>`:

   ```
   aws route53 list-hosted-zones --profile <profile> \
     --query "length(HostedZones[?Name=='<apex>.'])"
   ```

2. Hold the zone ID in a variable:

   ```
   zone_id=$(aws route53 list-hosted-zones --profile <profile> \
     --query "HostedZones[?Name=='<apex>.'].Id" --output text)
   zone_id=${zone_id##*/}
   ```

3. Read the zone type, the name-server count and the tags:

   ```
   aws route53 get-hosted-zone --profile <profile> --id "$zone_id" \
     --query '{Private: HostedZone.Config.PrivateZone, NameServers: length(DelegationSet.NameServers)}'
   aws route53 list-tags-for-resource --profile <profile> --resource-type hostedzone \
     --resource-id "$zone_id" --query 'ResourceTagSet.Tags[].[Key,Value]' --output text
   ```

4. List the record sets:

   ```
   aws route53 list-resource-record-sets --profile <profile> --hosted-zone-id "$zone_id" \
     --query 'ResourceRecordSets[].[Type,TTL,Name,ResourceRecords[0].Value]' --output text
   ```

5. When the name servers are needed, for the pre-cutover checks or the registrar, read them from
   the zone's delegation set:

   ```
   aws route53 get-hosted-zone --profile <profile> --id "$zone_id" \
     --query 'DelegationSet.NameServers' --output text
   ```

**Expected result.**

- Step 1 returns `1`.
- `Private` is `false` and `NameServers` is `4`.
- The six mandatory tags, with `Component` set to `dns`.
- Before the certificate, record types `NS` and `SOA` only. After it, `NS`, `SOA` and exactly
  one `CNAME`, the certificate's validation record, with TTL 300. The observed TTLs of `NS` and
  `SOA` were 172800 and 900.

**PASS when.**

- [ ] Every expected value above holds.

**STOP if.**

- More than one zone for `<apex>`.
- A private zone.
- A name-server count other than four.
- A missing or different tag.
- Any record type or count other than those above.

**If it fails.** This runbook has no corrective procedure for a zone that differs. Work stays
stopped until a reviewed decision is taken under explicit approval
([When to stop](README.md#when-to-stop)).

**Evidence to keep.** The result of each expected value, never the zone ID or the name servers.

**Next step.** After [Build the zone on its own](#build-the-zone-on-its-own):
[Pre-cutover checks](#pre-cutover-checks). When another procedure sent you here, return to it.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-23) |
| Published form | not executed as written (the validated read-backs made the same read-only calls with full JSON output into a private checker; the published form adds `--query` projections) |
| Evidence basis | [Status](../../terraform/foundation/README.md#status), zone and certificate paragraphs; retained private evidence of two read-backs on 2026-09-23, 8 of 8 checks after the zone apply and the zone checks of the certificate read-back, each by a checker qualified offline before use |
| Authority | None (read-only) |
| Cost | None |

The validated read-back also checked the foundation state and a no-drift plan; those checks
belong to [terraform-operations.md](terraform-operations.md).

### Pre-cutover checks

**Validation:** AWS-VALIDATED (2026-09-23, verified on public DNS) · **Published command form:** executed as written

**What this does.** Before the registrar change, it establishes what the parent delegates to now,
confirms that the parent holds no DS record, and confirms that all four Route 53 servers already
answer for the zone. The parent's answer for `<apex>` is a referral: it names the name servers the
domain is delegated to. [Verify delegation](#verify-delegation) and
[Roll back the delegation](#roll-back-the-delegation) reuse these commands.

Here and in [Verify delegation](#verify-delegation), a parent server **refers to Route 53** when
its referral names any of the four assigned `<route53-ns>`. Name servers of any other Route 53
hosted zone, such as an earlier zone for `<apex>` in another account, do not count: if the parent
refers to those, they are the `<previous-ns>` set, and that zone is the one to export before the
change. A zone that no longer exists cannot be exported, which stops the change
([Change the name servers at the registrar](#change-the-name-servers-at-the-registrar)). For this
root's own zone deleted outside Terraform, see [Build the zone on its own](#build-the-zone-on-its-own).

**Before you start.**

- [ ] [Read back the hosted zone](#read-back-the-hosted-zone) passed, and its step 5 supplied the
  four `<route53-ns>` values.
- [ ] The cutover campaign's evidence set opened
  ([Capture a campaign evidence set](evidence-handling.md#capture-a-campaign-evidence-set)); it
  runs to the [Verify delegation](#verify-delegation) round that passes ([Conventions](#conventions)).

**Safety and authority.** Read-only; no approval needed.

**Steps.**

1. Find the parent's authoritative servers. Each `NS` answer is a `<parent-server>`:

   ```
   dig +time=5 +tries=2 <parent> NS
   ```

2. At each `<parent-server>`, read the referral and check for a DS record:

   ```
   dig +norecurse +time=5 +tries=2 @<parent-server> <apex> NS
   dig +norecurse +time=5 +tries=2 @<parent-server> <apex> DS
   ```

   The referral is in the AUTHORITY section, not the ANSWER section, so do not use `+short`
   here. Note the referral's TTL: it is the parent's NS TTL, which the rollback and retirement
   waits depend on.

3. At each `<route53-ns>`, confirm the zone is served:

   ```
   dig +norecurse +time=5 +tries=2 @<route53-ns> <apex> SOA
   dig +norecurse +time=5 +tries=2 @<route53-ns> <apex> NS
   ```

4. At the public resolvers 1.1.1.1 and 8.8.8.8, read what clients currently see:

   ```
   dig +time=5 +tries=2 @<resolver> <apex> NS
   dig +time=5 +tries=2 @<resolver> <apex> DS
   ```

**Expected result.**

- Step 2: every parent server refers to the same `<previous-ns>` set and none refers to Route
  53 yet. The DS query returns `NOERROR` with no answer.
- Step 3: every Route 53 server answers `NOERROR` with the `aa` flag, all four report the same
  SOA serial, and the NS answer is exactly the four assigned name servers.
- Step 4: both resolvers return the `<previous-ns>` set and no DS record.

**PASS when.**

- [ ] Every parent server refers to the same `<previous-ns>` set, and none refers to Route 53.
- [ ] No parent server returns a DS record.
- [ ] Every Route 53 server answers `NOERROR` with `aa`, with one SOA serial and exactly the four
  assigned name servers.
- [ ] 1.1.1.1 and 8.8.8.8 return the `<previous-ns>` set and no DS record.
- [ ] The parent's NS TTL is noted.

**STOP if.**

- A DS record exists at the parent. Validating resolvers would answer `SERVFAIL` for the domain
  once an unsigned Route 53 zone takes over, so DNSSEC has to be dealt with at the registrar
  first. That path has never been exercised here.
- A Route 53 server answers without `aa`, answers `REFUSED`, or returns a different NS set.
- The parent servers disagree with each other, or already refer to Route 53, that is, to any of
  the four `<route53-ns>`.

**If it fails.** These checks change nothing. No procedure in this suite resolves a STOP here, so
do not make the registrar change. Handling a DS record at the registrar is listed under
[Not yet exercised](#not-yet-exercised).

**Evidence to keep.** The raw `dig` output with its start and end times, kept privately, because it
names the domain and every name server: it stays in the private run directory, and the set holds
its sha256, the result of each PASS item and the times ([Conventions](#conventions)).

**Next step.** [Registrar lock check](#registrar-lock-check), never exercised, then
[Change the name servers at the registrar](#change-the-name-servers-at-the-registrar). The
[CAA check](#caa-check), also never exercised, comes later, after
[Verify delegation](#verify-delegation) passes.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-23, verified on public DNS) |
| Published form | executed as written |
| Evidence basis | Retained private evidence of the preflight run on 2026-09-23 immediately before the registrar change, evaluated by a private checker qualified offline against five failing cases: a missing `aa` flag, `REFUSED`, a wrong NS set, a parent already delegating to Route 53, and a DS record present |
| Authority | None (read-only) |
| Cost | None beyond negligible Route 53 query charges |

### Change the name servers at the registrar

**Validation:** EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-09-23) · **Published command form:** not executed as written

**What this does.** It delegates `<apex>` to the Route 53 zone. It is a manual change at the
registrar, outside Terraform and outside AWS, so there is no command. Registrar interfaces differ,
so the steps are registrar-neutral. The outcome is proven separately, on public DNS, by
[Verify delegation](#verify-delegation).

**Before you start.**

- [ ] [Pre-cutover checks](#pre-cutover-checks) passed.
- [ ] The zone the previous provider serves has been exported, and the export is kept privately
  with its sha256; the rollback depends on it. The validated run took it at the registrar. This
  runbook publishes no export method and no test that an export is complete
  (see [Reproducibility gaps](#reproducibility-gaps)).
- [ ] The previous name-server set is kept privately, for rollback.
- [ ] A decision for every record in the export: migrate it into Route 53, or accept that it stops
  resolving once Route 53 answers. The validated deployment migrated none, and migration has
  never been exercised. This runbook supports only the second outcome: no migration procedure is
  published, and a migrated record would fail the record check of
  [Read back the hosted zone](#read-back-the-hosted-zone), which allows only `NS`, `SOA` and the
  certificate's validation record. If any record in the export must keep resolving, STOP.
- [ ] The registrar's lock status is known and shows no update lock
  ([Registrar lock check](#registrar-lock-check), for which no reviewed procedure exists).
- [ ] The four assigned name servers, from step 5 of
  [Read back the hosted zone](#read-back-the-hosted-zone).
- [ ] Explicit approval of the change.

**Safety and authority.** Mutating, owner-authorized. The owner approves the registrar change, and
whoever holds registrar access carries it out. No AWS cost; registrar charges sit outside the AWS
budget.

**Steps.**

1. At the registrar, replace the domain's complete name-server set with exactly the four assigned
   name servers.

   > **Warning:** Once Route 53 answers, every record in the export that was not migrated stops
   > resolving. The rollback, [Roll back the delegation](#roll-back-the-delegation), is designed
   > and has never been executed, and it depends on the export and the previous name-server set.

2. Change nothing else: no DNSSEC setting, no record, no contact or lock setting.

   > **Warning:** If the registrar asks to change DNSSEC or anything besides the name servers,
   > STOP.

3. Record the UTC time of the change.
4. Start [Verify delegation](#verify-delegation).

**Expected result.** The registry's RDAP record lists the new name servers before the parent
servers return them. Measured on
2026-09-23, from the RDAP `last changed` time: the one RDAP read, about 12 minutes after it,
already listed the four new name servers while the parent servers still returned the previous
set. The parent servers returned the previous set at four checks up to about 23 minutes after the
change, and the new set at the check 31 minutes after it.

**PASS when.**

- [ ] The registrar accepted a change of the name servers only.
- [ ] The values entered are exactly the four assigned name servers.
- [ ] The UTC time of the change is recorded.

**STOP if.**

- Before the change: any record in the export must keep resolving, or the lock status shows an
  update lock. No procedure in this runbook resolves either; work stays stopped until a reviewed
  decision is taken under explicit approval ([When to stop](README.md#when-to-stop)).
- Before the change: the lock status is not known. Do not make the change until it is.
- Before the change: no export of the zone the previous provider serves, or no record of the
  previous name-server set. The rollback depends on both.
- The registrar refuses the change, or asks to change DNSSEC or anything besides the name
  servers.
- The values entered differ from the four assigned name servers.

**If it fails.** If the registrar refuses the change, nothing in AWS has changed. Stop and leave
the delegation as it is. If the cutover fails after the change, the rollback is
[Roll back the delegation](#roll-back-the-delegation), designed and never executed; its triggers
come from [Verify delegation](#verify-delegation).

**Evidence to keep.** The UTC time of the change, a statement that only the name servers changed,
and the sha256 of the privately kept export. Registrar screenshots and exports carry the domain
and stay private, outside the set ([Conventions](#conventions)).

**Next step.** [Verify delegation](#verify-delegation).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-09-23) |
| Published form | not executed as written (a registrar-neutral description; registrar interfaces differ, and no step list for the interface used was retained) |
| Evidence basis | The change was made by hand in the registrar's control panel and is attested by the person who made it; that is not AWS evidence. The registry's RDAP record, captured privately on 2026-09-23, shows a change at that time. The outcome is proven separately, by [Verify delegation](#verify-delegation) |
| Authority | Explicit owner approval of the registrar change, carried out by whoever holds registrar access |
| Cost | None in AWS. Registrar charges sit outside the AWS budget ([ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md)) |

- In the validated run the export was taken at the registrar on 2026-09-23 and retained
  privately. It is a registrar-side action, outside the AWS labels.
- The root's `public_zone_name_servers` output carries the same values as step 5 of
  [Read back the hosted zone](#read-back-the-hosted-zone); reading that output was not part of
  the validated run.

### Verify delegation

**Validation:** AWS-VALIDATED (2026-09-23, verified on public DNS) · **Published command form:** not executed as written

**What this does.** It proves on public DNS that the parent delegates `<apex>` to the Route 53
zone. Repeat it after the registrar change until every parent server refers to Route 53 (NEW in
step 3: exactly the four `<route53-ns>`), and run it again immediately before the certificate
apply.

**Before you start.**

- [ ] [Change the name servers at the registrar](#change-the-name-servers-at-the-registrar) is
  done, and the UTC time of the change is recorded.
- [ ] The `<parent-server>` list, the four `<route53-ns>` values, the `<previous-ns>` set and the
  parent's NS TTL from [Pre-cutover checks](#pre-cutover-checks).

**Safety and authority.** Read-only; no approval needed.

**Steps.**

1. Run the NS and SOA queries of steps 1 to 4 of [Pre-cutover checks](#pre-cutover-checks)
   again, without the two DS queries:
   - the `<parent>` NS query:

     ```
     dig +time=5 +tries=2 <parent> NS
     ```

   - the NS query at each `<parent-server>`; the referral is in the AUTHORITY section, so do not
     use `+short`:

     ```
     dig +norecurse +time=5 +tries=2 @<parent-server> <apex> NS
     ```

   - the SOA and NS queries at each `<route53-ns>`:

     ```
     dig +norecurse +time=5 +tries=2 @<route53-ns> <apex> SOA
     dig +norecurse +time=5 +tries=2 @<route53-ns> <apex> NS
     ```

   - the NS query at 1.1.1.1 and 8.8.8.8:

     ```
     dig +time=5 +tries=2 @<resolver> <apex> NS
     ```

2. Optionally, read the registry's RDAP record. `<rdap-base>` is the base URL that IANA's RDAP
   bootstrap file for DNS, `https://data.iana.org/rdap/dns.json`, lists for `<tld>`, with its
   trailing `/` removed.

   ```
   curl -q -s --max-time 20 <rdap-base>/domain/<apex>
   ```

   Read `nameservers`, `status`, `secureDNS.delegationSigned` and the `last changed` event.

3. Classify each parent server's referral:

   | Class | Referral | Action |
   |---|---|---|
   | OLD | the `<previous-ns>` set | Wait and repeat |
   | NEW | exactly the four Route 53 name servers | Pass for that server |
   | MIXED | some of each | STOP |
   | WRONG | anything else, including an incomplete set | STOP |

4. If the parent's NS TTL has passed since the recorded change time, also run the resolver query
   at 1.1.1.1, 8.8.8.8 and 9.9.9.9. This is the resolver trigger of
   [Roll back the delegation](#roll-back-the-delegation); 9.9.9.9 is checked only for that
   trigger and is not a pass criterion.

   ```
   dig +time=5 +tries=2 @<resolver> <apex> NS
   ```

**Expected result.** Pass when every parent server is NEW, every Route 53 server still answers
with `aa`, one SOA serial and the four-server NS set, and 1.1.1.1 and 8.8.8.8 return the Route
53 set. A resolver still returning the previous set means propagation is in progress, until the
parent's NS TTL has passed since the change; after that it is a STOP and a rollback trigger
(step 4). RDAP lists the four name servers and `delegationSigned` false.

Measured on 2026-09-23: every parent server was NEW 31 minutes after the change, and 1.1.1.1
and 8.8.8.8 returned the Route 53 set when checked 55 minutes after it, with cached NS TTLs of
172800 s and 21600 s. The final check, immediately before the certificate apply, also passed.

**PASS when.**

- [ ] Every parent server is NEW.
- [ ] Every Route 53 server still answers with `aa`, one SOA serial and the four-server NS set.
- [ ] 1.1.1.1 and 8.8.8.8 return the Route 53 set.
- [ ] If RDAP was read: it lists the four name servers and `delegationSigned` false.

**STOP if.**

- MIXED or WRONG at any parent server.
- A Route 53 server stops answering authoritatively, answers `SERVFAIL` or `REFUSED`, or returns
  another NS set.
- A resolver returns a set that is neither the previous set nor the Route 53 set.
- At step 4, once the parent's NS TTL has passed since the change, 1.1.1.1, 8.8.8.8 or 9.9.9.9
  still does not return the Route 53 set.

**If it fails.**

- OLD at a parent server: wait and repeat. No designed bound exists for how long OLD may persist;
  the RDAP read in step 2 is the available way to tell whether the registry has taken the change
  at all (see the Engineering notes). This runbook publishes no repeat interval; record the time
  of each round.
- The previous set at a resolver: wait and repeat until the parent's NS TTL has passed since the
  change. After that it is the step 4 STOP, a rollback trigger.
- Design-review reasoning, not measurement: transient `SERVFAIL` from a resolver still holding the
  old delegation is expected until the parent's NS TTL has passed, and is not a reason to roll
  back. None was observed in the validated run.
- A STOP condition that persists is a trigger for
  [Roll back the delegation](#roll-back-the-delegation) only when it is one of the triggers
  listed there, which are the only rollback triggers. Any other persistent STOP has no published
  route: work stays stopped until the owner decides ([When to stop](README.md#when-to-stop)).

**Evidence to keep.** The raw `dig` and RDAP output, privately, in the private run directory, with
only its sha256 in the set; in the set, the class of each server and resolver, and the time of
each round ([Conventions](#conventions)). The cutover campaign ends with the round that passes:
sweep and seal its set then. The check immediately before the certificate apply belongs to the
certificate's campaign.

**Next step.** [CAA check](#caa-check), then
[Plan and apply the certificate](#plan-and-apply-the-certificate), which runs this procedure again
immediately before its apply.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-23, verified on public DNS) |
| Published form | not executed as written (the post-change checks ran the step 1 queries in this form, and the RDAP read in this form with the registry's base URL already known; how that base URL was found was not recorded, so the bootstrap lookup is derived. The DS queries of the pre-cutover checks were not repeated after the change and are not part of this procedure) |
| Evidence basis | [Status](../../terraform/foundation/README.md#status), zone paragraph; retained private evidence of the verification rounds on 2026-09-23, from the first check after the change to the final check immediately before the certificate apply, evaluated by a private checker qualified offline against six failing cases and three classification cases |
| Authority | None (read-only) |
| Cost | None beyond negligible Route 53 query charges |

Step 4 carries the resolver trigger of [Roll back the delegation](#roll-back-the-delegation) into
this procedure. Its 9.9.9.9 query never ran after the parent returned the new set (see below).

**Known limitations.**

- Resolver convergence is claimed only for 1.1.1.1 and 8.8.8.8. 9.9.9.9 and 208.67.222.222 were
  queried only while the parent still returned the previous set. The written cutover design
  also asked for 9.9.9.9 to converge before the certificate; that was never measured, and the
  certificate apply went ahead on the two resolvers above. Design-review reasoning, not
  measurement, held that ACM's validation depends on ACM's own resolution rather than on public
  resolvers.
- RDAP's `last changed` event is not proof of delegation. The one RDAP read, about 12 minutes
  after that event, already listed the new name servers while the parent servers still returned
  the previous set; they returned the new set 31 minutes after the event.
- No designed bound exists for how long OLD may persist, so a change the registry refused would
  look like slow propagation. The measured transition took 31 minutes. The RDAP read is the
  available way to tell whether the registry has taken the change at all: in the validated run it
  listed the new set while the parent still answered OLD.
- Delegation was last measured on 2026-09-23, and no periodic re-check exists. Run this
  procedure to learn the current state.

### Plan and apply the certificate

**Validation:** AWS-VALIDATED (2026-09-23) · **Published command form:** not executed as written

**What this does.** It requests the certificate for the apex and one wildcard beneath it, and
completes its DNS validation once the zone is delegated. The plan covers the whole root, without
`-target`, and adds the certificate, its validation record in the zone and Terraform's validation
step.

**Before you start.**

- [ ] [Verify delegation](#verify-delegation) passes at step 3, immediately before the apply. The
  reviewed design also required it to pass before the plan; the validated run planned first (see
  the Engineering notes).
- [ ] The [CAA check](#caa-check) passes for `<apex>`, after [Verify delegation](#verify-delegation)
  has passed: no CAA record at `<apex>` or its parent stops Amazon's certificate authority. It
  was never exercised as a step.
- [ ] The rest of the foundation root is already applied, as it was in the validated run; the
  step 2 shape assumes it. On a build from nothing no reviewed shape exists for the combined
  plan, and step 2 stops (see [Reproducibility gaps](#reproducibility-gaps)).
- [ ] Steps 1 to 5 of the [terraform-operations.md Normal path](terraform-operations.md#normal-path)
  done for `terraform/foundation` at the reviewed commit: the root's inputs and a new
  `<private-dir>` prepared, the [static checks](terraform-operations.md#run-the-static-checks) run,
  the root [initialized against its backend](terraform-operations.md#initialize-a-root-against-the-state-backend),
  [state inspected](terraform-operations.md#inspect-state-without-writing-it) with its serial,
  lineage and address digest recorded, and
  [debug logging kept off](terraform-operations.md#keep-terraform-debug-logging-off).
- [ ] The campaign's evidence set opened
  ([Capture a campaign evidence set](evidence-handling.md#capture-a-campaign-evidence-set)).
- [ ] The session outlasts Terraform's validation step, which can wait up to the AWS provider's
  default create timeout of 75 minutes. Set `<required-minutes>` as step 1 of
  [Check session headroom before long operations](operator-access.md#check-session-headroom-before-long-operations)
  describes: at least those 75 minutes, plus the step 5 read-backs and convergence plan, plus a
  margin. This runbook publishes no measured duration for step 5, and no margin rule exists. The
  check runs at step 4; only a re-read expiry decides, so signing in again is not a substitute.
- [ ] The owner available to approve the apply: explicit written approval of the reviewed saved
  plan, identified by its sha256, given after the plan review and before step 4 (see the Next
  step of
  [Bind the saved plan to its hash and to state](terraform-operations.md#bind-the-saved-plan-to-its-hash-and-to-state)).

**Safety and authority.** Mutating, owner-authorized. The approval is to apply exactly the reviewed
saved plan. The certificate is non-exportable and carries no charge; the zone's charge is
unchanged.

**Steps.**

1. From the reviewed commit, produce a saved plan of the whole root, without `-target`.
   `-lock=false` is used only under the conditions in
   [Plan without taking the state lock](terraform-operations.md#plan-without-taking-the-state-lock).

   ```
   AWS_PROFILE=<profile> terraform plan -lock=false -input=false -no-color -detailed-exitcode -out=<plan-file>
   echo $?
   ```

   Exit 2 means the plan has changes; exit 1, or exit 0 when a change is expected, is a STOP
   ([Plan to a saved file](terraform-operations.md#plan-to-a-saved-file)). Review the plan with
   [Review the saved plan](terraform-operations.md#review-the-saved-plan). Record its sha256 and
   the state serial and lineage it was made from, as the binding step in
   [Bind the saved plan to its hash and to state](terraform-operations.md#bind-the-saved-plan-to-its-hash-and-to-state)
   does.

2. Check the plan against this shape, which assumes the rest of the foundation is already
   applied, as it was in the validated run:
   - exactly three to add: `aws_acm_certificate.public`,
     `aws_route53_record.certificate_validation` and `aws_acm_certificate_validation.public`;
     0 to change and 0 to destroy; every other address, `aws_route53_zone.public` included, is a
     no-op;
   - the certificate's domain is `<apex>`, and its subject alternative names are exactly
     `<apex>` and `*.<apex>`, because ACM lists the apex among them;
   - validation method `DNS`, export `DISABLED`, and the six mandatory tags in `tags_all` with
     `Component` set to `dns`;
   - the validation record goes into this zone with TTL 300; its name and value are known only
     after apply;
   - the output `public_certificate_arn` is created.

   Read these attributes and tags in the plan text that step 1 of
   [Review the saved plan](terraform-operations.md#review-the-saved-plan) prints
   (`terraform show -no-color <plan-file>`). The validated run checked the shape with a private
   checker, which is not published (see the Engineering notes).

   > **Warning:** On a build from nothing, this full plan also adds the rest of the foundation.
   > That combined plan has never run, and the three-address shape above does not describe it.
   > That is a STOP: no reviewed shape exists for it.

3. Immediately before the apply, run [Verify delegation](#verify-delegation) again. It must pass
   in full, as in the validated run: every parent server NEW, every Route 53 server
   authoritative, and 1.1.1.1 and 8.8.8.8 returning the Route 53 set.

   > **Warning:** Never apply the certificate before [Verify delegation](#verify-delegation)
   > passes.

4. Run [Check session headroom before long operations](operator-access.md#check-session-headroom-before-long-operations)
   with `<required-minutes>`, in the shell that will run the apply. Go on only if it exits 0; if
   not, follow its failure handling. Then run the binding check in
   [Bind the saved plan to its hash and to state](terraform-operations.md#bind-the-saved-plan-to-its-hash-and-to-state)
   (hash, serial and lineage), then apply exactly that plan, without re-planning
   ([Apply the reviewed saved plan](terraform-operations.md#apply-the-reviewed-saved-plan)).

   > **Warning:** Apply only with the owner's explicit written approval of this saved plan,
   > identified by its sha256.

   > **Warning:** A validation step that does not complete is a failed apply. Stop and inspect,
   > and apply nothing further, from this plan or a new one.

5. Run [Read back the certificate](#read-back-the-certificate) and
   [Read back the hosted zone](#read-back-the-hosted-zone), then the convergence plan in
   [Confirm convergence](terraform-operations.md#confirm-convergence), which must exit 0.

**Expected result.** 3 added, 0 changed, 0 destroyed. In the validated run the certificate was
issued during the apply, less than a minute after it started, and the convergence plan then
reported no changes.

**PASS when.**

- [ ] The plan matched the shape in step 2.
- [ ] [Verify delegation](#verify-delegation) passed in full at step 3.
- [ ] The headroom check exited 0 at step 4, before the apply.
- [ ] The sha256, serial and lineage matched at step 4.
- [ ] The apply reported 3 added, 0 changed, 0 destroyed.
- [ ] [Read back the certificate](#read-back-the-certificate) and
  [Read back the hosted zone](#read-back-the-hosted-zone) passed.
- [ ] The convergence plan exited 0.

**STOP if.**

- Any difference from the plan shape, including any destroy or replacement.
- At step 3, any parent server not NEW, any Route 53 server not answering authoritatively, or
  1.1.1.1 or 8.8.8.8 not returning the Route 53 set.
- A sha256, serial or lineage mismatch at step 4.
- Too little session headroom for the validation wait: the headroom check at step 4 does not
  exit 0.

**If it fails.**

- A plan that differs from the shape is not approved
  ([Review the saved plan](terraform-operations.md#review-the-saved-plan)). A binding mismatch
  follows
  [Bind the saved plan to its hash and to state](terraform-operations.md#bind-the-saved-plan-to-its-hash-and-to-state).
- The combined plan of a build from nothing has no published route. Work stays stopped until a
  reviewed decision is taken under explicit approval ([When to stop](README.md#when-to-stop)).
  Meanwhile the zone keeps billing and the domain stays delegated to it.
- A validation step that does not complete is a failed apply. Follow the stop-and-inspect
  procedure for a failed or interrupted apply in
  [Stop after a failed or interrupted apply](terraform-operations.md#stop-after-a-failed-or-interrupted-apply):
  no further apply, from this plan or a new one. Design-review reasoning, not measurement: the
  apply ends with an error at the provider's create timeout, and the certificate remains,
  probably in `PENDING_VALIDATION`, the provisioning failure class ADR-0018 names for the orphan
  scan. Any re-apply is a separate reviewed decision; no recovery procedure exists (see
  [Not yet exercised](#not-yet-exercised)).

**Evidence to keep.** The saved plan's sha256 and the binding check's results, the plan-shape
result, the delegation check's classes, the headroom line, the apply result line, the read-back
results and the convergence exit code, captured as in [evidence-handling.md](evidence-handling.md).
This campaign ends with the convergence plan: sweep and seal its set then
([Conventions](#conventions)).

**Next step.** The normal path ends after step 5. The next gate is binding the certificate to the
load balancer through the ingress annotation, inside a runtime window. It is not implemented and
is outside this suite ([runtime validation](../validation/runtime-validation.md)).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-23) |
| Published form | not executed as written (the plan and apply commands are those of [terraform-operations.md](terraform-operations.md), and the validated run used them from a detached working tree at commit `ac87cb7`. It differed in three ways: its init added `-plugin-dir`, a private checker checked the plan shape instead of the checklist below, and before the apply it re-checked the plan's hash but not the state serial and lineage that step 4 binds) |
| Evidence basis | [Status](../../terraform/foundation/README.md#status), certificate paragraph; commit `ac87cb7`; retained private evidence of the 2026-09-23 plan, its sha256 binding, the delegation check immediately before the apply, the apply and the convergence plan |
| Authority | Explicit owner approval to apply exactly the reviewed saved plan |
| Cost | None. The certificate is non-exportable and carries no charge ([ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md)); the zone's charge is unchanged |

The steps above are the order the validated run followed. Its plan was produced after the last
check that still showed the previous set, about five minutes earlier, and before the first check
that showed the new set, about two minutes after the plan finished. The delegation check ran
between plan and apply. Design-review reasoning, not measurement: the plan does not depend on
delegation; the apply's validation step does.

Headroom was not recorded for the validated certificate apply.

**Known limitations.**

- On a build from nothing, this full plan also adds the rest of the foundation. That combined
  plan has never run, and the three-address shape above does not describe it.
- The reviewed design planned the certificate only after the post-change delegation checks had
  passed. The validated run produced its plan before the parent servers returned the new set,
  and gated only the apply.
- The validated apply re-checked the saved plan's hash, but not the state serial and lineage
  that step 4 now binds.

### Read back the certificate

**Validation:** AWS-VALIDATED (2026-09-23) · **Published command form:** not executed as written

**What this does.** It confirms that the issued certificate matches what this root declares.

**Before you start.**

- [ ] A session with the identity and account checks passed
  ([Verify the resolved identity](operator-access.md#verify-the-resolved-identity),
  [Check the account before AWS commands](operator-access.md#check-the-account-before-aws-commands)).
  `terraform output` reads only state and the AWS CLI calls are outside Terraform, so nothing else
  checks the account.
- [ ] `terraform/foundation` initialized against its backend
  ([Initialize a root against the state backend](terraform-operations.md#initialize-a-root-against-the-state-backend)).

**Safety and authority.** Read-only; no approval needed. The ARN stays in a shell variable and is
never written down.

**Steps.**

1. Hold the certificate ARN in a variable:

   ```
   cert_arn=$(AWS_PROFILE=<profile> terraform output -raw public_certificate_arn)
   ```

2. Read the certificate and its tags:

   ```
   aws acm describe-certificate --profile <profile> --region us-east-1 --certificate-arn "$cert_arn" \
     --query 'Certificate.{Status:Status,Type:Type,Domain:DomainName,SANs:SubjectAlternativeNames,Validation:DomainValidationOptions[].[DomainName,ValidationMethod,ValidationStatus,ResourceRecord.Name,ResourceRecord.Value],Export:Options.Export,Key:KeyAlgorithm,InUseBy:length(InUseBy || `[]`),Renewal:RenewalEligibility,NotAfter:NotAfter}'
   aws acm list-tags-for-certificate --profile <profile> --region us-east-1 \
     --certificate-arn "$cert_arn" --query 'Tags[].[Key,Value]' --output text
   ```

3. List the zone's record sets with steps 2 and 4 of
   [Read back the hosted zone](#read-back-the-hosted-zone); step 2 sets `$zone_id`.

**Expected result.** These are the checks the validated read-back asserted:

- `Status` is `ISSUED` and `Type` is `AMAZON_ISSUED`;
- `Domain` is `<apex>`, and `SANs` are exactly `<apex>` and `*.<apex>`;
- both names show `DNS` and `SUCCESS` and share one validation record;
- `Export` is `DISABLED`;
- the six mandatory tags, with `Component` set to `dns`;
- the zone holds `NS`, `SOA` and exactly one `CNAME`, and that `CNAME` is the validation record,
  with the same name and value and TTL 300.

Observed on 2026-09-23 but not asserted: key `RSA-2048`, `InUseBy` 0 and `Renewal`
`INELIGIBLE`. The last two describe a certificate nothing uses yet, so they are not pass
criteria.

**PASS when.**

- [ ] Every asserted check above holds.

**STOP if.**

- Any asserted check fails.

**If it fails.** This runbook has no corrective procedure; replacing or reissuing the certificate
is listed under [Not yet exercised](#not-yet-exercised). Work stays stopped until a reviewed
decision is taken under explicit approval ([When to stop](README.md#when-to-stop)).

**Evidence to keep.** The result of each asserted check and the observed values, never the ARN.

**Next step.** If [Plan and apply the certificate](#plan-and-apply-the-certificate) sent you here,
return to its step 5 for the rest of that step, the convergence plan included, and then its PASS
checklist. Otherwise the normal path ends here. Nothing detects an approaching expiry; `NotAfter`
in step 2 is the date that matters (see the Engineering notes).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-23) |
| Published form | not executed as written (the validated read-back made the same calls with full JSON output into a private checker and took the ARN from `terraform output`; the published form holds the ARN in a variable and adds `--query` projections) |
| Evidence basis | [Status](../../terraform/foundation/README.md#status), certificate paragraph; retained private evidence of the read-back on 2026-09-23, 12 of 12 checks passed, by a checker qualified offline against eight failing cases |
| Authority | None (read-only) |
| Cost | None |

**Known limitations.**

- At the 2026-09-23 read-back nothing used the certificate, and ACM reported it as not eligible
  for managed renewal. ACM renews a DNS-validated certificate automatically only if an AWS
  service is using it when ACM checks before expiry
  ([Public DNS](../../terraform/foundation/README.md#public-dns)). No renewal or reissue procedure
  exists, and nothing detects an approaching expiry; `NotAfter` in step 2 is the date that
  matters.
- The registration of `<apex>` expires on its own schedule, and nothing detects that either
  ([Before you start](#before-you-start)).
- No certificate in `PENDING_VALIDATION` was found at issuance, but that was derived, not
  scanned, and only from a default certificate list in `us-east-1`, which returns only RSA-1024
  and RSA-2048 certificates (see [Not yet exercised](#not-yet-exercised)).

### Registrar lock check

**Validation:** UNEXERCISED (never) · **Published command form:** not executed as written

**What this does.** It would tell you, before the change, whether the registry would refuse it. No
reviewed procedure exists, so this page publishes no steps. Design-review reasoning, not
measurement: a transfer lock does not block a name-server change, and an update lock would.

**Before you start.**

- [ ] A source for the lock status. The one this page names is the registry's RDAP record, which
  lists it in `status`. Its query, and how to find `<rdap-base>` from IANA's RDAP bootstrap file,
  are in step 2 of [Verify delegation](#verify-delegation), where the read is optional. It needs
  `curl` ([Before you start](#before-you-start)).

**Safety and authority.** Read-only.

**Steps.** None published. `dig` cannot read registry lock status. The registry's RDAP record
lists it, in `status`, through the query in step 2 of [Verify delegation](#verify-delegation).
This page does not list which `status` values are update locks.

**Expected result.** None is published; the check has never run. For reference only: the one
RDAP read of the validated deployment, taken after the change, showed only a transfer-prohibited
status (see the Engineering notes).

**PASS when.**

- [ ] The registrar's lock status is known and shows no update lock, which
  [Change the name servers at the registrar](#change-the-name-servers-at-the-registrar) requires
  before the change.

**STOP if.**

- The status shows an update lock, which by the design-review reasoning above would block the
  change. Lifting a lock is a change to a lock setting, which
  [Change the name servers at the registrar](#change-the-name-servers-at-the-registrar) excludes,
  and this runbook has no procedure for it.
- The lock status is not known, or you cannot tell whether it includes an update lock.

**If it fails.** No reviewed procedure exists. Do not make the registrar change until the lock
status is known. An update lock has no published route: work stays stopped until a reviewed
decision is taken under explicit approval ([When to stop](README.md#when-to-stop)).

**Evidence to keep.** None is specified for this never-exercised check. Raw RDAP output names the
domain, so any copy you keep stays in the private run directory, with only its sha256 in the
cutover campaign's set ([Conventions](#conventions)).

**Next step.** [Change the name servers at the registrar](#change-the-name-servers-at-the-registrar).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | UNEXERCISED (never) |
| Published form | not executed as written (no check ran before the change; the one registry read, taken after it, is described below) |
| Evidence basis | Retained private RDAP capture from 2026-09-23, taken after the change |
| Authority | None (read-only) |
| Cost | None |

**Known limitations.** No lock check ran before the validated change, and no reviewed procedure
exists. `dig` cannot read registry lock status; the registry's RDAP record lists it, through
the query in [Verify delegation](#verify-delegation). The one RDAP read, taken after the change
on 2026-09-23, showed only a transfer-prohibited status. Design-review reasoning, not
measurement: a transfer lock does not block a name-server change, an update lock would, and a
refused change leaves the parent's referral unchanged, which
[Verify delegation](#verify-delegation) would show.

### CAA check

**Validation:** UNEXERCISED (never) · **Published command form:** not executed as written

**What this does.** It would confirm that no CAA record at `<apex>` or at its parent stops Amazon's
certificate authority from issuing the certificate. A CAA record names the certificate authorities
allowed to issue for a domain. No reviewed procedure exists, so this page publishes no steps.

**Before you start.**

- [ ] [Verify delegation](#verify-delegation) has passed, so that Route 53, not the previous
  provider, answers for `<apex>` when you check. Records the previous provider served stop
  resolving once Route 53 answers
  ([Change the name servers at the registrar](#change-the-name-servers-at-the-registrar)).

**Safety and authority.** Read-only.

**Steps.** None published. A reproducer whose apex or parent publishes CAA records has to confirm
that they authorize Amazon's certificate authority before
[Plan and apply the certificate](#plan-and-apply-the-certificate); this repository has no reviewed
procedure for that.

**PASS when.**

- [ ] You have confirmed that `<apex>` and its parent publish no CAA record, or that the ones they
  publish authorize Amazon's certificate authority.

**STOP if.**

- That cannot be confirmed. Do not start
  [Plan and apply the certificate](#plan-and-apply-the-certificate). No reviewed procedure or
  command exists for this check.

**Next step.** [Plan and apply the certificate](#plan-and-apply-the-certificate).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | UNEXERCISED (never) |
| Published form | not executed as written (no check exists; a design-review lookup is described below) |
| Evidence basis | A private design-review note from 2026-09-21; no command output was retained |
| Authority | None (read-only) |
| Cost | None |

**Known limitations.** No CAA check ran as a step of the validated build. A read-only lookup
during the design review on 2026-09-21 found no CAA record at the apex or at the parent. Its
output was not retained, and the lookup was not repeated before the certificate apply. A
reproducer whose apex or parent publishes CAA records has to confirm that they authorize
Amazon's certificate authority before
[Plan and apply the certificate](#plan-and-apply-the-certificate); this repository has no
reviewed procedure for that.

### Roll back the delegation

**Validation:** DESIGNED-NOT-EXECUTED (never) · **Published command form:** not executed as written

**What this does.** It returns the delegation to the previous provider if the cutover fails. The
Route 53 zone is kept.

**Before you start.**

- [ ] One of these triggers, and only these:
  - [Verify delegation](#verify-delegation) finds MIXED or WRONG at a parent server;
  - a Route 53 server stops answering authoritatively;
  - 1.1.1.1, 8.8.8.8 or 9.9.9.9 still fails to return the Route 53 set once the parent's NS TTL
    has passed since the change, as step 4 of [Verify delegation](#verify-delegation) checks.

  OLD answers during propagation, and transient `SERVFAIL` from resolvers still holding the old
  delegation within that time, are not triggers.
- [ ] The `<previous-ns>` set and the private export of the previous zone.
- [ ] Explicit owner approval of the rollback.

**Safety and authority.** Mutating, owner-authorized. No AWS cost; the zone is kept and keeps its
monthly charge.

**Steps.**

1. At the registrar, restore the `<previous-ns>` set, changing nothing else.

   > **Warning:** This procedure has never been executed. Steps 1 and 2 change live DNS; the
   > owner's explicit approval of the rollback covers them.

2. If the previous provider no longer holds the zone's records, re-create them there from the
   private export.
3. Keep the Route 53 zone. Retiring it is a separate step
   ([Retire the hosted zone](#retire-the-hosted-zone)).

   > **Warning:** Do not retire the zone as part of the rollback. Design-review reasoning, not
   > measurement: a resolver holding the Route 53 NS set keeps querying Route 53 after a rollback
   > until its entry expires. The zone is kept until the retirement wait in
   > [Public DNS](../../terraform/foundation/README.md#public-dns) has passed: the longer of the
   > parent's NS TTL, noted in the [Pre-cutover checks](#pre-cutover-checks), and the zone's NS
   > TTL of 172800 s.

4. Repeat step 2 of [Pre-cutover checks](#pre-cutover-checks), and step 3 against each
   `<previous-ns>` in place of `<route53-ns>`.

**Expected result.** Every parent server returns the `<previous-ns>` set, and each previous name
server answers `SOA` with the `aa` flag.

**PASS when.**

- [ ] Every parent server returns the `<previous-ns>` set.
- [ ] Each previous name server answers `SOA` with the `aa` flag.

**STOP if.** None are published for the rollback itself; it has never run.

**If it fails.** No further procedure exists. Work stays stopped until a reviewed decision is taken
under explicit approval ([When to stop](README.md#when-to-stop)).

**Evidence to keep.** None is specified for this never-executed procedure. Registrar screenshots
and exports carry the domain and stay private.

**Next step.** [Retire the hosted zone](#retire-the-hosted-zone), only if the zone is to be
retired, and only after the retirement wait: the longer of the parent's NS TTL, noted in the
[Pre-cutover checks](#pre-cutover-checks), and the zone's NS TTL of 172800 s
([Public DNS](../../terraform/foundation/README.md#public-dns)).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | DESIGNED-NOT-EXECUTED (never) |
| Published form | not executed as written (a registrar-neutral form of the rollback reviewed before the cutover) |
| Evidence basis | None. The design review is private, and no rollback trigger occurred during the validated cutover |
| Authority | Explicit owner approval of the rollback |
| Cost | None in AWS. The zone is kept and keeps its monthly charge |

**Known limitations.**

- Never executed. The export and the previous name-server set of the validated deployment exist
  only in private evidence; a reproducer needs their own.
- The done criterion covers the parent servers and the previous name servers, not resolvers. In
  the validated run 1.1.1.1 held the Route 53 NS set with 172800 s remaining. Design-review
  reasoning, not measurement: a resolver holding that set keeps querying Route 53 after a
  rollback until its entry expires. The zone is kept until the retirement wait in
  [Public DNS](../../terraform/foundation/README.md#public-dns) has passed.

### Retire the hosted zone

**Validation:** DESIGNED-NOT-EXECUTED (never) for the order; UNEXERCISED (never) for the destroy step · **Published command form:** not executed as written

**What this does.** It decommissions the zone without leaving a dangling delegation. It runs at
project end only. The order is designed and has never run; the destroy step itself is not
designed, and no command sheet exists.

**Before you start.**

- [ ] Explicit owner approval, at project end only.
- [ ] The registrar already points elsewhere, a registrar change the owner approved.
- [ ] The retirement wait has passed since then: the longer of the parent's NS TTL, noted in the
  [Pre-cutover checks](#pre-cutover-checks), and the zone's NS TTL of 172800 s
  ([Public DNS](../../terraform/foundation/README.md#public-dns)).
- [ ] The preconditions of [Pre-cutover checks](#pre-cutover-checks) and
  [Read back the hosted zone](#read-back-the-hosted-zone), whose steps the checks below reuse.

**Safety and authority.** Destructive, owner-authorized. The zone bills until it is deleted.

> **Warning:** The order is fixed: the registrar first, then the wait, the certificate before the
> zone, and `prevent_destroy` lifted in a reviewed change. It is in
> [Public DNS](../../terraform/foundation/README.md#public-dns) and is not repeated here. The
> certificate's retirement, which comes first, has no mechanism (see
> [Not yet exercised](#not-yet-exercised)).

**Steps.** These are the reviewed checks before any destroy:

1. Step 2 of [Pre-cutover checks](#pre-cutover-checks): no parent server lists a Route 53 name
   server.
2. Step 4 of [Pre-cutover checks](#pre-cutover-checks) at 1.1.1.1, 8.8.8.8 and 9.9.9.9: none
   returns the Route 53 set.
3. Steps 2 and 4 of [Read back the hosted zone](#read-back-the-hosted-zone): no record remains
   other than `NS`, `SOA` and the certificate's validation record.

   > **Warning:** Route 53 deletes a zone only when its `NS` and `SOA` records alone remain
   > ([Public DNS](../../terraform/foundation/README.md#public-dns)), so the validation record has
   > to go first. Reviewed design, not measurement: the validation record depends on both the
   > certificate and the zone, so Terraform removes it before either.

No destroy step is published: it is not designed (see the Engineering notes).

**Expected result.** No parent server lists a Route 53 name server; none of 1.1.1.1, 8.8.8.8 and
9.9.9.9 returns the Route 53 set; and the zone holds only `NS`, `SOA` and the certificate's
validation record.

**PASS when.**

- [ ] All three checks hold. Passing them does not supply a destroy step; none is designed.

**STOP if.**

- Any of the three reviewed checks does not hold.

**If it fails.** No procedure exists.

**Evidence to keep.** None is specified; the procedure has never run.

**Next step.** The orphan and cost checks that close a decommission follow
[cost-and-residue.md](cost-and-residue.md).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | DESIGNED-NOT-EXECUTED (never) for the order; its destroy step is UNEXERCISED (never) |
| Published form | not executed as written (the reviewed order is in [Public DNS](../../terraform/foundation/README.md#public-dns); no command sheet exists) |
| Evidence basis | None; never executed |
| Authority | Explicit owner approval, at project end only |
| Cost | The zone bills until it is deleted |

**Known limitations.**

- The destroy step is not designed. A destroy of the whole root is blocked by the evidence
  bucket's `prevent_destroy`, so the zone needs a targeted destroy or a configuration change that
  removes it, and neither is written or reviewed.
- The certificate's retirement, which comes first, has no mechanism either (see
  [Not yet exercised](#not-yet-exercised)).
- The orphan and cost checks that close a decommission follow
  [cost-and-residue.md](cost-and-residue.md).

## Not yet exercised

- **[Build the zone on its own](#build-the-zone-on-its-own)**, in its `-target` form:
  DESIGNED-NOT-EXECUTED. The validated build used a zone-only commit instead.
- **[Roll back the delegation](#roll-back-the-delegation)**: DESIGNED-NOT-EXECUTED.
- **[Retire the hosted zone](#retire-the-hosted-zone)**: DESIGNED-NOT-EXECUTED for the order;
  the destroy step is UNEXERCISED.
- **[Registrar lock check](#registrar-lock-check)**: UNEXERCISED.
- **[CAA check](#caa-check)**: UNEXERCISED.
- **Record migration from the previous provider**: UNEXERCISED. The validated deployment
  migrated no record. The names the previous provider served were queried only while the parent
  still returned the previous set, so what they return now is unmeasured.
- **Retire the certificate**: UNEXERCISED. Only an ordering rule exists
  ([Public DNS](../../terraform/foundation/README.md#public-dns)): retire it before the zone, once
  nothing uses it. No mechanism for removing it while keeping the zone is written.
  Design-review reasoning, not measurement: destroying the zone first would delete the
  validation record and leave a certificate that cannot renew.
- **Managed renewal**: UNEXERCISED. The certificate is not eligible while nothing uses it; the
  read-only status check is step 2 of [Read back the certificate](#read-back-the-certificate).
- **Replace or reissue the certificate**: UNEXERCISED. A replacement has a new ARN, and
  `certificate.tf` creates the new certificate before deleting the old one. Design-review
  reasoning, not measurement: while a load balancer still references the old ARN, the provider
  retries deleting the old certificate for 20 minutes, then fails and leaves it deposed in state.
- **A DNS validation that does not complete**: UNEXERCISED; it has not occurred. Only stop
  conditions are published: never apply the certificate before
  [Verify delegation](#verify-delegation) passes, and treat a stalled validation step as a failed
  apply, which is stopped and inspected and not applied again without a separate reviewed
  decision. Design-review reasoning, not measurement: the failed validation step is not saved to
  state, a re-apply after delegation within ACM's 72-hour pending window completes it, and after
  that window the certificate has to be replaced.
- **Scan for certificates left in `PENDING_VALIDATION`**, an ADR-0018 orphan-scan class:
  UNEXERCISED. The orphan census in [cost-and-residue.md](cost-and-residue.md) has no ACM class.
  At issuance, absence was derived from the one certificate's `ISSUED` status and an empty
  default certificate list in `us-east-1` before the apply. That default list returns only
  RSA-1024 and RSA-2048 certificates, so certificates with other key types were not counted.
- **DS or DNSSEC at the parent before the cutover**: UNEXERCISED. The
  [Pre-cutover checks](#pre-cutover-checks) stop on a DS record; handling one at the registrar
  has never been done here.
- **The full certificate-stage plan on a build from nothing**: UNEXERCISED. After the zone-first
  step, that plan also creates the rest of the foundation; it has never run, and no reviewed
  shape exists for it.
- **Recover the zone after a deletion outside Terraform**: UNEXERCISED. `prevent_destroy` guards
  only against Terraform. A recreated zone gets new name servers, so the registrar has to be
  re-pointed, and the certificate's validation record has to exist in the new zone before renewal
  can use it. Until the registrar is re-pointed, the parent delegates to name servers that no
  longer hold the zone, and another account's zone could answer for the domain, so re-delegation
  is urgent. The recovery posture is rebuild-first
  ([ADR-0011](../decisions/0011-define-the-backup-and-recovery-model.md) and the DNS hosted zone
  row of the [architecture baseline](../architecture-baseline.md)); no reviewed sequence exists.
- **Re-adopt the zone and certificate after state loss**: UNEXERCISED. No import procedure
  exists; state recovery is covered, as unexercised, in
  [terraform-operations.md](terraform-operations.md).
- **Periodic re-verification**: UNEXERCISED. No cadence exists for re-running
  [Verify delegation](#verify-delegation) and step 2 of
  [Read back the certificate](#read-back-the-certificate).
- **Renew the domain registration**: UNEXERCISED. ADR-0018 defers the registrar and renewal
  procedure. Auto-renewal and multi-factor sign-in at the registrar are attested, not
  independently verified. A lapsed registration breaks delegation, public DNS and certificate
  validation, and nothing in the platform detects it.

## Reproducibility gaps

What a new engineer cannot reproduce from the public repositories today, what public contract does
exist, and whether a new public procedure or tool is needed later.

| What cannot be reproduced | Public contract that exists | Later need |
|---|---|---|
| The registrar change as executed. It was made by hand in the registrar's control panel, and no step list for the interface used was retained. | The registrar-neutral steps in [Change the name servers at the registrar](#change-the-name-servers-at-the-registrar); the outcome is proven by [Verify delegation](#verify-delegation). | No tool. Registrar interfaces differ, and the public-DNS outcome check already exists. |
| The private checkers that evaluated the zone read-back, the pre-cutover checks, the verification rounds, the certificate plan shape and the certificate read-back, and their offline qualification against failing cases. | The published commands with their expected results, PASS and STOP lists, and the plan review in [terraform-operations.md](terraform-operations.md#review-the-saved-plan). | Not needed to operate. Reproducing the offline qualification would need a published checker. |
| How the registry's RDAP base URL was found. It was not recorded, so the bootstrap lookup is derived. | IANA's RDAP bootstrap file for DNS, in step 2 of [Verify delegation](#verify-delegation). | No. |
| A registry lock check before the change. None ran, and no reviewed procedure exists. | The RDAP read in [Verify delegation](#verify-delegation), which lists the registry status. | Yes: a reviewed pre-change [Registrar lock check](#registrar-lock-check). |
| A CAA check. The design-review lookup's output was not retained, and no reviewed procedure exists. | The requirement stated in [CAA check](#caa-check). | Yes, for a reproducer whose apex or parent publishes CAA records. |
| The validated rollback inputs. The previous zone's export and the previous name-server set exist only in private evidence, and the rollback's design review is private. The validated export was taken at the registrar; no export method and no completeness test for an export are published. | [Roll back the delegation](#roll-back-the-delegation), registrar-neutral and never executed. | No tool: each reproducer takes their own export and name-server set before the change. The rollback itself has never run. |
| The zone-first build in its published `-target` form. The validated build applied a zone-only commit, `69c5770`, instead. | [Build the zone on its own](#build-the-zone-on-its-own) and the zone-first order in [Public DNS](../../terraform/foundation/README.md#public-dns). | No new tool; the targeted form has never run. |
| The certificate-stage plan on a build from nothing, which also creates the rest of the foundation. | The three-address shape in [Plan and apply the certificate](#plan-and-apply-the-certificate), which assumes the rest of the foundation is already applied. | Yes: a reviewed plan shape for the combined plan. |
| An apex under a multi-label public suffix, where the delegating zone sits below the top-level domain. | The placeholder definitions under [Before you start](#before-you-start). | Only for a reproducer with such an apex. |
| Handling a DS record at the parent, and migrating records from the previous provider. | The DS STOP in [Pre-cutover checks](#pre-cutover-checks) and the STOP in [Change the name servers at the registrar](#change-the-name-servers-at-the-registrar) on any record that must keep resolving. | Yes, for a reproducer whose parent holds a DS record or who keeps records from the previous provider. |
| The certificate after issuance: managed renewal, replacement or reissue, retirement, a DNS validation that does not complete, and the scan for certificates left in `PENDING_VALIDATION`. | The ordering rule in [Public DNS](../../terraform/foundation/README.md#public-dns), the stop conditions in [Plan and apply the certificate](#plan-and-apply-the-certificate), and the read-only status check in step 2 of [Read back the certificate](#read-back-the-certificate). | Yes: reviewed procedures, and an ACM class in the orphan census ([cost-and-residue.md](cost-and-residue.md)). |
| The destroy step of the zone's retirement. It is not designed, and no command sheet exists. | The order in [Public DNS](../../terraform/foundation/README.md#public-dns) and the reviewed checks in [Retire the hosted zone](#retire-the-hosted-zone). | Yes: a reviewed targeted destroy or configuration change. |
| Recovery of the zone after a deletion outside Terraform, and re-adoption of the zone and certificate after state loss. | The rebuild-first posture in [ADR-0011](../decisions/0011-define-the-backup-and-recovery-model.md) and the DNS hosted zone row of the [architecture baseline](../architecture-baseline.md). | Yes: a reviewed recovery sequence and an import procedure. |
| Domain registration and renewal. Auto-renewal and multi-factor sign-in at the registrar are attested, not independently verified. | ADR-0018, which defers the registrar and renewal procedure. | Yes, as deferred by ADR-0018. |
| A periodic re-verification of delegation and of the certificate. | [Verify delegation](#verify-delegation) and step 2 of [Read back the certificate](#read-back-the-certificate), run by hand. | Yes: a cadence. |

## Background prerequisites

The prerequisites needed before a first action are under [Before you start](#before-you-start).
These are discovered or read while the procedures run:

- The parent zone's authoritative servers and the registry's RDAP base URL, discovered at run
  time.
- The four assigned name servers, the zone ID and the certificate ARN, read at run time and
  never recorded in shared material.
