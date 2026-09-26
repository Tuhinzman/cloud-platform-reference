# Cost and Residue Runbook

Operates the cost controls
[ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md#decision) requires and the
residue checks that close a runtime window. ADR-0013 owns the budget levels, the review cadence and
the stop conditions;
[ADR-0018](../decisions/0018-define-the-public-entry-implementation-dns-and-certificate-model.md#decision)
owns the named orphan-scan classes. This runbook does not create the budget, activate the tags, or
run and tear down runtime windows. A procedure labeled DESIGNED-NOT-EXECUTED or UNEXERCISED has never
run ([validation labels](README.md#validation-labels)).

> **Warning: no hard cost cap exists.** AWS Budgets notify and never prevent spend, and ADR-0013
> defers any automated cost response. These checks detect spend sooner; none of them limits it.

## When to use this runbook

| Trigger | Procedure |
|---|---|
| Before any billable change | [Budget check](#budget-check), then [Price check](#price-check) |
| Before the first billable resource ([task list](README.md#task-list)) | [Cost-allocation tags](#cost-allocation-tags) as well |
| The budget figures cannot answer a cost question | [Cost investigation](#cost-investigation); each request bills |
| Each operating session while the datastore instance exists | [CPU credits](#cpu-credits) |
| Weekly, first due 2026-10-01 | Budget check, CPU credits and [Orphan census](#orphan-census), then [Weekly review](#weekly-review) |
| A budget level reached or projected | [Budget threshold response](#budget-threshold-response) |
| After every teardown, weekly, and at 150 and 200 USD | [Orphan census](#orphan-census) |
| One orphan found by the census or an investigation | [Orphan cleanup](#orphan-cleanup), with the owner's authorization for that object |

<a id="before-you-start"></a>
<a id="background-prerequisites"></a>
<a id="hidden-prerequisites"></a>

## Preconditions

- [ ] **The exported shell.** Every procedure runs in a `bash` shell prepared by
  [Export role credentials once](operator-access.md#export-role-credentials-once), steps 1 to 4,
  holding one exported role credential and nothing else. Continue only on `ACCOUNT_MATCH=PASS` with
  no HOLD line and the headroom line with exit 0. Its inputs:
  - `<root-tfvars>`: the absolute path of the bootstrap root's filled, untracked
    `<inputs-dir>/terraform.tfvars` with `allowed_account_id`; create it as
    [operator-access.md](operator-access.md#before-you-start) describes if it does not exist.
  - `<profile>`: the ReadOnly profile for reads ([conventions](README.md#conventions)); for a
    cleanup, one that may delete that object's class. Every recorded read and cleanup ran on the
    administrator permission set; ReadOnly is unexercised here. A denied call is a failed read.
  - `<required-minutes>`: no minimum or read duration is established; use the expected duration plus
    a margin. After a destroy, the census's repeat bound alone spans about ten minutes.
- [ ] **Read access** to Budgets, Cost Explorer, the Price List API, CloudWatch metrics, and the EC2,
  ELB, Auto Scaling, EKS, RDS, CloudWatch Logs, SNS, IAM, Secrets Manager and Route 53 reads.
- [ ] **Tools:** AWS CLI v2 (no minimum version recorded), `bash` and `jq`.
- [ ] **Cost Explorer enabled** by a one-time console action; the API cannot enable it, data appears
  about 24 hours later, and in an organization member account access depends on the management
  account.
- [ ] **The budget** `cloud-platform-reference`: monthly, cost, 200 USD, the project account's spend,
  created outside Terraform before the first billable resource (the state bucket). Five
  notifications, each `GREATER_THAN` with `ABSOLUTE_VALUE`: ACTUAL 100, 150 and 200, FORECASTED 150
  and 200. By owner decisions recorded beside ADR-0013, not part of it, there is no FORECASTED 100
  and the budget carries none of the six tags. In a management account, scope it to the project
  account. Subscriber addresses are held privately.
- [ ] **The six cost-allocation tag keys** activated by an identity with billing authority (in an
  organization, the management account). AWS offers a key only after a resource carries it, and each
  step takes up to 24 hours. On a new account the tag check before the first billable resource
  passes only if tagged resources exist; no order is published, and until the owner decides one,
  that check's STOP holds.
- [ ] **The environment-hour ledger**, kept by hand with the fields ADR-0013 defines per window.
- [ ] **The expected persistent set:** the register in the
  [architecture baseline](../architecture-baseline.md#persistent-foundations), the Dev root's
  retained addresses in
  [Confirm the retained and runtime split](dev-network.md#confirm-the-retained-and-runtime-split),
  and the [dev-datastore README](../../terraform/dev-datastore/README.md#what-it-creates).
- [ ] **A private records location** no repository tracks, for dated lines, review records, census
  outputs and cleanup records. The location [evidence-handling.md](evidence-handling.md) describes has
  not been practised.
- [ ] **An owner** who authorizes each cleanup and each resume after a HOLD, and who holds the ADR-0013
  budget levels.

**Rules for every procedure.**

- Only `ACCOUNT_MATCH=PASS` shows which account answered; the wrong account prints plausible values.
  Retain the verdict with every record.
- Never print or record the account number, an ARN, or an email or subscriber address. Commands keep
  the account number in a variable, and `--query` projections keep identifiers out of output. Error
  output is not projected: read it on screen, never copy it into evidence.
- Regional commands pass `--region us-east-1`; Budgets, Cost Explorer, IAM and Route 53 are global.
- Use `bash`: the census and the helpers rely on its word splitting and `read -a`.
- STOP and HOLD halt the work where they occur. Without a written resume procedure, work stays
  stopped until the owner takes a reviewed decision ([When to stop](README.md#when-to-stop)).
- Every figure is absolute USD.

<a id="read-back-the-budget-and-its-alert-states"></a>

## Budget check

**Validation:** AWS-VALIDATED (2026-09-24) · **Published command form:** not executed as written ·
**Authority:** none, read-only · **Cost:** none; Budgets reads, no Cost Explorer request

Before any billable change and in every weekly review. Reads the budget, month-to-date spend, the
forecast and each alert's state.

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
   appear to start on the previous day.

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
  `OK` or `ALARM`. This checks shape; an `ALARM` is still a STOP.
- [ ] Step 4 printed at least 1 for every notification.

**STOP if.**

- A read errors or returns nothing.
- The budget or a notification is missing or changed, or a notification has no subscriber: the
  ADR-0013 absent-alert stop condition. No billable resource is created, and with no creation or
  resume procedure published, work stays stopped until the owner decides.
- A notification is in `ALARM`: follow **Next step**.

**Next step.** On an `ALARM`, do not continue to the price check: go to
[Budget threshold response](#budget-threshold-response). In a weekly review, record the states in
entry 2, finish the record, then take the level there. If the level has an owner decision recorded
this month, record the `ALARM` with a reference to it and continue only as it allows. A billable
change goes on to the [Price check](#price-check) only when all five are `OK`, or an owner decision
recorded this month allows each `ALARM` level. Otherwise, if another runbook sent you here, return to
it.

**Evidence.** UTC time, `ACCOUNT_MATCH` verdict, pass or fail per criterion, the two spend figures and
the five states; never the unprojected response.

<a id="re-check-prices-before-billable-work"></a>

## Price check

**Validation:** AWS-VALIDATED (2026-09-24) · **Published command form:** not executed as written ·
**Authority:** none to read; a differing or missing rate needs owner approval · **Cost:** none; Price
List API reads

Immediately before each billable change; ADR-0013 requires it before the first billable resource. It
states what AWS charges, not what the account was billed.

**Before you start.** Identify the rates the change bills from the root's README and its reviewed
plan.

1. Define the helper. It prints usage type, USD, unit and range start for each price dimension.

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

3. Compare numerically each line whose usage type and range start appear in the table; the helper
   prints ten-decimal strings such as `0.0160000000`. Ignore other range starts, such as Route 53's
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

**STOP if.** A value differs, a billed rate is not in the table, or a read errors or returns no
matching line. Stop before the billable change, re-estimate and obtain owner approval; no written
re-estimation procedure exists. The table lacks the Route 53 query rate (0.40 USD per million
queries, [Public DNS](../../terraform/foundation/README.md#public-dns)), load balancers, registry
storage and S3 storage, so any change billing them stops here, including a hosted-zone build
([Build the zone on its own](public-dns-and-certificate.md#build-the-zone-on-its-own)). A changed EKS
control plane, NAT gateway or public IPv4 rate also triggers the ADR-0013 revisit.

**Evidence.** UTC time, each rate as read, and the verdict.

**Next step.** The billable change proceeds only under its own approval; this check is not that
approval. If another runbook sent you here, return to it.

<a id="read-back-the-cost-allocation-tags"></a>

## Cost-allocation tags

**Validation:** AWS-VALIDATED (2026-09-10) · **Published command form:** executed as written ·
**Authority:** none, read-only · **Cost:** up to USD 0.01, one Cost Explorer request

Before the first billable resource. Billing groups spend by a tag only while it is active.

1. List the active cost-allocation tags.

   ```
   aws ce list-cost-allocation-tags --status Active
   ```

**PASS when.** The set of `UserDefined` keys is exactly `Project`, `Environment`, `Component`,
`Lifecycle`, `Owner` and `ManagedBy`, each `Active`: a seventh key or a missing one fails. An
`AWSGenerated` entry is recorded and does not fail the check.

**STOP if.** The check fails: cost attribution cannot be demonstrated, an ADR-0013 stop condition. No
activation command and no procedure for a seventh key is published; work stays stopped until the
owner decides.

**Evidence.** UTC time and the listed keys with status and type.

<a id="break-spend-down-with-cost-explorer"></a>

## Cost investigation

**Validation:** AWS-VALIDATED (2026-09-10) for step 1; EXECUTED — RECORDED ONLY; RETAINED EXECUTION
EVIDENCE NOT AVAILABLE (2026-09-12) for step 2 · **Published command form:** not executed as written ·
**Authority:** none, read-only · **Cost:** USD 0.01 per Cost Explorer request

Only when the budget figures cannot answer the question, such as a written cost explanation or the
weekly review's entry 6, because each request bills. Cost Explorer lags by hours: a missing line is
not zero cost, and current-month figures are estimates. `<first-day>` and `<day-after-last-day>` are
UTC `YYYY-MM-DD` dates; `End` is exclusive.

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

**PASS when.** Each non-zero line maps to a known persistent foundation or an approved window;
zero-amount lines are recorded, not treated as spend.

**STOP if.** A non-zero line maps to nothing: unexplained spend, an ADR-0013 stop condition. Further
billable work holds; no investigation or resume procedure is written, so work stays stopped until the
owner decides.

**Evidence.** UTC time, period, the `Estimated` flag and each line with its mapping.

<a id="check-the-datastore-cpu-credits"></a>

## CPU credits

**Validation:** AWS-VALIDATED (2026-09-24) for one 300-second read; DESIGNED-NOT-EXECUTED (never) for
the recurring cadence and the 3,600-second form · **Published command form:** not executed as written ·
**Authority:** none, read-only · **Cost:** none recorded; within the CloudWatch free allowance

The datastore instance runs in unlimited CPU-credit mode: surplus credits are billed once they exceed
24 hours of earnings, or when the instance stops or is deleted. No alarm exists, so this check is how
a runaway is detected between budget alerts. It does not cap spend, erase incurred cost or change the
200 USD ceiling; detection takes up to the check interval plus the five-minute metric period and an
undocumented publishing delay. Costs and the stress case are in the
[dev-datastore README](../../terraform/dev-datastore/README.md#decommission).

`<previous-check-utc>` is the previous check's ISO 8601 UTC time, such as `2026-09-24T18:48:40Z`,
from its dated line; for the first check, use the instance's creation time or earlier.

1. Set the span and period: 300 seconds for up to five days, 3,600 beyond; one call returns at most
   1,440 datapoints.

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
  identifier, and allow for the metric period.
- [ ] `CPUSurplusCreditsCharged` is 0 in every period since the last check.
- [ ] `CPUSurplusCreditBalance` is 0 in the latest periods.

A surplus balance above 0 with a documented cause, such as the start-up burst after a create or start,
and nothing charged, is an explained review trigger, recorded with its cause. The next check must show
a balance of 0 and nothing charged.

**REVIEW and HOLD.** Any charge, or a surplus balance above 0 without a documented cause, is a REVIEW
and puts further optional billable work on HOLD until explained; the instance keeps running.
Investigate when the balance rises across two checks or CPU averages above 10 percent over 24 hours
(the EC2 `t4g.micro` per-vCPU baseline, applied to RDS by inference; no 24-hour average has been
computed). The response is owner-controlled and UNEXERCISED: find the CPU consumer and end any window
driving it. Stopping or decommissioning the instance are not exercised procedures
([dev-datastore.md](dev-datastore.md)).

> **Warning:** Stopping ends instance-hours but bills any outstanding surplus and loses earned
> credits, and AWS restarts a stopped instance after seven days.

**Evidence.** One dated private line per check: UTC time, `ACCOUNT_MATCH` verdict, period and span,
maximum surplus balance, sum charged, minimum credit balance, average and maximum CPU, and the verdict.

<a id="record-the-weekly-adr-0013-review"></a>

## Weekly review

**Validation:** DESIGNED-NOT-EXECUTED (never; first due 2026-10-01) for the record fields; UNEXERCISED
(never) for the entry 4 commands · **Published command form:** not executed as written ·
**Authority:** the continue, REVIEW or HOLD decision is the owner's · **Cost:** up to USD 0.01 per
Cost Explorer request in entry 6

Run that week's [Budget check](#budget-check), [Orphan census](#orphan-census) and
[CPU credits](#cpu-credits) first. With the datastore stopped after Stage 1, no instance exists: the
CPU-credit check does not run, and the entries that need an instance follow **Checks that still
apply** under [Stopping after Stage 1](dev-datastore.md#stopping-after-stage-1), that bullet only.
The CPU-credit input and entry 5, the instance status in entry 4 and the first period's start then
have no published form; how each is recorded is the owner's decision in entry 7. Its "Stopping here
ends the path" ends the build path, not this review.

Write one dated private record per review in the private records location, not in a sealed evidence
set. The period runs from the previous record, the first from the instance's creation. Redact
identifiers with your own private literal list and filter, which the project does not publish, per
[Redact at capture](evidence-handling.md#redact-at-capture), steps 1 to 4 (PASS: the step 4 re-scan
finds nothing). Keep each entry to what the linked procedure's **Evidence** names. The record does not
cover ADR-0013's other weekly duties, which have no procedure ([Not yet exercised](#not-yet-exercised)).
The seven entries:

1. Review time (UTC) and reviewer.
2. Budget: month-to-date actual, forecast (absent if not returned, never 0), the five alert states,
   and the level reached or projected (none, target, review threshold or ceiling). If the period
   crosses a month start, also run the budget check's step 5 for the previous month. Nothing defines
   approaching 100 USD or a projection method: state what the projection rests on.
3. Census: every runtime class 0 outside an approved window; exception classes as expected.
4. Persistent set: instance status, secrets (total, scheduled for deletion), hosted zones (total,
   private) and a dated listing of manual DB snapshots, which tracks the final-snapshot rule in the
   [dev-datastore README](../../terraform/dev-datastore/README.md#decommission). Expected: instance
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
     --query 'DBSnapshots[].[DBSnapshotIdentifier, Status, SnapshotCreateTime]' --output text
   ```

5. CPU credits across every check in the period, this review's included: the largest maximum surplus
   balance, the total charged, the largest maximum CPU, and how the average was derived. A span over
   five days needs the 3,600-second form, which has never run.
6. Environment-hour reconciliation for any window that week (no procedure published), and unexplained
   spend: none, or the explanation, using [Cost investigation](#cost-investigation) when needed. No
   expected monthly cost exists for the persistent set, and registry and S3 storage have no table
   rate; registry storage cost is visible here only as a Cost Explorer service line. Record none only
   when all spend maps to a known resource or an approved window.
7. The decision, continue, REVIEW or HOLD, and why.

**PASS when.** One dated private record holds all seven entries, identifiers redacted, with the
decision and why.

**HOLD if.** A review is missed: no record by its due date, with no grace period. Optional billable
work holds until the review is done and the datastore's retention is explicitly reconsidered. This
starts with the 2026-10-01 review; whether earlier uncovered weeks hold work is the owner's decision.

**Routing findings.** A level reached or projected goes to
[Budget threshold response](#budget-threshold-response), a census STOP to
[Orphan census](#orphan-census), unexplained spend to [Cost investigation](#cost-investigation), a
CPU-credit REVIEW to [CPU credits](#cpu-credits), and a resource nothing owns to
[Orphan cleanup](#orphan-cleanup). An unexpected persistent-set value has no procedure and goes to
entry 7. For a secret scheduled for deletion, run the reads of
[Verify the secret containers without reading a value](dev-datastore.md#verify-the-secret-containers-without-reading-a-value)
and [Read back the two Secrets Manager entries](dev-network.md#read-back-the-two-secrets-manager-entries);
the one printing a deletion date holds it. Ignore their **Next step**: record the secret in entry 4
and take it to entry 7.

<a id="respond-to-the-100-150-and-200-usd-levels"></a>

## Budget threshold response

**Validation:** DESIGNED-NOT-EXECUTED (never) for the 150 and 200 USD responses; UNEXERCISED (never)
for the 100 USD target review · **Published command form:** not executed as written ·
**Authority:** owner; the owner decides every resume, and each destructive step needs its own explicit
owner authorization · **Cost:** USD 0.01 per Cost Explorer request when a row needs one

ADR-0013 states what each level requires, halts and permits. Nothing responds automatically, no level
has been reached, and alert delivery is untested. No alert fires while spend approaches 100 USD; only
the weekly review or a window estimate detects it.

1. Run the [Budget check](#budget-check) and record the figures and states.
2. Identify the highest level reached or projected.
3. Carry out that level's row and the rest of its ADR-0013 list, which has no procedure here.

   > **Warning:** Each destructive step needs its own explicit owner authorization. Export evidence
   > that must survive a destroy first and read it back after
   > ([Export the sealed set before teardown](evidence-handling.md#export-the-sealed-set-before-teardown),
   > [Read back exported evidence after destruction](evidence-handling.md#read-back-exported-evidence-after-destruction)).
   > Decommissioning the datastore has not been exercised.

4. Record the decision and the evidence it rests on.

| Level | Trigger | Actions | Status |
|---|---|---|---|
| 100 USD target | ACTUAL 100 (fires only above 100 USD), or a weekly review or window estimate approaching it | [Cost investigation](#cost-investigation); [Orphan census](#orphan-census) to confirm the last teardown; environment-hour reconciliation (no procedure) | UNEXERCISED |
| 150 USD review threshold | ACTUAL or FORECASTED 150, or a projection past 150 USD | [Cost investigation](#cost-investigation) for the written explanation; [Orphan census](#orphan-census); environment-hour reconciliation (no procedure) | DESIGNED-NOT-EXECUTED |
| 200 USD ceiling | ACTUAL or FORECASTED 200, or a projection at or above 200 USD | [Orphan census](#orphan-census); [Cost investigation](#cost-investigation) for unexplained spend; [Orphan cleanup](#orphan-cleanup) for what the census finds | DESIGNED-NOT-EXECUTED |

**STOP.** The 150 and 200 USD levels carry ADR-0013 stop conditions; what halts and what continues is
stated there. No resume procedure is published: work resumes only on the owner's decision.

**Evidence.** Budget figures and states, the written cost explanation where required, the census
output, and a reference to the owner decision.

<a id="run-the-orphan-census"></a>

## Orphan census

**Validation:** AWS-VALIDATED (2026-09-22) for the runtime-residue classes without a datastore
instance; OFFLINE-VALIDATED (2026-09-22) for the datastore exception classes with a live instance ·
**Published command form:** not executed as written · **Authority:** none, read-only · **Cost:** none

Shows that nothing in the runtime classes exists outside an approved window, with the persistent
datastore in separate exception classes. Run it with no apply or destroy in progress and, after a
window, its pre-open census at hand. It is fail-closed: a class is absent only when its read
succeeded and printed 0; anything else is `UNKNOWN`, and a census with any `UNKNOWN` proves nothing.

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

4. After a destroy, repeat steps 2 and 3 together, up to 20 times 30 seconds apart, until one
   complete census shows every runtime class at 0. A resource still deleting is not absent.
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

**PASS when.** No `UNKNOWN`; once settled, every runtime class 0 and no `POD_IDENTITY_ASSOCIATIONS` or
`EKS_ADDONS` line; each exception class as the table expects; after a window, compared with the
pre-open census.

**STOP or HOLD if.**

- Any `UNKNOWN`: HOLD. Fix the cause (session, permission, region) and rerun the whole census; never
  edit a value. To find the cause, rerun the failing query without `2>/dev/null` and read the error
  on screen only.
- A runtime class above 0 once settled, or when the bound is reached: an orphaned resource, an
  ADR-0013 stop condition. Investigate before further billable work and remove it only through
  [Orphan cleanup](#orphan-cleanup). Right after a Terraform destroy of the dev root it may be an
  incomplete destroy: run steps 1 to 3 of
  [Confirm the retained and runtime split](dev-network.md#confirm-the-retained-and-runtime-split)
  with its **Before you start** met (PASS: the 21 retained addresses in state, 17 to add, no drift),
  then return here, not to its **Next step**. On its PASS the class is an orphan; on its STOP, work
  stays stopped as its **If it fails** says.
- `DATASTORE_SG` other than 1 with the datastore root applied, `RDS_DATASTORE` other than 1 when the
  instance should exist, or `DATASTORE_ENI` other than 1 with it present: HOLD and review, the first
  live run included. No review procedure is written; work stays stopped until the owner decides.
- `RDS_UNEXPECTED` above 0, an instance nobody reviewed such as a restore target: HOLD.

**Evidence.** The counts, UTC time, `ACCOUNT_MATCH` verdict and, after a window, the pre-open census
compared. A census after a window's teardown enters its final evidence set
([evidence-handling.md](evidence-handling.md#normal-path), step 9).

<a id="clean-up-an-orphan"></a>

## Orphan cleanup

**Validation:** AWS-VALIDATED (2026-09-11) for one SNS subscription only · **Published command form:**
not executed as written · **Authority:** mutating and destructive; explicit owner authorization naming
the one object, never a general cleanup permission · **Cost:** none; removing a billing orphan ends
its charge

Removes one resource the census or an investigation found, without widening the change. An orphan is
a resource no Terraform root declares or holds in state, that is neither a persistent foundation nor a
datastore exception class, and that belongs to no open window. Only one class has been removed, once:
an email subscription left on a deleted SNS topic.

1. Investigate read-only. Project only the fields needed; never read an endpoint, value or address.
   For a subscription, leave the endpoint out and record whether it is pending confirmation.
2. Confirm it is an orphan and record each answer: no root in this repository declares it; no root's
   state holds it (on each root, initialized per
   [Initialize a root against the state backend](terraform-operations.md#initialize-a-root-against-the-state-backend),
   run step 1 of [Inspect state without writing it](terraform-operations.md#inspect-state-without-writing-it);
   PASS here: the object is not listed, and that procedure's other criteria and its **Next step** do
   not apply); it is neither a persistent foundation nor a datastore
   exception class; it belongs to no open window; and whether its parent still exists.
3. Record the disposition: class, why it is an orphan, and its cost effect.
4. Obtain explicit owner authorization bounded to that one object and no other change.
5. Capture anything it must still yield, per steps 3 and 4 of
   [Capture a campaign evidence set](evidence-handling.md#capture-a-campaign-evidence-set), each
   output through [Redact at capture](evidence-handling.md#redact-at-capture), steps 1 to 4 (PASS: the
   step 4 re-scan finds nothing). Never a subscription's endpoint.
6. Remove it with its own delete call, one object at a time. For a subscription, capture the ARN from
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
   not absence, and has no written procedure. No read-back command is published here.
8. Run the [Orphan census](#orphan-census) again; a runtime class still above 0 is a STOP there. The
   census shows the object absent only where a class covers it; otherwise the read-back is the proof.

**PASS when.** The authorization names this one object, the removal exited 0, the read-back shows it
absent, and the census has run again.

**STOP or HOLD if.**

- Terraform declares or holds it: not an orphan. Reconcile through Terraform
  ([terraform-operations.md](terraform-operations.md)), never by hand.
- A datastore exception class: never removed here; its decommission has not been exercised.
- Ownership is unclear: HOLD.
- The subscription is pending confirmation, or the variable holds anything but exactly one ARN:
  HOLD. A pending subscription cannot be unsubscribed; it is recorded as deleted only with its topic,
  and no procedure for it is published.

**Evidence.** Investigation output without identifiers, the authorization reference, the removal's
exit status and the read-back result.

## Engineering notes

Audit detail behind each Validation line: what the published form is derived from, and the evidence it
rests on. Evidence is retained privately unless linked.

| Procedure | Published form derived from | Evidence basis |
|---|---|---|
| Budget check | Step 3 is the executed form; step 2 adds a projection so no account number prints; step 4 hard-codes the five notifications and adds a count projection; step 5 derives from a read whose command was not retained | ADR-0013; the 2026-09-10 budget and notification reads, and the 2026-09-24 check before the datastore apply and cost reads |
| Price check | The filters of the executed Price List reads; the helper, its `jq` parsing and three datastore usage-type filters are derived | ADR-0013 (provisional estimates); the 2026-09-10 runtime-rate reads, the 2026-09-22 EKS re-check, the 2026-09-22 and 2026-09-24 datastore, Secrets Manager and Route 53 reads, the 2026-09-23 re-check before the hosted-zone apply, and the 2026-09-24 comparison before the datastore apply |
| Cost-allocation tags | Executed as written | ADR-0013 (tagging); two 2026-09-10 reads with raw output |
| Cost investigation | The executed read passed the account number literally; here it comes from the session and a projection is added. Step 2's command and raw output were not retained | ADR-0013; the 2026-09-10 account-scoped reads with raw output; a record of the 2026-09-12 project-tag value |
| CPU credits | The executed command lines were not retained; the metrics and statistics follow the reviewed design, the 300-second default the first read, and `TZ=UTC` its confirming read | The dev-datastore README; the 2026-09-24 first read and its confirming read; the reviewed cost decision that designed the check |
| Weekly review | Never run; the fields follow the reviewed cost decision; the entry 4 commands are derived and unreviewed | ADR-0013; no execution evidence |
| Budget threshold response | Never triggered; derived from ADR-0013 and the recorded budget policy | ADR-0013; no execution evidence |
| Orphan census | The region-wide queries follow the private census tool; the count helpers, the SNS, IAM and per-cluster EKS lines are rewritten, the VPC count is omitted, and the datastore steps derive from the tool's classification rule | ADR-0013; ADR-0018; [ADR-0019](../decisions/0019-bound-immutable-image-controls-for-aws-managed-runtime-images.md#evidence) (the 2026-09-22 zero-node window); [Runtime Validation](../validation/runtime-validation.md#what-has-been-demonstrated); the 2026-09-22 censuses; offline controls for the tool's classifier and three-state rule |
| Orphan cleanup | Generalized from the single 2026-09-11 cleanup, whose removal call is step 6's example; capturing the ARN into a variable is derived | ADR-0013; the 2026-09-11 investigation, bounded authorization, removal and read-back |

## Known limitations

- The FORECASTED alerts may not fire: the forecast was observed on 2026-08-08 to be unreliable on this
  account's short history. The ACTUAL alerts do not depend on it.
- Budget figures lag billing and refresh up to three times a day. The budget check does not read the
  cost filter, cost types or time period, and the budget's tags have not been read back.
- Alert delivery has never been tested; an `ALARM` state is not evidence a message arrived.
- Active tag keys show the billing setting, not that cost records carry the tags. Attribution by tag
  is not demonstrated end to end; the project-tag read ran once and kept no command or raw output.
- The census covers us-east-1 only. ADR-0018 classes 1, 2 and 4 are counted directly, 3 and 5 only
  through the load-balancer and interface counts, 6 and 7 not at all. SNS and IAM classes are
  name-scoped. Persistent billable classes (hosted zone and records, certificates, S3 buckets,
  registry repositories, Parameter Store entries, DB snapshots) are outside it. It has never run with
  the datastore instance present, and its repeat path has never been needed.

### Not yet exercised

- **Budget creation** (2026-08-06) and **tag activation** (2026-08-21): EXECUTED — RECORDED ONLY;
  RETAINED EXECUTION EVIDENCE NOT AVAILABLE. As reproducible procedures, UNEXERCISED.
- **The 100 USD target review**: UNEXERCISED. **The 150 and 200 USD responses**:
  DESIGNED-NOT-EXECUTED.
- **Halt, continue and resume procedures for the ADR-0013 stop conditions**: UNEXERCISED. This
  runbook detects an absent budget alert, unexplained spend, an orphaned resource and undemonstrable
  cost attribution, with no resume procedure for any. A failed state recovery or secret rotation has
  no procedure in any runbook ([terraform-operations.md](terraform-operations.md),
  [dev-datastore.md](dev-datastore.md)).
- **The weekly review record**: DESIGNED-NOT-EXECUTED, its entry 4 commands UNEXERCISED. ADR-0013 has
  required it since 2026-08-01, and no record exists yet. **ADR-0013's other weekly duties** (budget
  anomaly, registry and retained-resource, and evidence-retention reviews, and evidence that each
  persistent foundation is still needed): UNEXERCISED.
- **Environment-hour ledger reconciliation**: UNEXERCISED; no procedure is published.
- **The CPU-credit cadence and 3,600-second form**: DESIGNED-NOT-EXECUTED. **Its response**:
  UNEXERCISED.
- **Price checks for the Route 53 query rate, load balancers, registry and S3 storage**, and
  **estimate against actual for the datastore** by the `Component` tag: UNEXERCISED.
- **Cleanup of any class but a confirmed SNS subscription**, a pending one included, and of a
  controller-created load balancer, target group or security group: UNEXERCISED.
- **Any read here on the read-only permission set**: never run.

### Reproducibility gaps

What cannot yet be reproduced from the public repositories, and what is needed:

- **Budget creation, tag activation and enabling Cost Explorer.** No procedure or command is
  published, no order for a new account exists, and the Cost Explorer enablement date is not
  recorded. Public contract: ADR-0013, the budget shape in [Preconditions](#preconditions), and the
  budget and tag checks. Needed: creation and activation procedures placed in the build order, and a
  console procedure for Cost Explorer, which the API cannot enable.
- **Re-estimation, ledger reconciliation, resume after an ADR-0013 stop condition, the unexplained
  spend investigation and the CPU-credit response.** Public contract: ADR-0013, the detecting
  procedures and the datastore [Decommission](../../terraform/dev-datastore/README.md#decommission)
  design. Needed: procedures for each, with stop and decommission procedures for the instance.
- **The census as validated.** The retained results and offline controls exercised a private tool,
  not the helpers published here. Needed: live and offline-controlled runs of the published helpers;
  no public control harness exists.
- **ADR-0013's other weekly duties, and cleanup beyond one SNS subscription.** Needed: procedures,
  each cleanup class when first needed.
- **The AWS CLI version.** Never recorded; closes when a run records it.

## Related references

- [ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md): budget levels, review
  cadence, tagging and stop conditions.
- [ADR-0018](../decisions/0018-define-the-public-entry-implementation-dns-and-certificate-model.md):
  named orphan-scan classes.
- [operator-access.md](operator-access.md): sessions, the exported shell and the account check.
- [terraform-operations.md](terraform-operations.md): state and reconciling what Terraform owns.
- [evidence-handling.md](evidence-handling.md): capture, redaction, export and read-back.
- [dev-network.md](dev-network.md), [dev-datastore.md](dev-datastore.md): the retained baseline and
  the datastore.
- [Runtime Validation](../validation/runtime-validation.md#windows): runtime windows, teardown and
  per-window cost.
