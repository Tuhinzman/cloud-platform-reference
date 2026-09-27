# Cost and Residue Runbook

Operates the cost controls that
[ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md#decision) requires and the
residue checks that close a runtime window. ADR-0013 owns the budget levels, review cadence and stop
conditions;
[ADR-0018](../decisions/0018-define-the-public-entry-implementation-dns-and-certificate-model.md#decision)
owns the orphan-scan classes. This runbook does not create the budget, activate tags, or run runtime
windows. A procedure labeled DESIGNED-NOT-EXECUTED or UNEXERCISED has never run
([validation labels](README.md#validation-labels)).

> **Warning: no hard cost cap exists.** AWS Budgets only notify, and ADR-0013 defers any automated
> cost response. These checks detect spend sooner; none of them limits it.

## When to use this runbook

| Trigger | Procedure |
|---|---|
| Before any billable change | [Budget check](#budget-check), then [Price check](#price-check) |
| Before the first billable resource ([task list](README.md#task-list)) | [Cost-allocation tags](#cost-allocation-tags) as well |
| Budget figures cannot answer a cost question | [Cost investigation](#cost-investigation); each request bills |
| Each operating session while the datastore instance exists | [CPU credits](#cpu-credits) |
| Weekly, first due 2026-10-01 | [Budget check](#budget-check), [CPU credits](#cpu-credits) and [Orphan census](#orphan-census), then [Weekly review](#weekly-review) |
| A budget level reached or projected | [Budget threshold response](#budget-threshold-response) |
| After every teardown, weekly, and at 150 and 200 USD | [Orphan census](#orphan-census) |
| An orphan found by the census or an investigation | [Orphan cleanup](#orphan-cleanup), with the owner's authorization for that object |

<a id="before-you-start"></a>
<a id="background-prerequisites"></a>
<a id="hidden-prerequisites"></a>

## Preconditions

- [ ] **The exported shell.** Every procedure runs in a `bash` shell prepared by
  [Export role credentials once](operator-access.md#export-role-credentials-once), steps 1 to 4,
  holding one exported role credential and nothing else. Continue only when it prints
  `ACCOUNT_MATCH=PASS` and no HOLD line, and the headroom check exits 0. Inputs:
  - `<root-tfvars>`: the bootstrap root's filled, untracked `<inputs-dir>/terraform.tfvars`, which
    sets `allowed_account_id` ([operator-access.md](operator-access.md#before-you-start)).
  - `<profile>`: ReadOnly for reads ([conventions](README.md#conventions)); for a cleanup, one that
    may delete that object's class. Every recorded run used the administrator permission set, so
    ReadOnly is unexercised here. A denied call is a failed read.
  - `<required-minutes>`: no minimum is established; use the expected duration plus a margin. After
    a destroy, the census's repeat bound alone takes about ten minutes.
- [ ] **Read access** to Budgets, Cost Explorer, the Price List API, CloudWatch metrics, and the EC2,
  ELB, Auto Scaling, EKS, RDS, CloudWatch Logs, SNS, IAM, Secrets Manager and Route 53 reads.
- [ ] **Tools:** AWS CLI v2 (no minimum version recorded), `bash` and `jq`.
- [ ] **Cost Explorer enabled** in the console; the API cannot enable it, data appears after about 24
  hours, and a member account's access depends on the management account.
- [ ] **The budget** `cloud-platform-reference`: monthly, cost, 200 USD, the project account's spend,
  created outside Terraform before the first billable resource (the state bucket), scoped to the
  project account in a management account. Five notifications, each `GREATER_THAN` with
  `ABSOLUTE_VALUE`: ACTUAL 100, 150 and 200, FORECASTED 150 and 200. Owner decisions recorded beside
  ADR-0013, not part of it: no FORECASTED 100, and no tags on the budget. Subscriber addresses stay
  private.
- [ ] **The six cost-allocation tag keys** activated by an identity with billing authority (the
  management account in an organization). AWS lists a key for activation only after a resource
  carries it; listing and activation each take up to 24 hours. On a new account the tag check passes
  only once tagged resources exist; no order is published, and until the owner decides one, that
  check's STOP holds.
- [ ] **The environment-hour ledger**, kept by hand with the fields ADR-0013 defines per window.
- [ ] **The expected persistent set:** the
  [architecture baseline](../architecture-baseline.md#persistent-foundations) register, the Dev
  root's retained addresses in
  [Confirm the retained and runtime split](dev-network.md#confirm-the-retained-and-runtime-split)
  and the [dev-datastore README](../../terraform/dev-datastore/README.md#what-it-creates).
- [ ] **A private records location** no repository tracks. The one
  [evidence-handling.md](evidence-handling.md) describes has not been practised.
- [ ] **An owner** who holds the ADR-0013 budget levels and authorizes each cleanup and each resume
  after a HOLD.

**Rules for every procedure.**

- Only `ACCOUNT_MATCH=PASS` shows which account answered; a wrong account prints plausible values.
  Retain the verdict with every record.
- Never print or record the account number, an ARN, or an email or subscriber address. Keep the
  account number in a variable and project identifiers out. Read error output on screen only; never
  copy it into evidence.
- Regional commands pass `--region us-east-1`; Budgets, Cost Explorer, IAM and Route 53 are global.
- Use `bash`: the census relies on its word splitting and `read -a`.
- STOP and HOLD halt the work. Without a written resume procedure, work stays stopped until the owner
  takes a reviewed decision ([When to stop](README.md#when-to-stop)).
- Figures are absolute USD.

<a id="read-back-the-budget-and-its-alert-states"></a>

## Budget check

**Validation:** AWS-VALIDATED (2026-09-24) · **Published command form:** not executed as written ·
**Authority:** none, read-only · **Cost:** none; no Cost Explorer request

Before any billable change and in every weekly review.

1. Read the account number into a variable without printing it.

   ```
   account=$(aws sts get-caller-identity --query Account --output text)
   ```

2. Read the budget. The projection omits the cost filter, which carries the account number.

   ```
   aws budgets describe-budgets --account-id "$account" \
     --query 'Budgets[?BudgetName==`"cloud-platform-reference"`].[BudgetName, BudgetType, TimeUnit, BudgetLimit.Amount, BudgetLimit.Unit, CalculatedSpend.ActualSpend.Amount, CalculatedSpend.ForecastedSpend.Amount]' \
     --output text
   ```

3. Read the notifications and their states.

   ```
   aws budgets describe-notifications-for-budget --account-id "$account" --budget-name cloud-platform-reference
   ```

4. Count each notification's subscribers without printing addresses.

   ```
   for n in ACTUAL:100 ACTUAL:150 ACTUAL:200 FORECASTED:150 FORECASTED:200; do
     printf '%s subscribers: ' "$n"
     aws budgets describe-subscribers-for-notification --account-id "$account" \
       --budget-name cloud-platform-reference \
       --notification "NotificationType=${n%%:*},ComparisonOperator=GREATER_THAN,Threshold=${n##*:},ThresholdType=ABSOLUTE_VALUE" \
       --query 'length(Subscribers)' --output text
   done
   ```

5. Optionally, read earlier months' actual spend. Period starts print in local time, so a month can
   appear to start a day early.

   ```
   aws budgets describe-budget-performance-history --account-id "$account" \
     --budget-name cloud-platform-reference \
     --query 'BudgetPerformanceHistory.BudgetedAndActualAmountsList[].[TimePeriod.Start, ActualAmount.Amount, BudgetedAmount.Amount]' \
     --output text
   ```

6. Clear the variable, whether or not you ran step 5.

   ```
   unset account
   ```

**PASS when.**

- [ ] Every read succeeded and returned output.
- [ ] Step 2 returned exactly one row with `cloud-platform-reference`, `COST`, `MONTHLY`, `200.0` and
  `USD`.
- [ ] Step 3 returned exactly the five notifications, each `GREATER_THAN` with `ABSOLUTE_VALUE`, each
  `OK` or `ALARM`. An `ALARM` is handled under **Next step**.
- [ ] Step 4 printed at least 1 for every notification.

**STOP if.**

- A read errors or returns nothing.
- The budget or a notification is missing or changed, or a notification has no subscriber: the
  ADR-0013 absent-alert stop condition. No billable resource is created; with no creation or resume
  procedure published, work stays stopped until the owner decides.
- A 150 or 200 notification, ACTUAL or FORECASTED, is in `ALARM`, unless each such level has an owner
  decision recorded this month that allows the change (see **Next step**).

**Next step.**

- ACTUAL 100 in `ALARM`, and nothing higher: ADR-0013 makes the 100 USD target a review, not a stop.
  Record it and run the 100 USD row of [Budget threshold response](#budget-threshold-response); the
  billable change may continue through the [Price check](#price-check).
- A 150 or 200 `ALARM`: do not continue to the price check; go to
  [Budget threshold response](#budget-threshold-response). If each 150 or 200 level in `ALARM` has an
  owner decision recorded this month, record each `ALARM` with a reference to its decision and
  continue only as those decisions allow.
- In a weekly review, record the states in entry 2 and finish the record before taking any level to
  its response.
- Otherwise go on to the [Price check](#price-check) for a billable change, or return to the runbook
  that sent you here.

**Evidence.** UTC time, `ACCOUNT_MATCH` verdict, pass or fail per criterion, the two spend figures and
the five states; never the unprojected response.

<a id="re-check-prices-before-billable-work"></a>

## Price check

**Validation:** AWS-VALIDATED (2026-09-24) · **Published command form:** not executed as written ·
**Authority:** none to read; a differing or missing rate needs owner approval · **Cost:** none

Immediately before each billable change; ADR-0013 requires it before the first billable resource. It
shows what AWS charges, not what the account was billed.

**Before you start.** Identify the rates the change bills from the root's README and its reviewed
plan.

1. Define the helper. It prints usage type, USD, unit and range start per price dimension.

   ```
   price() {
     local svc=$1 kv
     local f=()
     shift
     for kv in "$@"; do f+=("Type=TERM_MATCH,Field=${kv%%=*},Value=${kv#*=}"); done
     aws pricing get-products --region us-east-1 --service-code "$svc" --filters "${f[@]}" --output json |
       jq -r '.PriceList[] | fromjson | .product.attributes.usagetype as $u
              | .terms.OnDemand[].priceDimensions[] | [$u, .pricePerUnit.USD, .unit, .beginRange] | @tsv'
   }
   ```

2. Read the rates the change bills. These lines cover every rate in the table.

   ```
   price AmazonRDS regionCode=us-east-1 instanceType=db.t4g.micro databaseEngine=PostgreSQL deploymentOption=Single-AZ
   price AmazonRDS regionCode=us-east-1 usagetype=RDS:GP3-Storage databaseEngine=PostgreSQL deploymentOption=Single-AZ
   price AmazonRDS regionCode=us-east-1 usagetype=CPUCredits:db.t4g databaseEngine=PostgreSQL
   price AmazonRDS regionCode=us-east-1 usagetype=RDS:ChargedBackupUsage databaseEngine=PostgreSQL
   price AWSSecretsManager regionCode=us-east-1
   price AmazonRoute53 "productFamily=DNS Zone"
   price AmazonEKS "location=US East (N. Virginia)" usagetype=USE1-AmazonEKS-Hours:perCluster
   price AmazonEC2 "location=US East (N. Virginia)" instanceType=m6a.large operatingSystem=Linux tenancy=Shared preInstalledSw=NA capacitystatus=Used "licenseModel=No License required"
   price AmazonEC2 "location=US East (N. Virginia)" usagetype=NatGateway-Hours
   price AmazonEC2 "location=US East (N. Virginia)" usagetype=NatGateway-Bytes
   price AmazonVPC "location=US East (N. Virginia)" usagetype=USE1-PublicIPv4:InUseAddress
   price AmazonEC2 "location=US East (N. Virginia)" usagetype=EBS:VolumeUsage.gp3
   ```

3. Compare numerically each line whose usage type and range start are in the table (the helper
   prints ten-decimal strings such as `0.0160000000`). Ignore other range starts, such as Route 53's
   `HostedZone` line from 25, and usage types not in the table.

**Price table.** us-east-1, on-demand:

| Rate | Usage type | From | USD | Unit |
|---|---|---|---|---|
| RDS `db.t4g.micro`, PostgreSQL, Single-AZ | `InstanceUsage:db.t4g.micro` | 0 | 0.016 | instance-hour |
| RDS gp3 storage, PostgreSQL | `RDS:GP3-Storage` | 0 | 0.115 | GB-month |
| RDS T4g CPU credits, PostgreSQL | `CPUCredits:db.t4g` | 0 | 0.075 | vCPU-hour |
| RDS backup storage beyond the free allocation, PostgreSQL | `RDS:ChargedBackupUsage` | 0 | 0.095 | GB-month |
| Secrets Manager secret | `USE1-AWSSecretsManager-Secrets` | 0 | 0.40 | secret per month |
| Secrets Manager API requests | `USE1-AWSSecretsManagerAPIRequest` | 0 | 0.000005 | API request (0.05 USD per 10,000) |
| Route 53 hosted zone, first 25 | `HostedZone` | 0 | 0.50 | zone per month |
| EKS control plane | `USE1-AmazonEKS-Hours:perCluster` | 0 | 0.10 | cluster-hour |
| EC2 `m6a.large`, Linux, shared tenancy | `BoxUsage:m6a.large` | 0 | 0.0864 | instance-hour |
| NAT gateway | `NatGateway-Hours` | 0 | 0.045 | hour |
| NAT gateway data processing | `NatGateway-Bytes` | 0 | 0.045 | GB |
| Public IPv4 address in use | `USE1-PublicIPv4:InUseAddress` | 0 | 0.005 | address-hour |
| EBS gp3 volume | `EBS:VolumeUsage.gp3` | 0 | 0.08 | GB-month |

**PASS when.** Every rate the change bills is in the table, returned a line with the expected usage
type and range start, and equals the table's value.

**STOP if.** A value differs, a billed rate is missing from the table, or a read fails or returns no
matching line. Stop before the change, re-estimate and obtain owner approval; no re-estimation
procedure is written. The table has no rate for Route 53 queries (0.40 USD per million,
[Public DNS](../../terraform/foundation/README.md#public-dns)), load balancers, registry storage or S3
storage, so a change billing them, such as a hosted-zone build
([Build the zone on its own](public-dns-and-certificate.md#build-the-zone-on-its-own)), always stops
here. A changed EKS control plane, NAT gateway or public IPv4 rate also triggers the ADR-0013 revisit.

**Next step.** This check does not approve the change, which proceeds only under its own approval.
Return to the runbook that sent you here.

**Evidence.** UTC time, each rate as read, and the verdict.

<a id="read-back-the-cost-allocation-tags"></a>

## Cost-allocation tags

**Validation:** AWS-VALIDATED (2026-09-10) · **Published command form:** executed as written ·
**Authority:** none, read-only · **Cost:** up to USD 0.01, one Cost Explorer request

Before the first billable resource. Billing groups spend by a tag only while it is active.

1. List the active cost-allocation tags.

   ```
   aws ce list-cost-allocation-tags --status Active
   ```

**PASS when.** The `UserDefined` keys are exactly `Project`, `Environment`, `Component`, `Lifecycle`,
`Owner` and `ManagedBy`, each `Active`; a seventh key or a missing one fails. `AWSGenerated` entries
are recorded and do not fail the check.

**STOP if.** The check fails: cost attribution cannot be demonstrated, an ADR-0013 stop condition. No
activation command is published; work stays stopped until the owner decides.

**Evidence.** UTC time and the listed keys with status and type.

<a id="break-spend-down-with-cost-explorer"></a>

## Cost investigation

**Validation:** AWS-VALIDATED (2026-09-10) for step 1; EXECUTED — RECORDED ONLY; RETAINED EXECUTION
EVIDENCE NOT AVAILABLE (2026-09-12) for step 2 · **Published command form:** not executed as written ·
**Authority:** none, read-only · **Cost:** USD 0.01 per Cost Explorer request

Only when the budget figures cannot answer the question, because each request bills. Figures lag by
hours: a missing line is not zero cost, and the current month is estimated. `<first-day>` and
`<day-after-last-day>` are UTC `YYYY-MM-DD` dates; `End` is exclusive.

1. Read spend by service for the project account.

   > **Warning:** Keep the account filter. In an AWS Organizations management account the
   > unfiltered view covers every member account.

   ```
   account=$(aws sts get-caller-identity --query Account --output text)
   aws ce get-cost-and-usage --time-period Start=<first-day>,End=<day-after-last-day> \
     --granularity MONTHLY --metrics UnblendedCost \
     --filter "{\"Dimensions\":{\"Key\":\"LINKED_ACCOUNT\",\"Values\":[\"$account\"]}}" \
     --group-by Type=DIMENSION,Key=SERVICE \
     --query 'ResultsByTime[].{start: TimePeriod.Start, estimated: Estimated, services: Groups[].[Keys[0], Metrics.UnblendedCost.Amount]}' \
     --output json
   unset account
   ```

2. Optionally, read the spend that carries the project tag.

   ```
   aws ce get-cost-and-usage --time-period Start=<first-day>,End=<day-after-last-day> \
     --granularity MONTHLY --metrics UnblendedCost \
     --filter '{"Tags":{"Key":"Project","Values":["cloud-platform-reference"]}}' \
     --query 'ResultsByTime[].[TimePeriod.Start, Estimated, Total.UnblendedCost.Amount]' --output text
   ```

**PASS when.** Each non-zero line maps to a known persistent foundation or an approved window; zero
lines are recorded, not treated as spend.

**STOP if.** A non-zero line maps to nothing: unexplained spend, an ADR-0013 stop condition. Further
billable work holds; with no investigation procedure written, work stays stopped until the owner
decides.

**Evidence.** UTC time, period, the `Estimated` flag and each line with its mapping.

<a id="check-the-datastore-cpu-credits"></a>

## CPU credits

**Validation:** AWS-VALIDATED (2026-09-24) for one 300-second read; DESIGNED-NOT-EXECUTED (never) for
the recurring cadence and the 3,600-second form · **Published command form:** not executed as written ·
**Authority:** none, read-only · **Cost:** within the CloudWatch free allowance

The datastore runs in unlimited CPU-credit mode: surplus credits bill once they exceed 24 hours of
earnings, or when the instance stops or is deleted, and no alarm exists
([costs](../../terraform/dev-datastore/README.md#decommission)). This check detects a runaway; it does
not cap spend, erase incurred cost or change the 200 USD ceiling. Detection lags by the check
interval, the five-minute metric period and an undocumented publishing delay.

`<previous-check-utc>` is the previous check's ISO 8601 UTC time, such as `2026-09-24T18:48:40Z`; for
the first check, the instance's creation time or earlier.

1. Set the span and period: 300 seconds up to five days, 3,600 beyond; one call returns at most 1,440
   datapoints.

   ```
   since=<previous-check-utc>
   now=$(date -u +%FT%TZ)
   period=300
   ```

2. Read the metrics. `TZ=UTC` keeps timestamps in UTC.

   ```
   for m in CPUSurplusCreditBalance:Maximum CPUSurplusCreditsCharged:Sum CPUCreditBalance:Minimum CPUUtilization:Average CPUUtilization:Maximum; do
     TZ=UTC aws cloudwatch get-metric-statistics --region us-east-1 --namespace AWS/RDS \
       --dimensions Name=DBInstanceIdentifier,Value=cloud-platform-reference-dev-datastore \
       --metric-name "${m%%:*}" --statistics "${m##*:}" \
       --period "$period" --start-time "$since" --end-time "$now" \
       --query "sort_by(Datapoints, &Timestamp)[].[Timestamp, ${m##*:}]" --output text |
       sed "s/^/$m /"
   done
   ```

**PASS when.**

- [ ] Every metric printed lines. No lines means no datapoints, not zero: check the span and the
  identifier, and allow for the five-minute period.
- [ ] `CPUSurplusCreditsCharged` is 0 in every period since the last check.
- [ ] `CPUSurplusCreditBalance` is 0 in the latest periods.

A surplus balance above 0 with a documented cause, such as the start-up burst after a create or start,
and nothing charged, is recorded as an explained review trigger. The next check must show a balance of
0 and nothing charged.

**REVIEW and HOLD.** Any charge, or an unexplained surplus balance, is a REVIEW: optional billable work
holds until it is explained, and the instance keeps running. Investigate in that session when the
balance rises across
two checks or CPU averages above 10 percent over 24 hours (the EC2 `t4g.micro` baseline, applied to
RDS by inference; no 24-hour average has been computed). The response is owner-controlled and
UNEXERCISED: find the CPU consumer and end any window driving it. Stopping or decommissioning the
instance are not exercised procedures ([dev-datastore.md](dev-datastore.md)).

> **Warning:** Stopping ends instance-hours but bills any outstanding surplus and loses earned
> credits, and AWS restarts a stopped instance after seven days.

**Evidence.** One dated private line per check: UTC time, `ACCOUNT_MATCH` verdict, period and span,
maximum surplus balance, sum charged, minimum credit balance, average and maximum CPU, and verdict.

<a id="record-the-weekly-adr-0013-review"></a>

## Weekly review

**Validation:** DESIGNED-NOT-EXECUTED (never; first due 2026-10-01) for the record; UNEXERCISED
(never) for the entry 4 commands · **Published command form:** not executed as written ·
**Authority:** the continue, REVIEW or HOLD decision is the owner's · **Cost:** USD 0.01 per Cost
Explorer request in entry 6

Run that week's [Budget check](#budget-check), [Orphan census](#orphan-census) and
[CPU credits](#cpu-credits) first. If the datastore build stopped after Stage 1, no instance exists.
Read only the **Checks that still apply** bullet under
[Stopping after Stage 1](dev-datastore.md#stopping-after-stage-1); its "Stopping here ends the path"
ends the build path, not this review. The CPU-credit input and entry 5, entry 4's instance status and
the first period's start then have no published form: record in entry 7 how the owner decided to
record each.

Write one dated private record per review, not in a sealed evidence set. The period starts at the
previous record, the first at the instance's creation. Keep each entry to what the linked procedure's
**Evidence** names, and redact identifiers with your own literal list and filter per
[Redact at capture](evidence-handling.md#redact-at-capture), steps 1 to 4 (PASS: the step 4 re-scan
finds nothing). The record does not cover ADR-0013's other weekly duties. The seven entries:

1. Review time (UTC) and reviewer.
2. Budget: month-to-date actual, forecast (absent if not returned, never 0), the five states, and the
   level reached or projected. Across a month start, add the budget check's step 5 for the previous
   month. Nothing defines "approaching" 100 USD or a projection method: state what yours rests on.
3. Census: every runtime class 0 outside an approved window; exception classes as expected.
4. Persistent set: instance status, secrets (total, scheduled for deletion), hosted zones (total,
   private) and manual DB snapshots, one line each: `True` when its name starts with the datastore's
   final-snapshot name (so `-final-2` counts), then its status and creation time. This tracks the
   final-snapshot rule in the
   [dev-datastore README](../../terraform/dev-datastore/README.md#decommission); a `False` line is a
   snapshot that rule does not cover. Expected: instance
   `available`; 4 secrets (the Dev network's two, the datastore's two), none scheduled for deletion;
   1 hosted zone, not private; no manual snapshot before a decommission.

   > **Warning:** These commands are derived and have not been reviewed or run.

   ```
   aws rds describe-db-instances --region us-east-1 --db-instance-identifier cloud-platform-reference-dev-datastore \
     --query 'DBInstances[].DBInstanceStatus' --output text
   aws secretsmanager list-secrets --region us-east-1 --include-planned-deletion \
     --query '[length(SecretList), length(SecretList[?DeletedDate])]' --output text
   aws route53 list-hosted-zones --query '[length(HostedZones), length(HostedZones[?Config.PrivateZone])]' --output text
   aws rds describe-db-snapshots --region us-east-1 --snapshot-type manual \
     --query 'DBSnapshots[].[starts_with(DBSnapshotIdentifier, `"cloud-platform-reference-dev-datastore-final"`), Status, SnapshotCreateTime]' --output text
   ```

5. CPU credits over every check in the period, this review's included: the largest maximum surplus
   balance, the total charged, the largest maximum CPU, and how the average was derived. A span over
   five days needs the 3,600-second form, which has never run.
6. Environment-hour reconciliation for any window that week (no procedure published), and
   unexplained spend: none, or the explanation, using [Cost investigation](#cost-investigation) if
   needed. The persistent set has no expected monthly cost, and registry and S3 storage have no table
   rate (registry storage shows only as a Cost Explorer service line). Record none only when all
   spend maps to a known resource or an approved window.
7. The decision, continue, REVIEW or HOLD, and why.

**PASS when.** One dated private record holds all seven entries, identifiers redacted, with the
decision and why.

**Evidence.** The dated private record itself.

**HOLD if.** A review is missed: no record by its due date, with no grace period. Optional billable
work holds until the review is done and the datastore's retention is explicitly reconsidered. This
starts with the 2026-10-01 review; the owner decides whether earlier unrecorded weeks hold work.

**Routing.** Take each finding to its procedure: a level to
[Budget threshold response](#budget-threshold-response), a census STOP to
[Orphan census](#orphan-census), unexplained spend to [Cost investigation](#cost-investigation), a
CPU-credit REVIEW to [CPU credits](#cpu-credits), an unowned resource to
[Orphan cleanup](#orphan-cleanup), and an unexpected persistent-set value to entry 7. For a secret
scheduled for deletion, the reads of
[Verify the secret containers without reading a value](dev-datastore.md#verify-the-secret-containers-without-reading-a-value)
and [Read back the two Secrets Manager entries](dev-network.md#read-back-the-two-secrets-manager-entries)
show which secret holds the date; ignore their **Next step**, record it in entry 4 and decide in
entry 7.

<a id="respond-to-the-100-150-and-200-usd-levels"></a>

## Budget threshold response

**Validation:** DESIGNED-NOT-EXECUTED (never) for the 150 and 200 USD responses; UNEXERCISED (never)
for the 100 USD target review · **Published command form:** not executed as written ·
**Authority:** the owner decides every resume; each destructive step needs its own explicit owner
authorization · **Cost:** USD 0.01 per Cost Explorer request when a row needs one

Nothing responds automatically, and no level has been reached. No alert fires while spend approaches
100 USD; only the weekly review or a window estimate detects it. ADR-0013 states what each level
requires, halts and permits.

1. Run the [Budget check](#budget-check) and record the figures and states.
2. Identify the highest level reached or projected.
3. Carry out its row and the rest of its ADR-0013 list, which has no procedure here.

   > **Warning:** Each destructive step needs its own explicit owner authorization. Export evidence
   > that must survive a destroy first and read it back after
   > ([Export the sealed set before teardown](evidence-handling.md#export-the-sealed-set-before-teardown),
   > [Read back exported evidence after destruction](evidence-handling.md#read-back-exported-evidence-after-destruction)).
   > Decommissioning the datastore has not been exercised.

4. Record the decision and the evidence it rests on.

| Level | Trigger | Effect | Actions | Status |
|---|---|---|---|---|
| 100 USD target | ACTUAL 100 (fires only above 100 USD), or a review or estimate approaching it | Review, not a stop | [Cost investigation](#cost-investigation); [Orphan census](#orphan-census) to confirm the last teardown; ledger reconciliation (no procedure) | UNEXERCISED |
| 150 USD review threshold | ACTUAL or FORECASTED 150, or a projection past it | ADR-0013 stop condition without a written justification; owner review before further billable work | [Cost investigation](#cost-investigation) for the written explanation; [Orphan census](#orphan-census); ledger reconciliation (no procedure) | DESIGNED-NOT-EXECUTED |
| 200 USD ceiling | ACTUAL or FORECASTED 200, or a projection at or above it | ADR-0013 stop condition; hold | [Orphan census](#orphan-census); [Cost investigation](#cost-investigation) for unexplained spend; [Orphan cleanup](#orphan-cleanup) for what the census finds | DESIGNED-NOT-EXECUTED |

**PASS when.** The budget figures and states, the highest level with its row carried out, and the
owner decision with the evidence it rests on are recorded.

**STOP if.** A 150 or 200 USD level is reached or projected; ADR-0013 states what halts and what
continues. No resume procedure is published: work resumes only on the owner's decision, which at 200
USD must be a new explicit decision that changes the ceiling.

**Evidence.** Budget figures and states, the written cost explanation where required, the census
output, and a reference to the owner decision.

<a id="run-the-orphan-census"></a>

## Orphan census

**Validation:** AWS-VALIDATED (2026-09-22) for the runtime-residue classes without a datastore
instance; OFFLINE-VALIDATED (2026-09-22) for the datastore exception classes with a live instance ·
**Published command form:** not executed as written · **Authority:** none, read-only · **Cost:** none

Shows that nothing in the runtime classes exists outside an approved window; the persistent datastore
counts in separate exception classes. Run it with no apply or destroy in progress and, after a window,
with its pre-open census at hand. It is fail-closed: a class is absent only when its read succeeded
and printed 0; anything else is `UNKNOWN`, and a census with any `UNKNOWN` proves nothing.

> **Warning:** In the wrong account the census prints plausible zeros. Only the `ACCOUNT_MATCH=PASS`
> verdict shows which account answered.

1. Define the helpers. `q` prints a count or `UNKNOWN`; `role` prints 1, 0 or `UNKNOWN`.

   ```
   q() {
     local v
     v=$(aws "$@" --region us-east-1 --output text 2>/dev/null) || { echo UNKNOWN; return; }
     case $v in '' | *[!0-9]*) echo UNKNOWN ;; *) echo "$v" ;; esac
   }
   role() {
     local err
     if err=$(aws iam get-role --role-name "$1" --query Role.RoleName --output text 2>&1 >/dev/null); then echo 1
     elif [[ $err == *NoSuchEntity* ]]; then echo 0
     else echo UNKNOWN; fi
   }
   sub() { case "$1$2" in *[!0-9]*) echo UNKNOWN ;; *) echo $(( $1 - $2 )) ;; esac; }
   ```

2. Find the datastore security group by its tags. An empty result is a valid zero; a failed read is
   not.

   ```
   ds_groups=$(aws ec2 describe-security-groups --region us-east-1 \
     --filters Name=tag:Project,Values=cloud-platform-reference Name=tag:Component,Values=datastore Name=tag:Lifecycle,Values=persistent \
     --query 'SecurityGroups[].GroupId' --output text 2>/dev/null) || ds_groups=UNKNOWN
   read -ra ds <<< "$ds_groups"
   ```

3. Run the census and keep its output privately.

   ```
   DB=cloud-platform-reference-dev-datastore
   TOPIC=:cloud-platform-reference-dev-alerting
   if [ "$ds_groups" = UNKNOWN ]; then ds_sg=UNKNOWN ds_eni=UNKNOWN
   else
     ds_sg=${#ds[@]}
     if [ "$ds_sg" -ne 1 ]; then ds_eni=0
     else ds_eni=$(q ec2 describe-network-interfaces --filters "Name=group-id,Values=${ds[0]}" \
       --query 'length(NetworkInterfaces[?RequesterManaged==`true` && Description==`"RDSNetworkInterface"` && length(Groups)==`1`])')
     fi
   fi
   echo "CENSUS_AT=$(date -u +%FT%TZ)"
   echo "EBS=$(q ec2 describe-volumes --query 'length(Volumes)')"
   echo "EC2=$(q ec2 describe-instances --filters Name=instance-state-name,Values=pending,running,stopping,stopped --query 'length(Reservations[].Instances[])')"
   echo "ASG=$(q autoscaling describe-auto-scaling-groups --query 'length(AutoScalingGroups)')"
   echo "EIP=$(q ec2 describe-addresses --query 'length(Addresses)')"
   echo "NAT=$(q ec2 describe-nat-gateways --filter Name=state,Values=pending,available,deleting,failed --query 'length(NatGateways)')"
   echo "LAUNCH_TEMPLATE=$(q ec2 describe-launch-templates --query 'length(LaunchTemplates)')"
   echo "EKS=$(q eks list-clusters --query 'length(clusters)')"
   echo "ALB_NLB=$(q elbv2 describe-load-balancers --query 'length(LoadBalancers)')"
   echo "CLB=$(q elb describe-load-balancers --query 'length(LoadBalancerDescriptions)')"
   echo "TARGET_GROUPS=$(q elbv2 describe-target-groups --query 'length(TargetGroups)')"
   echo "LOG_GROUPS=$(q logs describe-log-groups --query 'length(logGroups)')"
   echo "ENI=$(sub "$(q ec2 describe-network-interfaces --query 'length(NetworkInterfaces)')" "$ds_eni")"
   echo "SG_NON_DEFAULT_RUNTIME=$(sub "$(q ec2 describe-security-groups --query "length(SecurityGroups[?GroupName!='default'])")" "$ds_sg")"
   echo "RDS_UNEXPECTED=$(q rds describe-db-instances --query "length(DBInstances[?DBInstanceIdentifier!='$DB'])")"
   echo "SNS_TOPICS_CAMPAIGN=$(q sns list-topics --query "length(Topics[?ends_with(TopicArn, '$TOPIC')])")"
   echo "SNS_SUBSCRIPTIONS_CAMPAIGN=$(q sns list-subscriptions --query "length(Subscriptions[?ends_with(TopicArn, '$TOPIC')])")"
   echo "IAM_ALERTING_ROLE=$(role cloud-platform-reference-dev-grafana-alerting)"
   echo "IAM_EKS_CLUSTER_ROLE=$(role cloud-platform-reference-dev-eks-cluster)"
   echo "IAM_EKS_NODE_ROLE=$(role cloud-platform-reference-dev-eks-node)"
   clusters=$(aws eks list-clusters --region us-east-1 --query 'clusters[]' --output text 2>/dev/null) || clusters=UNKNOWN
   for c in $clusters; do
     echo "POD_IDENTITY_ASSOCIATIONS[$c]=$(q eks list-pod-identity-associations --cluster-name "$c" --query 'length(associations)')"
     echo "EKS_ADDONS[$c]=$(q eks list-addons --cluster-name "$c" --query 'length(addons)')"
   done
   echo "DATASTORE_SG=$ds_sg"
   echo "DATASTORE_ENI=$ds_eni"
   echo "RDS_DATASTORE=$(q rds describe-db-instances --query "length(DBInstances[?DBInstanceIdentifier=='$DB'])")"
   ```

4. After a destroy, repeat steps 2 and 3 together in the same shell, up to 20 times 30 seconds apart,
   until one complete census shows every runtime class at 0. A resource still deleting is not
   absent.
5. Compare with the table and, after a window, with its pre-open census.

| Class | Expected between windows and after a teardown |
|---|---|
| `EBS`, `EC2`, `ASG`, `EIP`, `NAT`, `LAUNCH_TEMPLATE`, `EKS`, `ALB_NLB`, `CLB`, `TARGET_GROUPS`, `LOG_GROUPS` | 0, counted across the whole region rather than by tag |
| `ENI` (all interfaces less the datastore's) | 0. With the instance present, this rests on the `DATASTORE_ENI` classification, which is OFFLINE-VALIDATED only |
| `SG_NON_DEFAULT_RUNTIME` (non-default groups less the datastore's) | 0 |
| `RDS_UNEXPECTED` (any instance other than the datastore, including a restore target) | 0 |
| `SNS_TOPICS_CAMPAIGN`, `SNS_SUBSCRIPTIONS_CAMPAIGN` (the Dev root's alerting-campaign topic and its subscriptions; [Alerting](../../terraform/dev/README.md#alerting)) | 0 |
| `IAM_ALERTING_ROLE`, `IAM_EKS_CLUSTER_ROLE`, `IAM_EKS_NODE_ROLE` | 0 |
| `POD_IDENTITY_ASSOCIATIONS`, `EKS_ADDONS` | no lines, because no cluster exists |
| `DATASTORE_SG` (exception class) | 1 while the dev-datastore root is applied |
| `RDS_DATASTORE` (exception class) | 1 while the instance exists |
| `DATASTORE_ENI` (exception class) | 1 while the instance exists; never yet run against a live instance |

**PASS when.** No `UNKNOWN`; once settled, every runtime class 0 and no `POD_IDENTITY_ASSOCIATIONS`
or `EKS_ADDONS` line; each exception class as expected; after a window, compared with the pre-open
census.

**STOP or HOLD if.**

- Any `UNKNOWN`: HOLD. Fix the cause (session, permission, region) and rerun the whole census; never
  edit a value. To find the cause, rerun the failing query without `2>/dev/null` and read the error on
  screen only.
- A runtime class above 0 once settled, or at the bound: an orphaned resource, an ADR-0013 stop
  condition. Investigate before further billable work and remove it only through
  [Orphan cleanup](#orphan-cleanup). Right after a destroy of the dev root it may be an incomplete
  destroy: run steps 1 to 3 of
  [Confirm the retained and runtime split](dev-network.md#confirm-the-retained-and-runtime-split)
  with its **Before you start** met (PASS: 21 retained addresses in state, 17 to add, no drift), then
  return here instead of following its **Next step**. On its PASS the class is an orphan; on its STOP,
  work stays stopped as its **If it fails** says.
- `DATASTORE_SG` other than 1 with the datastore root applied, `RDS_DATASTORE` other than 1 when the
  instance should exist, or `DATASTORE_ENI` other than 1 with it present: HOLD and review, the first
  live run included. No review procedure is written; work stays stopped until the owner decides.
- `RDS_UNEXPECTED` above 0, an instance nobody reviewed such as a restore target: HOLD.

**Evidence.** The counts, UTC time, `ACCOUNT_MATCH` verdict and, after a window, the pre-open census
compared. A census after a window's teardown joins its final evidence set
([evidence-handling.md](evidence-handling.md#normal-path), step 9).

<a id="clean-up-an-orphan"></a>

## Orphan cleanup

**Validation:** AWS-VALIDATED (2026-09-11) for one SNS subscription only · **Published command form:**
not executed as written · **Authority:** mutating and destructive; explicit owner authorization naming
the one object, never a general cleanup permission · **Cost:** none; removing an orphan ends its
charge

Removes one orphan: a resource no Terraform root declares or holds in state, that is neither a
persistent foundation nor a datastore exception class, and that belongs to no open window. Only one
class has been removed, once: an email subscription left on a deleted SNS topic.

1. Investigate read-only. Project only the fields needed; never read an endpoint, value or address.
   For a subscription, leave the endpoint out and record whether it is pending confirmation.
2. Confirm it is an orphan and record each answer: no root in this repository declares it; no root's
   state holds it (on each root, initialized per
   [Initialize a root against the state backend](terraform-operations.md#initialize-a-root-against-the-state-backend),
   run step 1 of [Inspect state without writing it](terraform-operations.md#inspect-state-without-writing-it);
   PASS here: the object is not listed, and that procedure's other criteria and **Next step** do not
   apply); it is neither a persistent foundation nor a datastore exception class; it belongs to no
   open window; and whether its parent still exists.
3. Record the class, why it is an orphan, and its cost effect.
4. Obtain explicit owner authorization bounded to that one object and no other change.
5. Capture anything it must still yield, per steps 3 and 4 of
   [Capture a campaign evidence set](evidence-handling.md#capture-a-campaign-evidence-set), through
   [Redact at capture](evidence-handling.md#redact-at-capture), steps 1 to 4 (PASS: the step 4
   re-scan finds nothing). Never a subscription's endpoint.
6. Remove it with its own delete call, one object at a time. For a subscription, capture its ARN from
   a listing projected to it, without printing it, and count what the variable holds. `<topic-name>`
   is the subscription's topic.

   ```
   sub_arn=$(aws sns list-subscriptions --region us-east-1 \
     --query "Subscriptions[?ends_with(TopicArn, ':<topic-name>')].SubscriptionArn" --output text)
   wc -w <<< "$sub_arn"
   ```

   > **Warning:** Delete only when the variable holds exactly one ARN, and only under step 4's
   > authorization. `PendingConfirmation` in its place is an unconfirmed subscription this call
   > cannot remove, and it also counts as one word: rely on step 1's record.

   ```
   aws sns unsubscribe --region us-east-1 --subscription-arn "$sub_arn"
   unset sub_arn
   ```

7. Read back absence with the object's own read. `NotFound` is absence; any other error is `UNKNOWN`,
   not absence. No read-back command is published.
8. Run the [Orphan census](#orphan-census) again; a runtime class still above 0 is a STOP there. The
   census proves absence only where a class covers the object; otherwise the read-back is the proof.

**PASS when.** The authorization names this one object, the removal exited 0, the read-back shows it
absent, and the census has run again.

**STOP or HOLD if.**

- Terraform declares or holds it: not an orphan. Reconcile through Terraform
  ([terraform-operations.md](terraform-operations.md)), never by hand.
- A datastore exception class: never removed here; its decommission has not been exercised.
- Ownership is unclear: HOLD.
- The read-back is `UNKNOWN`: not absence. No procedure is written; work stays stopped until the owner
  decides.
- The subscription is pending confirmation, or the variable holds anything but exactly one ARN: HOLD.
  A pending subscription cannot be unsubscribed; it is recorded as deleted only with its topic, and no
  procedure for it is published.

**Evidence.** Investigation output without identifiers, the authorization reference, the removal's
exit status and the read-back result.

## Engineering notes

What each published form derives from, and its evidence. Evidence is retained privately unless linked.

| Procedure | Published form | Evidence |
|---|---|---|
| Budget check | Step 3 as executed; step 2 adds the projection; step 4 hard-codes the five notifications and counts; step 5's executed command was not retained | 2026-09-10 and 2026-09-24 reads |
| Price check | Executed Price List filters; the helper, `jq` parsing and three datastore usage-type filters are derived | Reads of 2026-09-10 to 2026-09-24, each before a billable change |
| Cost-allocation tags | Executed as written | Two 2026-09-10 reads with raw output |
| Cost investigation | Account number from the session instead of a literal, plus a projection; step 2's command and output were not retained | 2026-09-10 reads with raw output; a record of the 2026-09-12 value |
| CPU credits | Command lines not retained; follows the reviewed design, the first read's 300-second period and its confirming read's `TZ=UTC` | The 2026-09-24 read and its confirming read |
| Weekly review | Never run; derived from the reviewed cost decision; entry 4 commands unreviewed; the snapshot listing prints no identifier | None |
| Budget threshold response | Never triggered; derived from ADR-0013 and the recorded budget policy | None |
| Orphan census | Queries follow the private census tool; helpers, SNS, IAM and per-cluster EKS lines rewritten; VPC count omitted; datastore steps derived from the tool's rule | The 2026-09-22 censuses ([ADR-0019](../decisions/0019-bound-immutable-image-controls-for-aws-managed-runtime-images.md#evidence), [Runtime Validation](../validation/runtime-validation.md#what-has-been-demonstrated)); offline controls of the tool |
| Orphan cleanup | Generalized from the single cleanup; the ARN variable is derived | The 2026-09-11 investigation, authorization, removal and read-back |

## Known limitations

- The forecast was unreliable on this account's short history (observed 2026-08-08), so FORECASTED
  alerts may not fire; ACTUAL alerts do not depend on it.
- Budget figures refresh up to three times a day. The budget check does not read the cost filter,
  cost types or time period, and the budget's tags have not been read back.
- Alert delivery is untested; an `ALARM` state does not prove a message arrived.
- Active tag keys show the billing setting, not that cost records carry the tags; attribution by tag
  is not demonstrated end to end.
- The census covers us-east-1 only. ADR-0018 classes 1, 2 and 4 are counted directly, 3 and 5 only
  through the load-balancer and interface counts, and 6 and 7 not at all. SNS and IAM classes are
  name-scoped. Persistent billable classes (hosted zone and records, certificates, S3 buckets,
  registry repositories, Parameter Store entries, DB snapshots) are outside it. It has never run with
  the datastore instance present, and its repeat path has never been needed.

### Not yet exercised

Besides the parts labeled DESIGNED-NOT-EXECUTED or UNEXERCISED above (the weekly review, required
since 2026-08-01 and never recorded; the level responses; the CPU-credit cadence, 3,600-second form
and response):

- **Budget creation** (2026-08-06) and **tag activation** (2026-08-21): EXECUTED — RECORDED ONLY;
  RETAINED EXECUTION EVIDENCE NOT AVAILABLE; UNEXERCISED as reproducible procedures.
- **Resume after any ADR-0013 stop condition**: UNEXERCISED, with no procedure; a failed state
  recovery or secret rotation has none in any runbook.
- **ADR-0013's other weekly duties** (budget anomaly, registry and retained-resource, and
  evidence-retention reviews, and evidence each persistent foundation is still needed), **ledger
  reconciliation**, and **estimate against actual** by the `Component` tag: UNEXERCISED.
- **Price checks** for Route 53 queries, load balancers, and registry and S3 storage: UNEXERCISED.
- **Cleanup** of any class but a confirmed SNS subscription, including a pending one and
  controller-created load balancers, target groups or security groups: UNEXERCISED.
- **Reads on the read-only permission set**: never run.

### Reproducibility gaps

- **Budget creation, tag activation and enabling Cost Explorer:** need public procedures placed in the
  build order; Cost Explorer needs a console procedure, since the API cannot enable it, and when it
  was enabled on the reference account is not recorded.
- **Re-estimation, ledger reconciliation, resume after a stop condition, unexplained-spend
  investigation, the CPU-credit response, other weekly duties and further cleanup classes:** need
  procedures, including instance stop and
  [decommission](../../terraform/dev-datastore/README.md#decommission) for the CPU-credit response.
- **The census as validated:** the retained results and offline controls exercised a private tool,
  not these helpers; needs live and offline-controlled runs of the published helpers.
- **The AWS CLI version:** never recorded.

## Related references

- [ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md): budget levels, cadence,
  tagging and stop conditions.
- [ADR-0018](../decisions/0018-define-the-public-entry-implementation-dns-and-certificate-model.md):
  orphan-scan classes.
- [operator-access.md](operator-access.md): sessions, the exported shell and the account check.
- [terraform-operations.md](terraform-operations.md): state and reconciling what Terraform owns.
- [evidence-handling.md](evidence-handling.md): capture, redaction, export and read-back.
- [dev-network.md](dev-network.md), [dev-datastore.md](dev-datastore.md): the retained baseline and
  the datastore.
- [Runtime Validation](../validation/runtime-validation.md#windows): runtime windows and their cost.
