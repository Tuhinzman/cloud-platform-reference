# Cost and Residue Runbook

This runbook covers the recurring cost operations that
[ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md#decision) requires, and the
residue checks that close them: reading back the budget, its alerts and the cost-allocation tags,
re-checking prices before billable work, breaking spend down with Cost Explorer, checking the
datastore's CPU credits, recording the weekly review, responding to the three budget levels, and
finding and removing orphaned resources. It does not create the budget or activate the tags; no
procedure is published for either (see [Reproducibility gaps](#reproducibility-gaps)). It does not
run or tear down runtime windows. A runtime window creates the EKS cluster, its nodes and the NAT
gateway on top of the Dev network's retained baseline ([dev-network.md](dev-network.md)), exercises
them and destroys them at close.

It links rather than restates. ADR-0013 is the authority for the budget levels, the review cadence
and the stop conditions, and
[ADR-0018](../decisions/0018-define-the-public-entry-implementation-dns-and-certificate-model.md#decision)
for the named orphan-scan classes. The datastore's cost estimate, protections and decommission
design are in the [dev-datastore README](../../terraform/dev-datastore/README.md#decommission), and
its operations in [dev-datastore.md](dev-datastore.md). Runtime windows, their teardown and their
per-window cost are summarized in [Runtime Validation](../validation/runtime-validation.md#windows).
Sessions are in [operator-access.md](operator-access.md), Terraform state in
[terraform-operations.md](terraform-operations.md), and evidence capture, redaction, export and
read-back in [evidence-handling.md](evidence-handling.md). Validation labels are defined in the
[runbook index](README.md#validation-labels).

> **Warning: no hard cost cap exists.** Nothing in this runbook caps spend, and no hard cost cap is
> claimed. AWS Budgets notify and never prevent spend. No automated cost response exists, because
> ADR-0013 defers it. Every check below detects spend sooner; none of them limits it.

## Normal path

Each item runs on its own occasion, named in the item: before a billable change, before the first
billable resource, each operating session, weekly, after a teardown, or on a trigger. Run only the
items today's occasion calls for.

1. **Pre-change budget check.**
   [Read back the budget and its alert states](#read-back-the-budget-and-its-alert-states), before
   any billable change and in every weekly review.
2. **Price check.** [Re-check prices before billable work](#re-check-prices-before-billable-work),
   before each billable change.
3. **Cost attribution.** [Read back the cost-allocation tags](#read-back-the-cost-allocation-tags)
   before the first billable resource ([task list](README.md#task-list)), and
   [Break spend down with Cost Explorer](#break-spend-down-with-cost-explorer) only when the budget
   figures cannot answer a cost question, because each request bills.
4. **CPU-credit check.** [Check the datastore CPU credits](#check-the-datastore-cpu-credits), at the
   start of each operating session while the datastore instance exists.
5. **Weekly review.** [Record the weekly ADR-0013 review](#record-the-weekly-adr-0013-review), every
   week; the first is due 2026-10-01. Run that week's budget read-back (item 1), CPU-credit check
   (item 4) and census (item 7) first: the record uses their results.
6. **Budget-level response.**
   [Respond to the 100, 150 and 200 USD levels](#respond-to-the-100-150-and-200-usd-levels), only when
   a level is reached or projected.
7. **Orphan census.** [Run the orphan census](#run-the-orphan-census), after every teardown, in every
   weekly review and at the 150 and 200 USD levels.
8. **Orphan cleanup.** [Clean up an orphan](#clean-up-an-orphan), only for one object the census or
   an investigation found, with the owner's authorization for that object.

## Before you start

- [ ] **A dedicated AWS account and an operator session** as [operator-access.md](operator-access.md)
  describes. The account number is kept locally and never recorded.
- [ ] **The exported shell.** Every procedure runs inside a `bash` shell prepared by
  [Export role credentials once](operator-access.md#export-role-credentials-once): a clean shell
  that holds one exported role credential and nothing else, so no command here names a profile. Its
  export ends with the [account check](operator-access.md#check-the-account-before-aws-commands), which
  prints only a verdict. Continue only on `ACCOUNT_MATCH=PASS`.
- [ ] **For the account check:** the absolute path of `<root-tfvars>`, a filled, untracked root
  `terraform.tfvars` that sets `allowed_account_id`, the account pin
  ([operator-access.md](operator-access.md#before-you-start)). Each root holds the same dedicated
  account's ID; cost work targets no root.
- [ ] **The `<profile>` the shell is exported from.** For the reads, the ReadOnly profile, which
  inspection is meant for ([runbook conventions](README.md#conventions)); for a cleanup, a profile
  that may delete that one object's class. Running these reads on the ReadOnly profile has never
  been exercised: every recorded read and the 2026-09-11 cleanup ran on the administrator permission
  set (Rules for every procedure, below). A denied call is a failed read, never a pass, and the
  census prints `UNKNOWN` for it.
- [ ] **A session requirement for the headroom check.** The exported shell's headroom check needs
  `<required-minutes>`. This runbook sets no minimum session time and publishes no measured duration
  for its reads, so set the requirement as step 1 of
  [Check session headroom before long operations](operator-access.md#check-session-headroom-before-long-operations)
  describes. After a destroy, the census's repeat bound alone, 20 attempts 30 seconds apart, spans
  about ten minutes.
- [ ] **Read access** to Budgets, Cost Explorer, the Price List API, CloudWatch metrics, and the
  EC2, Elastic Load Balancing, Auto Scaling, EKS, RDS, CloudWatch Logs, SNS, IAM, Secrets Manager
  and Route 53 list and describe calls. For a cleanup only, permission to delete that one object's
  class.
- [ ] **Tools.** AWS CLI v2 (the minimum version was never recorded), `bash` and `jq`.
- [ ] **Cost Explorer enabled** on the account, a one-time console action outside the repositories
  ([Background prerequisites](#background-prerequisites)).
- [ ] **The budget** `cloud-platform-reference` with its five notifications, created outside
  Terraform. Its full shape is in [Background prerequisites](#background-prerequisites).
- [ ] **The six cost-allocation tag keys activated**
  ([Background prerequisites](#background-prerequisites)). On a new account a key can be activated
  only after a resource carries it; the ordering consequence is stated there.
- [ ] **A private records location** that no repository tracks or publishes, for the dated budget
  and CPU-credit lines, the weekly review records, census outputs and cleanup records. The location
  outside every Git working tree that [evidence-handling.md](evidence-handling.md) describes has not
  yet been practised.
- [ ] **An owner** who authorizes each cleanup and each resume after a HOLD, and who holds the
  ADR-0013 budget levels.

**Rules for every procedure.**

- AWS CLI calls are outside Terraform, so nothing else checks the account. A census or a budget read
  in the wrong account prints plausible values, and only the `ACCOUNT_MATCH=PASS` verdict shows
  which account answered. Retain that verdict with every record.
- Every recorded read ran on the administrator permission set, and so did the 2026-09-11 cleanup.
  The read-only permission set is unexercised for these reads.
- Regional commands pass `--region us-east-1`. Budgets, Cost Explorer, IAM and Route 53 are global.
- A command that needs the account number reads it from the session into a shell variable and never
  prints it. `--query` projections keep account numbers, ARNs and email addresses out of successful
  output.
- Error output is not projected. An AWS error can carry the caller's ARN and the account number, so
  error text is read on screen and never copied into evidence.
- The exported shell is `bash`; the census and the helpers rely on its word splitting and `read -a`.
- STOP and HOLD halt the work where they occur. Where no resume procedure is written, work stays
  stopped until a reviewed decision is taken under explicit approval
  ([When to stop](README.md#when-to-stop)).
- Every figure is absolute USD.

## Procedures

### Read back the budget and its alert states

**Validation:** AWS-VALIDATED (2026-09-24) · **Published command form:** not executed as written

**What this does.** It confirms that the monthly budget ADR-0013 requires still exists with its five
alerts. It also reads month-to-date spend, the month-end forecast and each alert's state, without a
billable Cost Explorer request.

Run it before any billable change and in every weekly review. The budget only notifies; it never
prevents spend.

**Before you start.**

- [ ] The exported shell, with `ACCOUNT_MATCH=PASS` ([Before you start](#before-you-start)).
- [ ] The budget `cloud-platform-reference` exists with its five notifications
  ([Background prerequisites](#background-prerequisites)). No creation procedure is published
  ([Not yet exercised](#not-yet-exercised)).

**Safety and authority.** Read-only. No approval is needed. Budgets reads only, no Cost Explorer
request. Never print or keep the account number, a subscriber address or the unprojected budget
response.

**Steps.**

1. Read the account number into a variable without printing it.

   ```
   account=$(aws sts get-caller-identity --query Account --output text)
   ```

2. Read the budget. The raw response carries the account number in its cost filter, so the
   projection leaves the filter out.

   ```
   aws budgets describe-budgets --account-id "$account" \
     --query 'Budgets[?BudgetName==`"cloud-platform-reference"`].[BudgetName, BudgetType, TimeUnit, BudgetLimit.Amount, BudgetLimit.Unit, CalculatedSpend.ActualSpend.Amount, CalculatedSpend.ForecastedSpend.Amount]' \
     --output text
   ```

3. Read the notifications and their states.

   ```
   aws budgets describe-notifications-for-budget --account-id "$account" --budget-name cloud-platform-reference
   ```

4. Count each notification's subscribers. Addresses are never printed.

   ```
   for n in ACTUAL:100 ACTUAL:150 ACTUAL:200 FORECASTED:150 FORECASTED:200; do
     printf '%s subscribers: ' "$n"
     aws budgets describe-subscribers-for-notification --account-id "$account" \
       --budget-name cloud-platform-reference \
       --notification "NotificationType=${n%%:*},ComparisonOperator=GREATER_THAN,Threshold=${n##*:},ThresholdType=ABSOLUTE_VALUE" \
       --query 'length(Subscribers)' --output text
   done
   ```

5. Optionally, read earlier months' actual spend from the same budget. Period starts print in the
   workstation's time zone, so a month can appear to start on the last day of the month before.

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

**Expected result.** This is the full measured check:

- step 2 returns exactly one row: `cloud-platform-reference`, `COST`, `MONTHLY`, `200.0`, `USD`,
  then the month-to-date actual and the forecast;
- step 3 returns exactly five notifications, ACTUAL 100, ACTUAL 150, ACTUAL 200, FORECASTED 150 and
  FORECASTED 200, each `GREATER_THAN` with `ABSOLUTE_VALUE`, each with a `NotificationState` of `OK`
  or `ALARM`;
- step 4 returns at least 1 for every notification.

Last measured 2026-09-24: every criterion met, month-to-date actual 3.938 USD, forecast 4.216 USD,
all five states `OK`.

**PASS when.**

- [ ] Every read succeeded and returned output.
- [ ] Step 2 returned exactly one row with `cloud-platform-reference`, `COST`, `MONTHLY`, `200.0`
  and `USD`.
- [ ] Step 3 returned exactly the five notifications, each `GREATER_THAN` with `ABSOLUTE_VALUE`, each
  in `OK` or `ALARM`. This checks the budget's shape; an `ALARM` is still a STOP below.
- [ ] Step 4 printed at least 1 for every notification.

**STOP if.**

- A read errors or returns nothing. That is not a pass.
- The budget is missing, a notification is missing or changed, or a notification has no subscriber.
  This is the ADR-0013 stop condition for an absent budget alert: no billable resource is created.
- A notification is in `ALARM`: go to
  [Respond to the 100, 150 and 200 USD levels](#respond-to-the-100-150-and-200-usd-levels). Two
  cases differ. Inside a weekly review, record the states in its entry 2, complete the record, and
  then take the level to that procedure. If the level already has an owner decision recorded this
  month, record the `ALARM` with a reference to that decision, and continue only as that decision
  allows.

**If it fails.** Read any error on screen and never copy it into evidence. The procedure for
resuming from an absent budget alert is not written, and no procedure for creating the budget is
published ([Not yet exercised](#not-yet-exercised)). Work stays stopped until the owner decides.

**Evidence to keep.** The UTC time, the `ACCOUNT_MATCH` verdict, a pass or fail per criterion, the
two spend figures and the five states. Never the account number, a subscriber address or the
unprojected budget response.

**Next step.** If any notification is in `ALARM`, do not continue to the price re-check: go to
[Respond to the 100, 150 and 200 USD levels](#respond-to-the-100-150-and-200-usd-levels). For a
billable change, go on to [Re-check prices before billable work](#re-check-prices-before-billable-work)
only when all five are `OK`, or when an owner decision recorded this month for each `ALARM` level
allows the change. This read runs again
before the next billable change, and in the first weekly review on 2026-10-01.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-24) |
| Published form | not executed as written (step 3 is the executed form; step 2 adds a projection to the executed read so that no account number prints; step 4 hard-codes the five notifications in shorthand, where the executed read passed each notification as step 3 returned it, and adds a count projection; step 5 is derived from a 2026-09-24 read whose command line was not retained) |
| Evidence basis | [ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md#decision); retained private evidence of the 2026-09-10 budget and notification reads, the 2026-09-24 read-only check immediately before the datastore apply (budget shape, a pass on every notification having at least one subscriber, alert states) and the 2026-09-24 cost reads |
| Authority | None (read-only) |
| Cost | None recorded; Budgets reads only, no Cost Explorer request |

**Known limitations.**

- Other budget attributes (cost filter, cost types, time period) are not part of the measured check.
- Delivery of a notification to its subscribers has never been tested. An `ALARM` state is not
  evidence that a message arrived.
- The forecast was observed on 2026-08-08 to be unreliable on this account's short and irregular
  history, so the FORECASTED alerts may not fire. The ACTUAL alerts do not depend on it.
- Budget spend figures lag billing; AWS refreshes them up to three times a day.
- The budget is a billing object created outside Terraform. ADR-0013 makes the six tags mandatory on
  every resource. By an owner decision recorded when the budget was created on 2026-08-06, the
  budget carries none of them. That exemption is a recorded owner decision beside ADR-0013, not part
  of it, and the budget's tags have not been read back since.

### Re-check prices before billable work

**Validation:** AWS-VALIDATED (2026-09-24) · **Published command form:** not executed as written

**What this does.** It reads the current us-east-1 on-demand price of each rate a change will bill
from the AWS Price List API, and compares it with the price table in this procedure. ADR-0013
requires the estimate to be re-checked immediately before the first billable resource exists. This
runbook applies the same re-check before each billable change. ADR-0013 also treats a material
change in the EKS control plane, NAT gateway or public IPv4 rate as a revisit trigger.

A re-check states what AWS charges, not what the account was billed.

**Before you start.**

- [ ] The rates the change will bill, identified from the root's README and its reviewed plan
  ([Review the saved plan](terraform-operations.md#review-the-saved-plan)).
- [ ] `jq` installed, and the exported shell ([Before you start](#before-you-start)).

**Safety and authority.** Read-only; Price List API reads. No approval is needed to read. A value
that differs, or a rate missing from the table, needs a re-estimate and owner approval before the
billable change.

**Steps.**

1. Define the helper. It prints one line per price dimension: usage type, USD, unit and the start of
   the range the price applies from.

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

2. Read the rates the change bills. The lines below cover every rate in the table.

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

3. Compare each line whose usage type and range start both appear in the table with the table's
   value, numerically. The helper prints the Price List's ten-decimal strings, for example
   `0.0160000000` for 0.016. Ignore lines of a listed usage type at another range start, such as
   Route 53's `HostedZone` line from 25, and lines of usage types not in the table.

**Price table.** The prices actually re-checked, us-east-1, on-demand:

| Rate | Usage type | From | USD | Unit | Last re-checked |
|---|---|---|---|---|---|
| RDS `db.t4g.micro`, PostgreSQL, Single-AZ | `InstanceUsage:db.t4g.micro` | 0 | 0.016 | instance-hour | 2026-09-24 |
| RDS gp3 storage, PostgreSQL | `RDS:GP3-Storage` | 0 | 0.115 | GB-month | 2026-09-24 |
| RDS T4g CPU credits, PostgreSQL | `CPUCredits:db.t4g` | 0 | 0.075 | vCPU-hour | 2026-09-24 |
| RDS backup storage beyond the free allocation, PostgreSQL | `RDS:ChargedBackupUsage` | 0 | 0.095 | GB-month | 2026-09-24 |
| Secrets Manager secret | `USE1-AWSSecretsManager-Secrets` | 0 | 0.40 | secret per month | 2026-09-24 |
| Secrets Manager API requests | `USE1-AWSSecretsManagerAPIRequest` | 0 | 0.000005 | API request (0.05 USD per 10,000) | 2026-09-24 |
| Route 53 hosted zone, first 25 | `HostedZone` | 0 | 0.50 | zone per month | 2026-09-23 |
| EKS control plane | `USE1-AmazonEKS-Hours:perCluster` | 0 | 0.10 | cluster-hour | 2026-09-22 |
| EC2 `m6a.large`, Linux, shared tenancy | `BoxUsage:m6a.large` | 0 | 0.0864 | instance-hour | 2026-09-10 |
| NAT gateway | `NatGateway-Hours` | 0 | 0.045 | hour | 2026-09-10 |
| NAT gateway data processing | `NatGateway-Bytes` | 0 | 0.045 | GB | 2026-09-10 |
| Public IPv4 address in use | `USE1-PublicIPv4:InUseAddress` | 0 | 0.005 | address-hour | 2026-09-10 |
| EBS gp3 volume | `EBS:VolumeUsage.gp3` | 0 | 0.08 | GB-month | 2026-09-10 |

**Expected result.** Every rate the change bills is in the table, and the value read equals it.

**PASS when.**

- [ ] Every rate the change bills is in the table.
- [ ] Each of those rates returned a line with the expected usage type and range start.
- [ ] Each value equals the table's value, compared numerically.

**STOP if.** Stop before the billable change when:

- a value differs from the table;
- a rate the change bills is not in the table;
- a read errors or returns no line with the expected usage type and range start.

A hosted-zone build ([Build the zone on its own](public-dns-and-certificate.md#build-the-zone-on-its-own))
always meets the second condition. The table has the zone rate but not the Route 53 query rate,
0.40 USD per million queries in [Public DNS](../../terraform/foundation/README.md#public-dns), and
this procedure has never re-checked that rate. Its re-estimate and owner approval follow If it fails.

**If it fails.** Re-estimate and obtain owner approval before the billable change. This runbook has
no written re-estimation procedure. A changed EKS control plane, NAT gateway or public IPv4 rate
also triggers the ADR-0013 revisit.

**Evidence to keep.** The UTC time, each rate as read, and the comparison verdict.

**Next step.** The reviewed billable change, under its own approval. Run this re-check again before
the next billable change; a runtime window re-checks the runtime rates.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-24) |
| Published form | not executed as written (the filters are those of the executed Price List reads; the helper, its `jq` parsing and the usage-type filters on three datastore rates are derived) |
| Evidence basis | [ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md#decision) (cost estimates are provisional); retained private evidence of the 2026-09-10 runtime-rate reads, the 2026-09-22 EKS control-plane re-check immediately before the zero-node observation window, the 2026-09-22 and 2026-09-24 datastore, Secrets Manager and Route 53 reads, the 2026-09-23 Route 53 re-check immediately before the hosted-zone apply, and the 2026-09-24 comparison immediately before the datastore apply |
| Authority | None (read-only) |
| Cost | None recorded; Price List API reads |

**Known limitations.** Rates, not spend: a re-check states what AWS charges, not what the account was
billed. Rates outside the table, for example the Route 53 query rate, the load balancer, registry
storage and S3 storage, have never been re-checked through this procedure (see
[Not yet exercised](#not-yet-exercised)).
The runtime rates other than the EKS control plane were last re-checked before a window on
2026-09-10.

### Read back the cost-allocation tags

**Validation:** AWS-VALIDATED (2026-09-10) · **Published command form:** executed as written

**What this does.** ADR-0013 makes six tags mandatory so that cost can be attributed. Billing groups
spend by a tag only while that tag is an active cost-allocation tag. This read confirms that all six
still are.

Active keys show that the billing setting is on. They do not show that any cost record carries the
tags.

**Before you start.**

- [ ] The six tags were activated once, and Cost Explorer is enabled
  ([Background prerequisites](#background-prerequisites)).
- [ ] The exported shell ([Before you start](#before-you-start)).

**Safety and authority.** Read-only; no approval is needed. Billable: up to USD 0.01, one Cost
Explorer API request.

**Steps.**

1. List the active cost-allocation tags.

   ```
   aws ce list-cost-allocation-tags --status Active
   ```

**Expected result.** The `UserDefined` entries are exactly these six, each `Active`: `Project`,
`Environment`, `Component`, `Lifecycle`, `Owner` and `ManagedBy`. An `AWSGenerated` entry that the
list also returns is recorded and does not fail the check. Last measured 2026-09-10: exactly these
six, each last updated at their 2026-08-21 activation, and no `AWSGenerated` entry.

**PASS when.**

- [ ] The set of `UserDefined` keys is exactly the six, each `Active`. Compare the set of keys, not
  the count: a seventh active user-defined key, or any of the six missing, fails the check.

**STOP if.** A key is missing or inactive. Cost attribution then cannot be demonstrated, which is an
ADR-0013 stop condition.

**If it fails.** No reactivation procedure is published, and no activation command either
([Not yet exercised](#not-yet-exercised)). No procedure is written for a seventh active key. Work
stays stopped until the owner decides.

**Evidence to keep.** The UTC time and the listed keys with their status and type.

**Next step.** When the budget figures cannot explain spend,
[Break spend down with Cost Explorer](#break-spend-down-with-cost-explorer). Otherwise continue the
[normal path](#normal-path).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-10) |
| Published form | executed as written |
| Evidence basis | [ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md#decision) (tagging and attribution); retained private evidence of two 2026-09-10 reads with raw output |
| Authority | None (read-only) |
| Cost | Up to USD 0.01 (one Cost Explorer API request) |

**Known limitations.** Active keys show that the billing setting is on. They do not show that any
cost record carries the tags. Attribution by tag has not been demonstrated end to end (see
[Break spend down with Cost Explorer](#break-spend-down-with-cost-explorer)).

### Break spend down with Cost Explorer

**Validation:** AWS-VALIDATED (2026-09-10) for step 1; AWS-VALIDATED (2026-09-12) for step 2 · **Published command form:** not executed as written

**What this does.** It breaks spend down by service when the budget figures cannot answer the
question, as in a written cost explanation, an unexplained-spend check, or the weekly review's
unexplained-spend entry. Use it only then, because each request bills. Step 2 optionally reads the spend that carries the project tag.

Cost Explorer lags by hours. A missing line is not evidence of zero cost, and the current month's
figures are estimates.

**Before you start.**

- [ ] Cost Explorer is enabled ([Background prerequisites](#background-prerequisites)).
- [ ] The exported shell ([Before you start](#before-you-start)).
- [ ] The period. `<first-day>` and `<day-after-last-day>` are UTC dates in `YYYY-MM-DD` form; `End`
  is exclusive. The executed read used `Start=2026-09-01,End=2026-09-11`. For a weekly review, use
  the review's period ([Record the weekly ADR-0013 review](#record-the-weekly-adr-0013-review)).
- [ ] The expected persistent set, to map each line to
  ([Background prerequisites](#background-prerequisites)).

**Safety and authority.** Read-only; no approval is needed. Billable: USD 0.01 per Cost Explorer API
request.

**Steps.**

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

2. Optionally, read the spend carrying the project tag for the same period.

   ```
   aws ce get-cost-and-usage --time-period Start=<first-day>,End=<day-after-last-day> \
     --granularity MONTHLY --metrics UnblendedCost \
     --filter '{"Tags":{"Key":"Project","Values":["cloud-platform-reference"]}}' \
     --query 'ResultsByTime[].[TimePeriod.Start, Estimated, Total.UnblendedCost.Amount]' --output text
   ```

**Expected result.** Every non-zero service line maps to a known persistent foundation (a resource
kept on purpose, such as the registry) or to an approved window. On 2026-09-10 every non-zero line
mapped to a retained foundation (Secrets Manager, the registry, S3) or to tax.

**PASS when.**

- [ ] Each non-zero line is mapped to a resource.
- [ ] Zero-amount lines are recorded, not treated as spend.

**STOP if.** A non-zero line maps to nothing. That is unexplained spend, an ADR-0013 stop condition:
further billable work holds until it is explained.

**If it fails.** The investigation and resume procedure is not written. Work stays stopped until the
owner decides.

**Evidence to keep.** The UTC time, the period, the `Estimated` flag and each line with its mapping.
Never the account number.

**Next step.** Return to the procedure that asked for the breakdown: the
[weekly review](#record-the-weekly-adr-0013-review) or a
[budget-level response](#respond-to-the-100-150-and-200-usd-levels).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-10) for step 1; AWS-VALIDATED (2026-09-12) for step 2, one read whose value was retained and whose raw output was not |
| Published form | not executed as written (the executed read passed the account number literally in its filter; here the number comes from the session, and a projection is added) |
| Evidence basis | [ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md#decision) (unexplained spend; estimate against actual); retained private evidence of the 2026-09-10 account-scoped reads by service, with raw output, and a retained private record of the 2026-09-12 project-tag read's value, without raw output |
| Authority | None (read-only) |
| Cost | USD 0.01 per Cost Explorer API request |

**Known limitations.**

- Filter to the project account. In an AWS Organizations management account the unfiltered view
  covers every member account.
- Cost Explorer lags by hours, so a missing line is not evidence of zero cost, and the current
  month's figures are estimates.
- The project-tag form in step 2 ran once, on 2026-09-12; its value was retained, its raw output was
  not. Attribution by tag has not been demonstrated end to end.

### Check the datastore CPU credits

**Validation:** AWS-VALIDATED (2026-09-24) for one 300-second read; DESIGNED-NOT-EXECUTED (never) for the recurring cadence and the 3,600-second form · **Published command form:** not executed as written

**What this does.** The datastore instance runs in unlimited CPU-credit mode. In that mode a CPU
burst can draw surplus credits, and surplus is billed once it exceeds what the instance can earn in
24 hours, or when the instance stops or is deleted. What that bills, and the stress-case
figure, are in the [dev-datastore README](../../terraform/dev-datastore/README.md#decommission). No
alarm exists. This read-only check is how a runaway is detected between budget alerts.

Run it at the start of each operating session while the instance exists, and in every weekly
review. This cadence is designed and has not yet been exercised.

> **Warning:** This check detects; it does not limit spend. It does not cap spend, erase incurred
> cost or change the 200 USD ceiling. Detection takes up to the check interval, plus the five-minute
> metric period and an undocumented publishing delay.

**Before you start.**

- [ ] The instance exists.
- [ ] The exported shell ([Before you start](#before-you-start)).
- [ ] `<previous-check-utc>`: the UTC time of the previous check in ISO 8601, for example
  `2026-09-24T18:48:40Z`, as that check's dated line in the private records location
  ([Before you start](#before-you-start)) gives it. For the first check after the instance is created, start at or before its
  creation time, as the executed first read did.

**Safety and authority.** Read-only; no approval is needed. `GetMetricStatistics` requests within
the CloudWatch free request allowance.

**Steps.**

1. Set the span and the period. Use 300 seconds for a span up to five days and 3,600 seconds for a
   longer one; one call returns at most 1,440 datapoints.

   ```
   since=<previous-check-utc>
   now=$(date -u +%FT%TZ)
   period=300
   ```

2. Read the four metrics. `TZ=UTC` keeps the timestamps in UTC; the first executed read, run without
   it, printed them in the workstation's time zone.

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

**Expected result.** At an idle instance: `CPUSurplusCreditsCharged` 0 in every period since the
last check, and `CPUSurplusCreditBalance` 0 in the latest periods. A third outcome is neither PASS
nor STOP: a surplus balance above 0 with a documented cause, and nothing charged, is recorded as an
explained review trigger with its cause, as the one executed read was (Engineering notes). The
next check must show a surplus balance of 0 in its latest periods and nothing charged since.

**PASS when.**

- [ ] Every metric printed lines. A metric that prints no lines returned no datapoints. That is not
  a zero: check the span and the identifier, and allow for the five-minute metric period.
- [ ] `CPUSurplusCreditsCharged` is 0 in every period since the last check.
- [ ] `CPUSurplusCreditBalance` is 0 in the latest periods.

**STOP if.**

- Any `CPUSurplusCreditsCharged` above 0, or a surplus balance above 0 without a documented cause,
  is a REVIEW and puts further optional billable work on HOLD until it is explained. A documented
  cause is, for example, the start-up burst after a create or a start. The HOLD applies to optional
  billable work; it is not a shutdown of the instance.

**Investigate when.** Investigate at that session when the surplus balance is above 0 and rising
across two checks, or when CPU averages above 10 percent over 24 hours. The 10 percent figure is the
documented per-vCPU baseline of the EC2 `t4g.micro`; AWS does not document the RDS figure, so
applying it here is an inference. This procedure prints period averages only: no 24-hour average
has been computed, and deriving one from the period averages is unexercised.

**If it fails.** UNEXERCISED. The response is owner-controlled: find the CPU consumer, and end any
runtime window driving it. Stopping or decommissioning the instance are not exercised procedures
(see [dev-datastore.md](dev-datastore.md)).

> **Warning:** Stopping ends instance-hours but bills any outstanding surplus and loses earned
> credits, and AWS restarts a stopped instance after seven days.

**Evidence to keep.** One dated private line per check: UTC read time, the `ACCOUNT_MATCH` verdict,
period and span, maximum surplus balance, sum charged, minimum credit balance, average and maximum
CPU, and the verdict.

**Next step.** The next operating session, and at the latest the first weekly review on 2026-10-01.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-24) for one read at a 300-second period; DESIGNED-NOT-EXECUTED (never) for the recurring cadence and the 3,600-second form |
| Published form | not executed as written (the executed read's command lines were not retained; the metrics and statistics follow the reviewed design of the check, which reads at a 3,600-second period and allows 300 seconds for spans up to five days; the 300-second default follows the executed first read, and `TZ=UTC` follows its confirming read) |
| Evidence basis | [dev-datastore README](../../terraform/dev-datastore/README.md#decommission) (cost estimate, unlimited CPU-credit mode); retained private evidence of the 2026-09-24 first read and its confirming read, and of the reviewed cost decision that designed the check |
| Authority | None (read-only) |
| Cost | None recorded; `GetMetricStatistics` requests within the CloudWatch free request allowance |

**The one executed read.** It showed a surplus balance above 0 and falling, drawn during the CPU
burst while the instance was created and took its first backup, because T4g instances start with no
launch credits. Nothing was charged, and it was recorded as an explained review trigger.

**Known limitations.** The check shortens detection; it does not cap spend, erase incurred cost or
change the 200 USD ceiling. Detection takes up to the check interval, plus the five-minute metric
period and an undocumented publishing delay. Surplus is billed once it exceeds what the instance can
earn in 24 hours, or when the instance stops or is deleted. The README's 0.15 USD an hour figure is
a stress case, not a projection.

### Record the weekly ADR-0013 review

**Validation:** DESIGNED-NOT-EXECUTED (never; first due 2026-10-01) for the record fields; UNEXERCISED (never) for the step 4 commands · **Published command form:** not executed as written

**What this does.** ADR-0013 requires a weekly cost and billing review. While the datastore exists,
this record is where the week's cost, residue and datastore checks meet and a decision is taken:
continue, REVIEW or HOLD.

No review record exists for any week so far. 2026-10-01 is the first review due under this
procedure, not the first review ADR-0013 required.

**Before you start.**

- [ ] This week's results from
  [Read back the budget and its alert states](#read-back-the-budget-and-its-alert-states),
  [Run the orphan census](#run-the-orphan-census) and
  [Check the datastore CPU credits](#check-the-datastore-cpu-credits).
- [ ] For any window that week, the environment-hour ledger
  ([Background prerequisites](#background-prerequisites)).
- [ ] The private records location ([Before you start](#before-you-start)).
- [ ] The owner, who takes the decision.

**Safety and authority.** Read-only for the reads. The continue, REVIEW or HOLD decision is the
owner's. Billable only when step 6 needs a Cost Explorer request: up to USD 0.01 per request.

**Steps.** Write one dated private record per review, identifiers redacted as
[evidence-handling.md](evidence-handling.md) describes, with the entries below. The review's period
is the time since the previous review record; the first review's period starts when the instance
was created. No published rule makes the review a campaign: its record goes in the private records
location ([Before you start](#before-you-start)), not into a sealed evidence set. Keep each entry
to what the linked procedure's Evidence to keep names, and redact any other identifier before it is
written ([Redact at capture](evidence-handling.md#redact-at-capture)).

1. Review time (UTC) and reviewer.
2. From [Read back the budget and its alert states](#read-back-the-budget-and-its-alert-states):
   month-to-date actual, month-end forecast, the five alert states, and the ADR-0013 level reached
   or projected: none, target, review threshold or ceiling. A forecast the read does not return is
   recorded as absent, never as 0. When the period crosses the start of a month, also run that
   procedure's step 5 and record the previous month's actual. No numeric rule defines approaching
   the 100 USD target, and no projection method is published: state what the projection rests on,
   such as the forecast, which may be unreliable, or a window estimate. An `ALARM` is recorded here
   and taken to its level's response once the record is complete.
3. From [Run the orphan census](#run-the-orphan-census): every runtime class 0 outside an approved
   window, and the datastore exception classes as expected.
4. The persistent set: the instance's status, the secrets (total and scheduled for deletion), the
   hosted zones (total and private), and a dated listing of manual DB snapshots, which tracks the
   final-snapshot retention rule in the
   [dev-datastore README](../../terraform/dev-datastore/README.md#decommission).

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

5. From [Check the datastore CPU credits](#check-the-datastore-cpu-credits): the week's maximum
   surplus balance, sum charged, and average and maximum CPU. Take them from the dated lines of
   every check in the period, the check run for this review included: the largest maximum surplus
   balance, the total of the sums charged and the largest maximum CPU. No method for combining
   period averages into one figure is published (that procedure's Investigate when); record how the
   average was derived. If no check ran since the previous review, this review's check spans more
   than five days and needs the 3,600-second form, which has never run.
6. Environment-hour reconciliation against the ledger for any window that week (see
   [Background prerequisites](#background-prerequisites); no reconciliation procedure is
   published), and unexplained spend: none, or the explanation, using
   [Break spend down with Cost Explorer](#break-spend-down-with-cost-explorer) when the budget
   figures cannot explain it. This runbook states no expected monthly cost for the whole persistent
   set, and registry and S3 storage have no rate in the price table, so record none only when every
   part of the spend maps to a known resource or an approved window.
7. The decision, continue, REVIEW or HOLD, and why.

**Expected result.** The first record under this procedure exists by 2026-10-01. Entry 4 expects:
instance `available`; 4 secrets, the Dev network's two entries and the datastore's two containers,
none scheduled for deletion; 1 hosted zone, not private; and no manual snapshot, because the final
snapshot that the retention rule covers does not exist until a decommission deletes the instance.
Last measured values for the persistent set, 2026-09-24: instance `available`; 4 secrets, none
scheduled for deletion; 1 hosted zone, not private; no manual snapshot.

**PASS when.**

- [ ] One dated private record holds all seven entries, with identifiers redacted.
- [ ] The record states the decision and why.

**STOP if.** A review is missed. That puts further optional billable work on HOLD until the review
is completed and the datastore's continued retention is explicitly reconsidered. A review is missed
when no record exists by its due date; no grace period is set. This HOLD starts with the first
review due under this procedure, on 2026-10-01. The earlier weeks that ADR-0013 required and no
record covers are an open gap (Engineering notes): whether they put optional billable work on HOLD
is not settled in any published text, and that is the owner's decision.

**If it fails.** Route each finding to the procedure that owns it: a level reached or projected to
[Respond to the 100, 150 and 200 USD levels](#respond-to-the-100-150-and-200-usd-levels); a census
STOP to [Run the orphan census](#run-the-orphan-census); unexplained spend to
[Break spend down with Cost Explorer](#break-spend-down-with-cost-explorer); a CPU-credit REVIEW to
[Check the datastore CPU credits](#check-the-datastore-cpu-credits). Environment-hour reconciliation
has no published procedure. A persistent-set value other than expected has no procedure either: it
is taken to the owner's decision in entry 7. A secret scheduled for deletion is also checked with
[Verify the secret containers without reading a value](dev-datastore.md#verify-the-secret-containers-without-reading-a-value)
or [Read back the two Secrets Manager entries](dev-network.md#read-back-the-two-secrets-manager-entries),
whichever holds it, and a resource nothing owns goes to the investigation in
[Clean up an orphan](#clean-up-an-orphan).

**Evidence to keep.** The dated private record itself.

**Next step.** The first review, due 2026-10-01.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | DESIGNED-NOT-EXECUTED (never; first due 2026-10-01) for the record fields; UNEXERCISED (never) for the step 4 commands |
| Published form | not executed as written (never run; the record fields follow the reviewed cost decision; the step 4 commands are derived and unreviewed, and the 2026-09-24 persistent-set values below come from reads whose command lines were not retained) |
| Evidence basis | [ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md#decision) (weekly cost and billing review); no execution evidence |
| Authority | None for the reads; the continue, REVIEW or HOLD decision is the owner's |
| Cost | Up to USD 0.01 per Cost Explorer request when step 6 needs one; otherwise none recorded |

The 2026-09-24 persistent-set values that the Published form row refers to are the last measured
values under Expected result.

**Known limitations.**

- ADR-0013 has required a weekly cost and billing review since it was accepted on 2026-08-01. No
  review record exists for any week so far. 2026-10-01 is the first review due under this procedure,
  not the first review ADR-0013 required.
- The record covers cost and billing, residue and the datastore. ADR-0013's other weekly duties have
  no reviewed procedure yet (see [Not yet exercised](#not-yet-exercised)).

### Respond to the 100, 150 and 200 USD levels

**Validation:** DESIGNED-NOT-EXECUTED (never) for the 150 and 200 USD responses; UNEXERCISED (never) for the 100 USD target review · **Published command form:** not executed as written

**What this does.** It carries out what ADR-0013 requires when monthly spend reaches, or is
projected to reach, one of its three levels: the 100 USD target, the 150 USD review threshold and the
200 USD ceiling. What each level requires, halts and permits, and how work resumes, is in
[ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md#decision); the table below maps
each level to the procedures in this runbook.

> **Warning:** Nothing responds automatically. No automated response exists, and the budget alerts
> only notify. No level has ever been reached, and alert delivery has never been tested. No alert
> fires while spend approaches 100 USD: approaching the target is detected only by the weekly review
> or a window estimate.

**Before you start.**

- [ ] A trigger: a notification in `ALARM` at the budget read-back, a received alert, or a weekly
  review or window estimate that projects the month to reach or pass a level.
- [ ] The owner, who decides every resume.

**Safety and authority.** Owner-authorized. The owner decides every resume, and each destructive
step needs its own explicit owner authorization. Billable: USD 0.01 per Cost Explorer request when a
row needs one; none for the budget reads and the census. Destroying what is not needed reduces spend.

**Steps.**

1. Run [Read back the budget and its alert states](#read-back-the-budget-and-its-alert-states) and
   record the figures and states.
2. Identify the highest level reached or projected.
3. Carry out that level's row, and the rest of that level's ADR-0013 list, which has no procedure
   here.

   > **Warning:** Each destructive step needs its own explicit owner authorization. Evidence that
   > must survive a destroy is exported before it and read back after it
   > ([evidence-handling.md](evidence-handling.md)). Runtime windows and their teardown are
   > summarized in [Runtime Validation](../validation/runtime-validation.md#windows).
   > Decommissioning the datastore has not been exercised ([dev-datastore.md](dev-datastore.md)).

4. Record the decision and the evidence it rests on.

| Level | Trigger | Procedures in this runbook | Status |
|---|---|---|---|
| 100 USD target | ACTUAL 100 (fires only once spend exceeds 100 USD), or a weekly review or window estimate approaching it | [Break spend down with Cost Explorer](#break-spend-down-with-cost-explorer); [Run the orphan census](#run-the-orphan-census) to confirm the last teardown; environment-hour reconciliation (no procedure) | UNEXERCISED |
| 150 USD review threshold | ACTUAL 150 or FORECASTED 150, or a projection past 150 USD | [Break spend down with Cost Explorer](#break-spend-down-with-cost-explorer) for the written explanation; [Run the orphan census](#run-the-orphan-census); environment-hour reconciliation (no procedure) | DESIGNED-NOT-EXECUTED |
| 200 USD ceiling | ACTUAL 200 or FORECASTED 200, or a projection at or above 200 USD | [Run the orphan census](#run-the-orphan-census); [Break spend down with Cost Explorer](#break-spend-down-with-cost-explorer) for unexplained spend; [Clean up an orphan](#clean-up-an-orphan) for what the census finds | DESIGNED-NOT-EXECUTED |

**Expected result.** No level has ever been reached, so no response has been observed.

**PASS when.**

- [ ] The budget figures and states are recorded.
- [ ] The highest level reached or projected is identified, and its row is carried out.
- [ ] The decision and the evidence it rests on are recorded.

**STOP if.** The 150 and 200 USD levels carry ADR-0013 stop conditions; what halts and what may
continue is stated there.

**If it fails.** No resume procedure is published for any ADR-0013 stop condition
([Not yet exercised](#not-yet-exercised)). The owner decides every resume. Environment-hour
reconciliation has no procedure.

**Evidence to keep.** The budget figures and states, the written cost explanation where one is
required, the census output, and a reference to the owner decision.

**Next step.** Work resumes only on the owner's decision.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | DESIGNED-NOT-EXECUTED (never) for the 150 and 200 USD responses; UNEXERCISED (never) for the 100 USD target review |
| Published form | not executed as written (never triggered; derived from ADR-0013 and the recorded budget policy) |
| Evidence basis | [ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md#decision) (budget policy, cost response, stop conditions); no execution evidence |
| Authority | The owner decides every resume; each destructive step needs its own explicit owner authorization |
| Cost | USD 0.01 per Cost Explorer request when a row needs one; none for the budget reads and the census. Destroying what is not needed reduces spend. |

**Known limitations.**

- No level has ever been reached, and alert delivery has never been tested. A projection rests on
  estimated window-hours. No automated response exists.
- No alert fires while spend approaches 100 USD. ACTUAL 100 fires only once spend exceeds it, and by
  an owner decision there is no FORECASTED 100 notification. Approaching the target is detected only
  by the weekly review or a window estimate.

### Run the orphan census

**Validation:** AWS-VALIDATED (2026-09-22) for the runtime-residue classes without a datastore instance; OFFLINE-VALIDATED (2026-09-22) for the datastore exception classes with a live instance · **Published command form:** not executed as written

**What this does.** It shows that no runtime residue remains: no resource in the census's runtime
classes exists outside an approved runtime window. It counts the persistent datastore in separate
exception classes, so that it is never read as residue.

Run it after every teardown, in every weekly review and at the 150 and 200 USD levels.

The census is fail-closed: a class counts as absent only when its read succeeded and printed 0.

> **Warning:** In the wrong account the census prints plausible zeros. Only the `ACCOUNT_MATCH=PASS`
> verdict shows which account answered.

**Before you start.**

- [ ] The exported shell with `ACCOUNT_MATCH=PASS` ([Before you start](#before-you-start)).
- [ ] No apply or destroy in progress.
- [ ] After a window, that window's pre-open census, for comparison.

**Safety and authority.** Read-only list and describe calls. No approval is needed. No cost.

**Steps.**

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

2. Find the datastore security group by its tags. An empty result is a valid zero here; a failed
   read is not.

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

4. After a destroy, repeat the whole census, steps 2 and 3 together in the same shell, up to 20
   times, 30 seconds apart, the bound the executed teardown used, until it settles: one complete census with every runtime class at 0. A resource
   still deleting is not absent. On 2026-09-22 the census settled on its first attempt, so the repeat
   path has never been needed.
5. Compare the result with the table below and, after a window, with that window's pre-open census.

**Expected result.** The fail-closed rule: a class is absent only when its read succeeded and
printed 0. An error, empty output or anything other than a number is `UNKNOWN`, and `UNKNOWN` is
never absent. A census with any `UNKNOWN` class is incomplete and proves nothing.

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
| `DATASTORE_ENI` (exception class) | 1 expected while the instance exists; this classification has never run against a live instance |

**PASS when.**

- [ ] No class prints `UNKNOWN`.
- [ ] Once the census has settled, every runtime class is 0, and no `POD_IDENTITY_ASSOCIATIONS` or
  `EKS_ADDONS` line prints.
- [ ] Each exception class reads as the table expects.
- [ ] After a window, the result has been compared with that window's pre-open census.

**STOP if.**

- Any `UNKNOWN`: the census is incomplete. HOLD.
- Any runtime class above 0 once the census has settled, or when the bound is reached with a class
  still above 0: an orphaned resource, an ADR-0013 stop condition. Investigate before further
  billable work, and remove it only through [Clean up an orphan](#clean-up-an-orphan).
- `DATASTORE_SG` other than 1 while the datastore root is applied: the datastore exception does not
  apply. HOLD and review.
- `RDS_DATASTORE` other than 1 while the instance should exist, or `DATASTORE_ENI` other than 1 with
  the instance present: HOLD and review. The first live run records the observed value as
  evidence. It does not change the expected 1, and a value other than 1 is a HOLD on that run too.
- `RDS_UNEXPECTED` above 0: an instance nobody reviewed, such as a restore target. HOLD.

**If it fails.**

- An `UNKNOWN` class: fix the cause (session, permission, region) and run the whole census again;
  never edit a value by hand. To find the cause, rerun the single failing query by hand without
  `2>/dev/null` and read the error on screen. Never copy the error text into evidence, because it
  can carry the caller's ARN and the account number.
- A non-zero class right after a Terraform destroy may be an incomplete destroy rather than an
  orphan. For the dev root, the expected post-teardown state and plan (21 retained addresses, 17 to
  add) are in
  [Confirm the retained and runtime split](dev-network.md#confirm-the-retained-and-runtime-split);
  plan mechanics are in [terraform-operations.md](terraform-operations.md).
- A confirmed orphan: [Clean up an orphan](#clean-up-an-orphan).
- An exception class that holds: no review procedure is written. Work stays stopped until the owner
  decides.

**Evidence to keep.** The census output (counts only), its UTC time, the `ACCOUNT_MATCH` verdict and,
after a window, the pre-open census it was compared with. A census after a window's teardown also
enters that window's final evidence set ([evidence-handling.md](evidence-handling.md#normal-path),
step 9).

**Next step.** For an orphan, [Clean up an orphan](#clean-up-an-orphan). The next gate is the first
census with the instance present, which records the first live exception values against the table;
at the latest in the first weekly review on 2026-10-01.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22) for the runtime-residue classes in an account without a datastore instance; OFFLINE-VALIDATED (2026-09-22) for the datastore exception classes with a live instance |
| Published form | not executed as written (the region-wide count queries follow the private census tool that produced the retained results; the count helpers, the SNS and IAM lines and the per-cluster EKS lines are rewritten, the VPC count is omitted, and the datastore security-group and network-interface steps are derived from the tool's classification rule; the offline three-state controls exercised the private tool, not the helpers published here) |
| Evidence basis | [ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md#decision) (orphan-resource scan after every teardown); [ADR-0018](../decisions/0018-define-the-public-entry-implementation-dns-and-certificate-model.md#decision) (named orphan-scan classes); [ADR-0019](../decisions/0019-bound-immutable-image-controls-for-aws-managed-runtime-images.md#evidence) (the 2026-09-22 zero-node observation window and its zero-residual teardown); [Runtime Validation](../validation/runtime-validation.md#what-has-been-demonstrated) (teardown and zero residual for the windows up to 2026-09-13); retained private evidence of the zero-node observation window's pre-teardown, post-teardown and final censuses, the match of the post-teardown census with the pre-open census, and a separate read outside the census of clusters and the cluster role; a 2026-09-22 census after a state-only reconciliation; and the offline controls for the classifier and the three-state rule |
| Authority | None (read-only) |
| Cost | None; read-only list and describe calls |

**What the runs showed.** On 2026-09-22, in the zero-node observation window, the pre-teardown
census showed one cluster with four add-ons; only the EKS, ENI, security-group, cluster-role and
add-on classes were above 0. The post-teardown and final censuses showed every runtime class at 0,
the post-teardown census matched the pre-open census exactly, and a separate read outside the census
confirmed no cluster and no cluster role. The datastore classes were then 1 security group, no
instance and no interface, because the instance did not yet exist. With an instance present, the
classification has passed offline controls only: the datastore interface recognised, a restore
target in another group counted as unexpected, a node interface in the datastore group not exempted,
two tagged groups treated as ambiguous, and an untagged group not exempted. The private tool's
three-state rule passed offline controls for an empty success, access denied, an expired token, a
null and a blank result.

**Known limitations.**

- us-east-1 only.
- ADR-0018 classes 1, 2 and 4 are counted directly; classes 3 and 5 only through the load-balancer
  and network-interface counts; classes 6 (controller-created record sets) and 7 (certificates left
  in `PENDING_VALIDATION`) are not counted.
- The SNS and IAM classes are name-scoped. Topics, subscriptions and roles under other names, such as
  the subscription removed on 2026-09-11, are not counted.
- Persistent billable classes (hosted zone and records, certificates, S3 buckets, registry
  repositories, Parameter Store entries, DB snapshots) are outside the census; the weekly review
  lists the ones that matter to cost.
- The census has never run while the datastore instance exists.

### Clean up an orphan

**Validation:** AWS-VALIDATED (2026-09-11) for one SNS subscription only · **Published command form:** not executed as written

**What this does.** It removes one resource that the census or an investigation found and that
nothing owns, without widening the change beyond that one object. An orphan is a resource that no
Terraform root declares or holds in state, that is neither a persistent foundation nor a datastore
exception class, and that belongs to no open window.

One object class has been removed, once: an email subscription left on a deleted SNS topic.

**Before you start.**

- [ ] A finding from [Run the orphan census](#run-the-orphan-census) or an investigation.
- [ ] The exported shell with `ACCOUNT_MATCH=PASS` ([Before you start](#before-you-start)), with
  permission to delete that one object's class.
- [ ] The owner, who must authorize this one object. `<topic-name>` in step 6 is the name of the
  subscription's topic.

**Safety and authority.** Mutating, destructive and owner-authorized. It needs explicit owner
authorization naming the one object. The authorization covers the named object only and is never a
general cleanup permission. No cost to run; removing a billing orphan ends its charge.

**Steps.**

1. Investigate read-only. Project only the fields needed, and never read an endpoint, value or
   address; for a subscription, leave its endpoint out. For a subscription, record whether it is
   still pending confirmation: a pending subscription is a HOLD before step 6.
2. Confirm it is an orphan and record each answer:
   - no Terraform root in this repository declares it;
   - no root's state holds it (see
     [Inspect state without writing it](terraform-operations.md#inspect-state-without-writing-it));
   - it is neither a persistent foundation nor a datastore exception class;
   - it belongs to no open window;
   - whether its parent still exists (on 2026-09-11 the subscription's topic returned `NotFound`).
3. Record the disposition: the class, why it is an orphan, and its cost effect.
4. Obtain explicit owner authorization bounded to that one object and to no other change.
5. Capture anything the object must still yield, as [evidence-handling.md](evidence-handling.md)
   describes.
6. Remove it with its own delete call, one object at a time. For the executed case, capture the
   subscription ARN into a variable from a listing projected to the one subscription, without
   printing it, and count what it holds.

   ```
   sub_arn=$(aws sns list-subscriptions --region us-east-1 \
     --query "Subscriptions[?ends_with(TopicArn, ':<topic-name>')].SubscriptionArn" --output text)
   wc -w <<< "$sub_arn"
   ```

   > **Warning:** Delete only when the variable holds exactly one ARN, and only under step 4's
   > authorization. `PendingConfirmation` in place of an ARN means an unconfirmed subscription,
   > which this call cannot remove (see Engineering notes). The count cannot tell them apart:
   > `PendingConfirmation` is one word, so it also prints 1. Rely on step 1's record of whether
   > the subscription is pending.

   ```
   aws sns unsubscribe --region us-east-1 --subscription-arn "$sub_arn"
   unset sub_arn
   ```

7. Read back absence with the object's own read. `NotFound` is absence; access denied or any other
   error is `UNKNOWN`. For the executed SNS case the read-back was a count of all subscriptions in
   the account, 0 after the removal; no read-back command is published here.
8. Run [the orphan census](#run-the-orphan-census) again.

**Expected result.** The removal exits 0, and the object's own read-back shows it absent; a census
class reads 0 only where one covers the object. On 2026-09-11 the read-back was a count of all
subscriptions in the account: 0 after the removal.

**PASS when.**

- [ ] The owner's authorization names this one object.
- [ ] The removal exited 0.
- [ ] The object's own read-back shows it absent (`NotFound` is absence; on 2026-09-11 a
  subscription count of 0).
- [ ] The census has run again.

**STOP if.**

- Terraform declares or holds it: it is not an orphan. Reconcile through Terraform, never by hand.
- A datastore exception class: never removed here. The datastore decommission has not been
  exercised ([dev-datastore.md](dev-datastore.md)).
- Ownership unclear: HOLD.
- The subscription is pending confirmation (step 1), or the ARN variable holds anything other than
  exactly one ARN: HOLD.

**If it fails.**

- Terraform declares or holds it: reconcile through Terraform
  ([terraform-operations.md](terraform-operations.md)), never by hand.
- The read-back is `UNKNOWN`: that is not absence. No procedure for it is written.
- A subscription still pending confirmation cannot be unsubscribed. The project records it as
  deleted only with its topic, and no procedure for it is published.

**Evidence to keep.** The investigation output with identifiers left out, the authorization
reference, the removal's exit status and the read-back count.

**Next step.** The census in step 8. A runtime class still above 0 is a STOP there.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-11) for one object: an email subscription left on a deleted SNS topic |
| Published form | not executed as written (generalized from that single cleanup; its removal call is the example in step 6, and capturing the subscription ARN into a variable is derived) |
| Evidence basis | [ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md#decision) (cost response stays owner-controlled; orphaned resource stop condition); retained private evidence of the 2026-09-11 read-only investigation, the bounded authorization, the removal and its read-back |
| Authority | Explicit owner authorization naming the one object |
| Cost | None to run; removing a billing orphan ends its charge |

**Known limitations.** One object class has been removed, once. Removing a controller-created load
balancer, its target groups or its security groups has never been exercised. A subscription still
pending confirmation cannot be unsubscribed; the project records it as deleted only with its topic,
and no procedure for it is published.

## Not yet exercised

- **Creating the budget and its five notifications.** Executed once, 2026-08-06: EXECUTED —
  RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE. No creation procedure is published,
  because no retained source for it is available; as a reproducible procedure it is UNEXERCISED.
- **Activating the six cost-allocation tags.** Executed once, 2026-08-21: EXECUTED — RECORDED ONLY;
  RETAINED EXECUTION EVIDENCE NOT AVAILABLE. No activation command is published; as a reproducible
  procedure it is UNEXERCISED.
- **Budget alert delivery** to its subscribers: UNEXERCISED.
- **The 100 USD target review**: UNEXERCISED. **The 150 and 200 USD responses**:
  DESIGNED-NOT-EXECUTED.
- **Halt, continue and resume procedures for the other
  [ADR-0013 stop conditions](../decisions/0013-define-operations-and-cost-guardrails.md#decision)**:
  UNEXERCISED. This runbook detects some of them (an absent budget alert, unexplained spend, an
  orphaned resource, cost attribution that cannot be demonstrated) and publishes no resume
  procedure for any. A failed state recovery or secret rotation has no procedure in any runbook;
  neither recovery nor rotation has been exercised ([terraform-operations.md](terraform-operations.md),
  [dev-datastore.md](dev-datastore.md)).
- **The weekly ADR-0013 review record**: DESIGNED-NOT-EXECUTED for its record fields, UNEXERCISED
  for its step 4 commands; first due 2026-10-01. ADR-0013 has required a weekly cost and billing
  review since it was accepted on 2026-08-01. No review record exists for any week so far.
  2026-10-01 is the first review due under this procedure, not the first review ADR-0013 required.
- **ADR-0013's other weekly duties** (budget anomaly review, registry and retained-resource review,
  evidence-retention review, and the evidence that each persistent foundation is still needed):
  UNEXERCISED.
- **Environment-hour ledger reconciliation**: no reviewed procedure published. UNEXERCISED.
- **The CPU-credit check's recurring cadence and its 3,600-second form**: DESIGNED-NOT-EXECUTED.
- **The CPU-credit response** (find the consumer, end the window driving it): UNEXERCISED.
- **Price re-check for the Route 53 query rate, the load balancer, registry storage and S3
  storage**: UNEXERCISED. No rate for them is in the table; registry storage cost is visible here
  only as a Cost Explorer service line.
- **Estimate against actual for the datastore** through Cost Explorer, grouped by the `Component`
  tag: UNEXERCISED.
- **Orphan cleanup for any class other than a confirmed SNS subscription**, including a
  subscription pending confirmation: UNEXERCISED.
- **Census coverage** outside us-east-1, for ADR-0018 classes 6 and 7, for SNS topics,
  subscriptions and roles under other names, and for persistent billable classes: UNEXERCISED.
- **Any read in this runbook on the read-only permission set**: never run.

## Reproducibility gaps

What a new engineer cannot yet reproduce from the public repositories:

- **Creating the budget and its five notifications.**
  - Cannot be reproduced: no creation procedure is published, because no retained source for it is
    available. The budget's cost filter, cost types and time period are not part of the measured
    check.
  - Public contract: the budget levels and stop conditions in ADR-0013; the budget's name, amount,
    scope and five notifications under [Background prerequisites](#background-prerequisites); and
    [Read back the budget and its alert states](#read-back-the-budget-and-its-alert-states), which
    checks the result.
  - Needed later: a public creation procedure.
- **Activating the six cost-allocation tags.**
  - Cannot be reproduced: no activation command is published, and no order for a new account,
    where a key can be activated only after a resource carries it
    ([Background prerequisites](#background-prerequisites)).
  - Public contract: the six mandatory tags in ADR-0013, and
    [Read back the cost-allocation tags](#read-back-the-cost-allocation-tags), which names the six
    keys and checks them.
  - Needed later: a public activation procedure, with its place in the build order.
- **Enabling Cost Explorer.**
  - Cannot be reproduced: it is a one-time console action outside the repositories, it cannot be
    done through the API, and when it was done on the reference account is not recorded.
  - Public contract: the prerequisite under [Background prerequisites](#background-prerequisites).
  - Needed later: a written console procedure. A command-line tool cannot do it, because the API
    cannot enable Cost Explorer.
- **Environment-hour ledger reconciliation.**
  - Cannot be reproduced: the ledger is kept by hand, and no reviewed reconciliation procedure is
    published.
  - Public contract: the ledger fields that ADR-0013 defines for each window.
  - Needed later: a public reconciliation procedure.
- **Resuming after an ADR-0013 stop condition.**
  - Cannot be reproduced: this runbook detects an absent budget alert, unexplained spend, an
    orphaned resource and cost attribution that cannot be demonstrated, and publishes no resume
    procedure for any of them. The investigation procedure for unexplained spend is not written
    either.
  - Public contract: the stop conditions in ADR-0013 and the detecting procedures here.
  - Needed later: public resume procedures.
- **Responding to a CPU-credit REVIEW.**
  - Cannot be reproduced: the response is unexercised, and stopping or decommissioning the datastore
    instance are not exercised procedures.
  - Public contract: the decommission design in the
    [dev-datastore README](../../terraform/dev-datastore/README.md#decommission) and
    [Check the datastore CPU credits](#check-the-datastore-cpu-credits).
  - Needed later: a public response procedure, with stop and decommission procedures for the
    instance ([dev-datastore.md](dev-datastore.md)).
- **The orphan census as validated.**
  - Cannot be reproduced: the retained results came from a private census tool, and its offline
    controls for the classifier and the three-state rule exercised that tool, not the helpers
    published here.
  - Public contract: the published census, its fail-closed rule and its expected-class table.
  - Needed later: a run of the published helpers themselves, live and against offline controls. No
    public harness for such controls exists today.
- **ADR-0013's other weekly duties.**
  - Cannot be reproduced: the budget anomaly review, the registry and retained-resource review, the
    evidence-retention review and the evidence that each persistent foundation is still needed have
    no reviewed procedure.
  - Public contract: the weekly duties in ADR-0013.
  - Needed later: public procedures for them.
- **Orphan cleanup beyond one SNS subscription.**
  - Cannot be reproduced: only one object class has been removed, once. A subscription still pending
    confirmation cannot be unsubscribed, and no procedure for it is published.
  - Public contract: [Clean up an orphan](#clean-up-an-orphan).
  - Needed later: a procedure for each further class when it is first needed.
- **The AWS CLI version.**
  - Cannot be reproduced: the minimum AWS CLI version was never recorded.
  - Public contract: AWS CLI v2, `bash` and `jq`.
  - Needed later: no new procedure or tool; the gap closes when a run records its version.

<a id="hidden-prerequisites"></a>

## Background prerequisites

- **Cost Explorer.** Enabled on the account, a one-time console action outside the repositories; it
  cannot be enabled through the API, and current-month data appears about 24 hours after enabling.
  When it was enabled on the reference account is not recorded. In a member account of an
  organization, Cost Explorer access depends on the management account.
- **Budget.** A monthly cost budget named `cloud-platform-reference`, 200 USD, for the project
  account's spend, created outside Terraform, with five notifications, ACTUAL 100, 150 and 200 and
  FORECASTED 150 and 200, each `GREATER_THAN` with an `ABSOLUTE_VALUE` threshold. By an owner
  decision there is no FORECASTED 100. In an AWS Organizations management account, its scope is
  limited to the project account. ADR-0013 requires the budget and its alerts before the first
  billable resource, the state bucket ([terraform-operations.md](terraform-operations.md)).
- **Subscribers.** The notification recipients' addresses, held privately.
- **Cost-allocation tags.** The six tag keys activated by an identity with billing authority; in an
  organization, from the management account. AWS lists a user-defined key for activation only after
  a resource carries it, which can take up to 24 hours, and newly activated keys take up to 24 hours
  to apply. On a new account, the tag read-back that the [build order](README.md#task-list) runs
  before the first billable resource therefore passes only if resources carrying the six keys
  already exist. No reviewed order for a new account is published; until the owner decides one, the
  read-back's STOP holds.
- **Environment-hour ledger.** A ledger kept by hand with the fields
  [ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md#decision) defines for each
  window, which the weekly review and the 100 and 150 USD levels reconcile against.
- **Expected persistent set.** Knowledge of what should persist in the account (the Terraform roots'
  retained addresses and the datastore), so that the census and the weekly review can tell retained
  from residual. The public sources are the persistent-foundation register in the
  [architecture baseline](../architecture-baseline.md#persistent-foundations), the Dev root's
  retained addresses in
  [Confirm the retained and runtime split](dev-network.md#confirm-the-retained-and-runtime-split),
  and the [dev-datastore README](../../terraform/dev-datastore/README.md#what-it-creates).
