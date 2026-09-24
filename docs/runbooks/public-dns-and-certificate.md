# Public DNS and Certificate Runbook

## Scope

This runbook operates the public hosted zone, its delegation from the registrar, and the ACM
certificate validated through that zone. `terraform/foundation` declares the zone and the
certificate, in [`dns.tf`](../../terraform/foundation/dns.tf) and
[`certificate.tf`](../../terraform/foundation/certificate.tf). The delegation is a registrar-side
setting, outside Terraform and outside AWS.
[ADR-0018](../decisions/0018-define-the-public-entry-implementation-dns-and-certificate-model.md)
is the decision, and
[ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md) sets the
persistent-foundation obligations and the cost rules.

It owns the zone-first build, the zone read-back, the pre-cutover checks, the registrar
name-server change, delegation verification, and the certificate plan, apply and read-back,
each with its validation status. Validation labels and the published-form rule are defined in
the [runbook index](README.md).

It links rather than repeats:

- what the root creates, its inputs, the zone-first, rebuild and retirement order, the cost and
  the write-access boundary: [Public DNS](../../terraform/foundation/README.md#public-dns);
  measured outcomes: [Status](../../terraform/foundation/README.md#status);
- login, caller verification and session headroom: [operator-access.md](operator-access.md);
- backend initialization, the reviewed saved-plan workflow, apply and the convergence plan:
  [terraform-operations.md](terraform-operations.md);
- the Route 53 pricing re-check and the orphan census: [cost-and-residue.md](cost-and-residue.md);
- evidence capture, redaction and sealing: [evidence-handling.md](evidence-handling.md).

Environment DNS records, the record controller and binding the certificate to a load balancer
belong to runtime windows, which this suite does not cover; see
[runtime validation](../validation/runtime-validation.md).

Conventions:

- Terraform commands run in `terraform/foundation`, prefixed with `AWS_PROFILE=<profile>` as in
  [terraform-operations.md](terraform-operations.md), where `<profile>` is the administrative
  profile. `<plan-file>` and `<private-dir>` are defined there: a saved plan lives outside every
  Git working tree.
- `<apex>` is the registered domain supplied as `public_domain`. `<parent>` is the zone that
  delegates `<apex>`, and `<parent-server>` each of its authoritative servers. In the validated
  deployment `<parent>` was the top-level domain; an apex under a multi-label public suffix,
  where the delegating zone sits below the top-level domain, has never been exercised. `<tld>`
  is the top-level domain, used only to find the registry's RDAP service.
- `<route53-ns>` is each of the four name servers Route 53 assigned, `<previous-ns>` each name
  server of the provider that served the domain before the cutover, and `<resolver>` a public
  resolver. `<rdap-base>` is the registry's RDAP base URL without its trailing `/`.
- The six mandatory tags: the keys are set by
  [ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md), under Tagging and
  attribution, and the values by `default_tags` in
  [`providers.tf`](../../terraform/foundation/providers.tf), with `Component` overridden to
  `dns` in `dns.tf` and `certificate.tf`. A plan shows the default tags under `tags_all`, not
  `tags`, so the plan checks below read `tags_all`.
- No command prints an ARN or an account number. The zone ID and the certificate ARN are held
  in shell variables and never written down, and the domain and the name servers stay out of
  shared records.

## Procedures

### Build the zone on its own

| Field | Value |
|---|---|
| Validation status | DESIGNED-NOT-EXECUTED (never) |
| Published form | not executed as written (derived from the zone-first order in [Public DNS](../../terraform/foundation/README.md#public-dns), whose `terraform apply -target` sentence gives the order only; this saved-plan form is the procedure. The plan command is the plan form of [terraform-operations.md](terraform-operations.md) with `-target` added. The one validated zone build, executed 2026-09-23, applied a reviewed saved plan made from commit `69c5770`, whose configuration declared the zone and no certificate, so it needed no `-target`. It was applied from that commit before the merge, and the same foundation tree was confirmed on merged main afterwards) |
| Evidence basis | [Status](../../terraform/foundation/README.md#status), zone paragraph; commit `69c5770`; retained private evidence of the 2026-09-22 saved plan and the 2026-09-23 apply and read-back |
| Authority | Explicit owner approval of the zone apply |
| Cost | 0.50 USD a month from creation, not prorated, plus query charges ([Public DNS](../../terraform/foundation/README.md#public-dns)) |

**Purpose.** Create the hosted zone alone, so the certificate is not requested before the
registrar delegates to the zone. This applies to a first build, to a rebuild from nothing, and
to any rebuild that creates a new zone, because a new zone gets new name servers.

**Preconditions.**

- An administrative session, with the caller verified and enough session headroom
  ([operator-access.md](operator-access.md)).
- `terraform/foundation` initialized against its backend
  ([terraform-operations.md](terraform-operations.md)). Every plan of this root needs all four
  [inputs](../../terraform/foundation/README.md#input), DNS-only work included.
- Route 53 pricing re-checked immediately before the apply
  ([cost-and-residue.md](cost-and-residue.md)).
- No hosted zone for `<apex>` exists: step 1 of
  [Read back the hosted zone](#read-back-the-hosted-zone) returns `0`.
- Explicit approval of this apply.

**Procedure.**

1. Plan the zone alone into a saved plan. Terraform warns that resource targeting is in effect;
   that is expected for this step only. `-lock=false` is used only under the conditions in
   [terraform-operations.md](terraform-operations.md).

   ```
   AWS_PROFILE=<profile> terraform plan -lock=false -input=false -no-color -detailed-exitcode -target=aws_route53_zone.public -out=<plan-file>
   echo $?
   ```

   Exit 2 means the plan has changes, as expected here; exit 0 or 1 is a STOP.

2. Review the saved plan with the workflow in [terraform-operations.md](terraform-operations.md)
   against this shape:
   - exactly one resource to add, `aws_route53_zone.public`, and 0 to change, destroy or replace;
   - the zone is public (no VPC association), named `<apex>`, with `force_destroy` false;
   - the six mandatory tags in `tags_all`, with `Component` set to `dns`;
   - no `aws_acm_*` and no `aws_route53_record` address;
   - output changes: `public_zone_name_servers` created. What this targeted form shows for
     `public_certificate_arn` is unmeasured (see Known limitations).
3. Bind the saved plan to its hash and to state, then apply exactly that plan, without
   re-planning, with the same workflow.
4. Run [Read back the hosted zone](#read-back-the-hosted-zone).

**Expected result.** One public hosted zone with four assigned name servers, and public DNS
still answered by the previous provider. After the validated apply, the live delegation had no
name server in common with the four assigned.

**Validation.** [Read back the hosted zone](#read-back-the-hosted-zone).

**Evidence to retain.** The saved plan's sha256, the plan-shape result, the apply result line
and the read-back results, captured as in [evidence-handling.md](evidence-handling.md). Raw
plan and apply output of this root prints private values, including the evidence bucket name,
the zone ID and the name servers, so it stays private.

**STOP conditions.**

- The plan differs from the shape above in any way.
- A hosted zone for `<apex>` already exists.
- Any `aws_acm_*` address would be created. Design-review reasoning, not measurement: a
  certificate requested before delegation waits out Terraform's validation step and is left in
  `PENDING_VALIDATION`, a class ADR-0018 names for the orphan scan.

**Failure handling.** A failed or interrupted apply follows
[terraform-operations.md](terraform-operations.md).

**Teardown / decommission.** The zone is persistent; see
[Retire the hosted zone](#retire-the-hosted-zone), which has never run.

**Known limitations.**

- The `-target` form has never run. Until
  [Plan and apply the certificate](#plan-and-apply-the-certificate) completes, a plain plan of
  this root is expected to show the certificate's three addresses as pending, and on a build
  from nothing the rest of the foundation as well, so the no-drift convergence check applies
  only after the certificate apply.
- The validated zone plan showed `public_zone_name_servers` created. It was made from a
  configuration without `certificate.tf`, so how a targeted plan on the current configuration
  shows `public_certificate_arn` has never been observed.

**Next gate.** [Pre-cutover checks](#pre-cutover-checks).

### Read back the hosted zone

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-23) |
| Published form | not executed as written (the validated read-backs made the same read-only calls with full JSON output into a private checker; the published form adds `--query` projections) |
| Evidence basis | [Status](../../terraform/foundation/README.md#status), zone and certificate paragraphs; retained private evidence of two read-backs on 2026-09-23, 8 of 8 checks after the zone apply and the zone checks of the certificate read-back, each by a checker qualified offline before use |
| Authority | None (read-only) |
| Cost | None |

**Purpose.** Confirm that the zone is the one this root declares and holds nothing unexpected,
and obtain the four assigned name servers.

**Preconditions.** A session with the identity and account checks passed
([operator-access.md](operator-access.md)). Nothing else checks the account for these AWS CLI
calls, and a `0` at step 1 says nothing about the intended account without that check.

**Procedure.**

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

5. When the name servers are needed, for the pre-cutover checks or the registrar, read them
   from the zone's delegation set:

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

The validated read-back also checked the foundation state and a no-drift plan; those checks
belong to [terraform-operations.md](terraform-operations.md).

**STOP conditions.** More than one zone for `<apex>`, a private zone, a name-server count other
than four, a missing or different tag, or any record type or count other than those above.

**Evidence to retain.** The result of each expected value, never the zone ID or the name
servers.

### Pre-cutover checks

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-23, verified on public DNS) |
| Published form | executed as written |
| Evidence basis | Retained private evidence of the preflight run on 2026-09-23 immediately before the registrar change, evaluated by a private checker qualified offline against five failing cases: a missing `aa` flag, `REFUSED`, a wrong NS set, a parent already delegating to Route 53, and a DS record present |
| Authority | None (read-only) |
| Cost | None beyond negligible Route 53 query charges |

**Purpose.** Before the registrar change, establish what the parent delegates to now, confirm
that the parent holds no DS record, and confirm that all four Route 53 servers already answer
for the zone. [Verify delegation](#verify-delegation) and
[Roll back the delegation](#roll-back-the-delegation) reuse these commands.

**Preconditions.** [Read back the hosted zone](#read-back-the-hosted-zone) passed, and its step
5 supplied the four `<route53-ns>` values.

**Procedure.**

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

**STOP conditions.**

- A DS record exists at the parent. Validating resolvers would answer `SERVFAIL` for the domain
  once an unsigned Route 53 zone takes over, so DNSSEC has to be dealt with at the registrar
  first. That path has never been exercised here.
- A Route 53 server answers without `aa`, answers `REFUSED`, or returns a different NS set.
- The parent servers disagree with each other, or already refer to Route 53.

**Evidence to retain.** The raw `dig` output with its start and end times, kept privately,
because it names the domain and every name server.

**Next gate.** [Registrar lock check](#registrar-lock-check) and [CAA check](#caa-check), both
never exercised, then [Change the name servers at the registrar](#change-the-name-servers-at-the-registrar).

### Registrar lock check

| Field | Value |
|---|---|
| Validation status | UNEXERCISED (never) |
| Published form | not executed as written (no check ran before the change; the one registry read, taken after it, is described below) |
| Evidence basis | Retained private RDAP capture from 2026-09-23, taken after the change |
| Authority | None (read-only) |
| Cost | None |

**Purpose.** Know before the change whether the registry would refuse it.

**Known limitations.** No lock check ran before the validated change, and no reviewed procedure
exists. `dig` cannot read registry lock status; the registry's RDAP record lists it, through
the query in [Verify delegation](#verify-delegation). The one RDAP read, taken after the change
on 2026-09-23, showed only a transfer-prohibited status. Design-review reasoning, not
measurement: a transfer lock does not block a name-server change, an update lock would, and a
refused change leaves the parent's referral unchanged, which
[Verify delegation](#verify-delegation) would show.

### CAA check

| Field | Value |
|---|---|
| Validation status | UNEXERCISED (never) |
| Published form | not executed as written (no check exists; a design-review lookup is described below) |
| Evidence basis | A private design-review note from 2026-09-21; no command output was retained |
| Authority | None (read-only) |
| Cost | None |

**Purpose.** Confirm that no CAA record at `<apex>` or at its parent stops Amazon's
certificate authority from issuing the certificate.

**Known limitations.** No CAA check ran as a step of the validated build. A read-only lookup
during the design review on 2026-09-21 found no CAA record at the apex or at the parent. Its
output was not retained, and the lookup was not repeated before the certificate apply. A
reproducer whose apex or parent publishes CAA records has to confirm that they authorize
Amazon's certificate authority before
[Plan and apply the certificate](#plan-and-apply-the-certificate); this repository has no
reviewed procedure for that.

### Change the name servers at the registrar

| Field | Value |
|---|---|
| Validation status | EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-09-23) |
| Published form | not executed as written (a registrar-neutral description; registrar interfaces differ, and no step list for the interface used was retained) |
| Evidence basis | The change was made by hand in the registrar's control panel and is attested by the person who made it; that is not AWS evidence. The registry's RDAP record, captured privately on 2026-09-23, shows a change at that time. The outcome is proven separately, by [Verify delegation](#verify-delegation) |
| Authority | Explicit owner approval of the registrar change, carried out by whoever holds registrar access |
| Cost | None in AWS. Registrar charges sit outside the AWS budget ([ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md)) |

**Purpose.** Delegate `<apex>` to the Route 53 zone.

**Preconditions.**

- [Pre-cutover checks](#pre-cutover-checks) passed.
- The zone the previous provider serves has been exported, and the export is kept privately
  with its sha256; the rollback depends on it. In the validated run the export was taken at
  the registrar on 2026-09-23 and retained privately. It is a registrar-side action, outside the
  AWS labels.
- A decision for every record in the export: migrate it into Route 53, or accept that it stops
  resolving once Route 53 answers. The validated deployment migrated none, and migration has
  never been exercised.
- The registrar's lock status is known ([Registrar lock check](#registrar-lock-check)).
- Explicit approval of the change.

**Inputs.** The four assigned name servers, from step 5 of
[Read back the hosted zone](#read-back-the-hosted-zone). The root's `public_zone_name_servers`
output carries the same values; reading that output was not part of the validated run.

**Procedure.**

1. At the registrar, replace the domain's complete name-server set with exactly the four
   assigned name servers.
2. Change nothing else: no DNSSEC setting, no record, no contact or lock setting.
3. Record the UTC time of the change.
4. Start [Verify delegation](#verify-delegation).

**Expected result.** The registry's RDAP record lists the new name servers before the parent
servers return them. Measured on 2026-09-23, from the RDAP `last changed` time: the one RDAP
read, about 12 minutes after it, already listed the four new name servers while the parent
servers still returned the previous set. The parent servers returned the previous set at four
checks up to about 23 minutes after the change, and the new set at the check 31 minutes after
it.

**STOP conditions.**

- The registrar refuses the change, or asks to change DNSSEC or anything besides the name
  servers.
- The values entered differ from the four assigned name servers.

**Failure handling.** If the registrar refuses the change, nothing in AWS has changed. Stop and
leave the delegation as it is.

**Recovery / rollback.** [Roll back the delegation](#roll-back-the-delegation), designed and
never executed.

**Evidence to retain.** The UTC time of the change, a statement that only the name servers
changed, and the sha256 of the privately kept export. Registrar screenshots and exports carry
the domain and stay private.

### Verify delegation

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-23, verified on public DNS) |
| Published form | not executed as written (the post-change checks ran the step 1 queries in this form, and the RDAP read in this form with the registry's base URL already known; how that base URL was found was not recorded, so the bootstrap lookup is derived. The DS queries of the pre-cutover checks were not repeated after the change and are not part of this procedure) |
| Evidence basis | [Status](../../terraform/foundation/README.md#status), zone paragraph; retained private evidence of the verification rounds on 2026-09-23, from the first check after the change to the final check immediately before the certificate apply, evaluated by a private checker qualified offline against six failing cases and three classification cases |
| Authority | None (read-only) |
| Cost | None beyond negligible Route 53 query charges |

**Purpose.** Prove on public DNS that the parent delegates `<apex>` to the Route 53 zone.

**Procedure.**

1. Run the NS and SOA queries of steps 1 to 4 of [Pre-cutover checks](#pre-cutover-checks)
   again, without the two DS queries: the `<parent>` NS query, the NS query at each
   `<parent-server>`, the SOA and NS queries at each `<route53-ns>`, and the NS query at 1.1.1.1
   and 8.8.8.8.
2. Optionally, read the registry's RDAP record. `<rdap-base>` is the base URL that IANA's RDAP
   bootstrap file for DNS, `https://data.iana.org/rdap/dns.json`, lists for `<tld>`, with its
   trailing `/` removed.

   ```
   curl -q -s --max-time 20 <rdap-base>/domain/<apex>
   ```

   Read `nameservers`, `status`, `secureDNS.delegationSigned` and the `last changed` event.

Classify each parent server's referral:

| Class | Referral | Action |
|---|---|---|
| OLD | the `<previous-ns>` set | Wait and repeat |
| NEW | exactly the four Route 53 name servers | Pass for that server |
| MIXED | some of each | STOP |
| WRONG | anything else, including an incomplete set | STOP |

**Expected result.** Pass when every parent server is NEW, every Route 53 server still answers
with `aa`, one SOA serial and the four-server NS set, and 1.1.1.1 and 8.8.8.8 return the Route
53 set. A resolver still returning the previous set means propagation is in progress. RDAP
lists the four name servers and `delegationSigned` false.

Measured on 2026-09-23: every parent server was NEW 31 minutes after the change, and 1.1.1.1
and 8.8.8.8 returned the Route 53 set when checked 55 minutes after it, with cached NS TTLs of
172800 s and 21600 s. The final check, immediately before the certificate apply, also passed.

**STOP conditions.**

- MIXED or WRONG at any parent server.
- A Route 53 server stops answering authoritatively, answers `SERVFAIL` or `REFUSED`, or returns
  another NS set.
- A resolver returns a set that is neither the previous set nor the Route 53 set.

**Failure handling.** Design-review reasoning, not measurement: transient `SERVFAIL` from a
resolver still holding the old delegation is expected until the parent's NS TTL has passed, and
is not a reason to roll back. None was observed in the validated run. A STOP condition that
persists is a trigger for [Roll back the delegation](#roll-back-the-delegation).

**Evidence to retain.** The raw `dig` and RDAP output, privately; the class of each server and
resolver, and the time of each round.

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

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-23) |
| Published form | not executed as written (the plan and apply commands are those of [terraform-operations.md](terraform-operations.md), and the validated run used them from a detached working tree at commit `ac87cb7`. It differed in three ways: its init added `-plugin-dir`, a private checker checked the plan shape instead of the checklist below, and before the apply it re-checked the plan's hash but not the state serial and lineage that step 4 binds) |
| Evidence basis | [Status](../../terraform/foundation/README.md#status), certificate paragraph; commit `ac87cb7`; retained private evidence of the 2026-09-23 plan, its sha256 binding, the delegation check immediately before the apply, the apply and the convergence plan |
| Authority | Explicit owner approval to apply exactly the reviewed saved plan |
| Cost | None. The certificate is non-exportable and carries no charge ([ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md)); the zone's charge is unchanged |

**Purpose.** Request the certificate for the apex and one wildcard beneath it, and complete its
DNS validation once the zone is delegated.

**Preconditions.**

- [Verify delegation](#verify-delegation) passes at step 3, immediately before the apply. The
  reviewed design also required it to pass before the plan; the validated run planned first
  (see Known limitations).
- The [CAA check](#caa-check) concern is settled for `<apex>`; it was never exercised as a step.
- The session outlasts Terraform's validation step, which can wait up to the AWS provider's
  default create timeout of 75 minutes. Check headroom as in
  [operator-access.md](operator-access.md), or log in again first. Headroom was not recorded for
  the validated certificate apply.
- Explicit approval of the apply.

**Procedure.**

1. From the reviewed commit, produce a saved plan of the whole root, without `-target`, and
   review it with the workflow in [terraform-operations.md](terraform-operations.md). Record its
   sha256 and the state serial and lineage it was made from, as that workflow's binding step
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
3. Immediately before the apply, run [Verify delegation](#verify-delegation) again. It must pass
   in full, as in the validated run: every parent server NEW, every Route 53 server
   authoritative, and 1.1.1.1 and 8.8.8.8 returning the Route 53 set.
4. Run the binding check in [terraform-operations.md](terraform-operations.md) (hash, serial and
   lineage), then apply exactly that plan, without re-planning.
5. Run [Read back the certificate](#read-back-the-certificate), then the convergence plan in
   [terraform-operations.md](terraform-operations.md), which must exit 0.

This is the order the validated run followed. Its plan was produced after the last check that
still showed the previous set, about five minutes earlier, and before the first check that
showed the new set, about two minutes after the plan finished. The delegation check ran between
plan and apply. Design-review reasoning, not measurement: the plan does not depend on
delegation; the apply's validation step does.

**Expected result.** 3 added, 0 changed, 0 destroyed. In the validated run the certificate was
issued during the apply, less than a minute after it started, and the convergence plan then
reported no changes.

**Validation.** [Read back the certificate](#read-back-the-certificate) and
[Read back the hosted zone](#read-back-the-hosted-zone).

**Evidence to retain.** The saved plan's sha256 and the binding check's results, the plan-shape result,
the delegation check's classes, the apply result line, the read-back results and the
convergence exit code, captured as in [evidence-handling.md](evidence-handling.md).

**STOP conditions.**

- Any difference from the plan shape, including any destroy or replacement.
- At step 3, any parent server not NEW, any Route 53 server not answering authoritatively, or
  1.1.1.1 or 8.8.8.8 not returning the Route 53 set.
- A sha256, serial or lineage mismatch at step 4.
- Too little session headroom for the validation wait.

**Failure handling.** A validation step that does not complete is a failed apply. Follow the
stop-and-inspect procedure for a failed or interrupted apply in
[terraform-operations.md](terraform-operations.md): no further apply, from this plan or a new
one. Design-review reasoning, not measurement: the apply ends with an error at the provider's
create timeout, and the certificate remains, probably in `PENDING_VALIDATION`, the provisioning
failure class ADR-0018 names for the orphan scan. Any re-apply is a separate reviewed decision;
no recovery procedure exists (see [Not yet exercised](#not-yet-exercised)).

**Known limitations.**

- On a build from nothing, this full plan also adds the rest of the foundation. That combined
  plan has never run, and the three-address shape above does not describe it.
- The reviewed design planned the certificate only after the post-change delegation checks had
  passed. The validated run produced its plan before the parent servers returned the new set,
  and gated only the apply.
- The validated apply re-checked the saved plan's hash, but not the state serial and lineage
  that step 4 now binds.

**Next gate.** Binding the certificate to the load balancer through the ingress annotation,
inside a runtime window. It is not implemented and is outside this suite
([runtime validation](../validation/runtime-validation.md)).

### Read back the certificate

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-23) |
| Published form | not executed as written (the validated read-back made the same calls with full JSON output into a private checker and took the ARN from `terraform output`; the published form holds the ARN in a variable and adds `--query` projections) |
| Evidence basis | [Status](../../terraform/foundation/README.md#status), certificate paragraph; retained private evidence of the read-back on 2026-09-23, 12 of 12 checks passed, by a checker qualified offline against eight failing cases |
| Authority | None (read-only) |
| Cost | None |

**Purpose.** Confirm the issued certificate matches what this root declares.

**Preconditions.**

- A session with the identity and account checks passed
  ([operator-access.md](operator-access.md)). `terraform output` reads only state and the AWS CLI
  calls are outside Terraform, so nothing else checks the account.
- `terraform/foundation` initialized against its backend
  ([terraform-operations.md](terraform-operations.md)).

**Procedure.**

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

**STOP conditions.** Any asserted check fails.

**Evidence to retain.** The result of each asserted check and the observed values, never the
ARN.

**Known limitations.**

- At the 2026-09-23 read-back nothing used the certificate, and ACM reported it as not eligible
  for managed renewal. ACM renews a DNS-validated certificate automatically only if an AWS
  service is using it when ACM checks before expiry
  ([Public DNS](../../terraform/foundation/README.md#public-dns)). No renewal or reissue procedure
  exists, and nothing detects an approaching expiry; `NotAfter` in step 2 is the date that
  matters.
- The registration of `<apex>` expires on its own schedule, and nothing detects that either
  ([Hidden prerequisites](#hidden-prerequisites)).
- No certificate in `PENDING_VALIDATION` was found at issuance, but that was derived, not
  scanned, and only from a default certificate list in `us-east-1`, which returns only RSA-1024
  and RSA-2048 certificates (see [Not yet exercised](#not-yet-exercised)).

### Roll back the delegation

| Field | Value |
|---|---|
| Validation status | DESIGNED-NOT-EXECUTED (never) |
| Published form | not executed as written (a registrar-neutral form of the rollback reviewed before the cutover) |
| Evidence basis | None. The design review is private, and no rollback trigger occurred during the validated cutover |
| Authority | Explicit owner approval of the rollback |
| Cost | None in AWS. The zone is kept and keeps its monthly charge |

**Purpose.** Return the delegation to the previous provider if the cutover fails.

**Preconditions.** One of these triggers, and only these:

- [Verify delegation](#verify-delegation) finds MIXED or WRONG at a parent server;
- a Route 53 server stops answering authoritatively;
- 1.1.1.1, 8.8.8.8 or 9.9.9.9 still fails to return the Route 53 set once the parent's NS TTL
  has passed since the change.

OLD answers during propagation, and transient `SERVFAIL` from resolvers still holding the old
delegation within that time, are not triggers.

**Inputs.** The `<previous-ns>` set and the private export of the previous zone.

**Procedure.**

1. At the registrar, restore the `<previous-ns>` set, changing nothing else.
2. If the previous provider no longer holds the zone's records, re-create them there from the
   private export.
3. Keep the Route 53 zone. Retiring it is a separate step
   ([Retire the hosted zone](#retire-the-hosted-zone)).
4. Repeat step 2 of [Pre-cutover checks](#pre-cutover-checks), and step 3 against each
   `<previous-ns>` in place of `<route53-ns>`.

**Expected result.** Every parent server returns the `<previous-ns>` set, and each previous name
server answers `SOA` with the `aa` flag.

**Known limitations.**

- Never executed. The export and the previous name-server set of the validated deployment exist
  only in private evidence; a reproducer needs their own.
- The done criterion covers the parent servers and the previous name servers, not resolvers. In
  the validated run 1.1.1.1 held the Route 53 NS set with 172800 s remaining. Design-review
  reasoning, not measurement: a resolver holding that set keeps querying Route 53 after a
  rollback until its entry expires. The zone is kept until the retirement wait in
  [Public DNS](../../terraform/foundation/README.md#public-dns) has passed.

### Retire the hosted zone

| Field | Value |
|---|---|
| Validation status | DESIGNED-NOT-EXECUTED (never) for the order; its destroy step is UNEXERCISED (never) |
| Published form | not executed as written (the reviewed order is in [Public DNS](../../terraform/foundation/README.md#public-dns); no command sheet exists) |
| Evidence basis | None; never executed |
| Authority | Explicit owner approval, at project end only |
| Cost | The zone bills until it is deleted |

**Purpose.** Decommission the zone without leaving a dangling delegation.

**Procedure.** The order (registrar first, the wait, the certificate before the zone, and
lifting `prevent_destroy` in a reviewed change) is in
[Public DNS](../../terraform/foundation/README.md#public-dns) and is not repeated here. The
reviewed checks before any destroy are:

1. Step 2 of [Pre-cutover checks](#pre-cutover-checks): no parent server lists a Route 53 name
   server.
2. Step 4 of [Pre-cutover checks](#pre-cutover-checks) at 1.1.1.1, 8.8.8.8 and 9.9.9.9: none
   returns the Route 53 set.
3. Steps 2 and 4 of [Read back the hosted zone](#read-back-the-hosted-zone): no record remains
   other than `NS`, `SOA` and the certificate's validation record. Route 53 deletes a zone only
   when its `NS` and `SOA` records alone remain
   ([Public DNS](../../terraform/foundation/README.md#public-dns)), so the validation record has
   to go first. Reviewed design, not measurement: the validation record depends on both the
   certificate and the zone, so Terraform removes it before either.

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

## Hidden prerequisites

- A registered apex domain at an external registrar, controlled by the operator, with a known
  renewal posture. Registration and renewal sit outside AWS and outside the AWS budget.
- Registrar access, with multi-factor sign-in, that can replace the domain's name-server set,
  plus knowledge of the domain's lock status and of whether the parent holds a DS record.
- A private export of the zone the previous provider serves, kept with its sha256, and the
  previous name-server set, both kept for rollback.
- The dedicated AWS account and an administrative operator session
  ([operator-access.md](operator-access.md)).
- The four foundation inputs in an untracked `terraform.tfvars` and the state bucket in an
  untracked `backend.hcl` ([Input](../../terraform/foundation/README.md#input)).
- Tools: the workstation toolchain in [operator-access.md](operator-access.md) (Terraform, the
  AWS provider and the AWS CLI); `jq`, `unzip` and `shasum` (or `sha256sum`) for the plan review
  and binding in [terraform-operations.md](terraform-operations.md); `dig`; and `curl` for the
  optional RDAP read.
- The parent zone's authoritative servers and the registry's RDAP base URL, discovered at run
  time.
- A private directory outside every Git working tree for saved plans
  ([terraform-operations.md](terraform-operations.md)).
- The four assigned name servers, the zone ID and the certificate ARN, read at run time and
  never recorded in shared material.
- An approver for each mutating step: the zone apply, the registrar change, the certificate
  apply, and any rollback, retirement or destroy.
