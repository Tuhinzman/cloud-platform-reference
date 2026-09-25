# Dev Network Runbook

This runbook operates the retained side of [`terraform/dev`](../../terraform/dev/README.md): the
zone check before a first build, building only the retained baseline, confirming the split
between retained and runtime addresses, reading the network and the environment's two Secrets
Manager entries back from AWS, and checking what the Dev datastore now places inside this network.
It does not create or operate the runtime, and it does not repeat what the root creates or why.

Two terms carry this page. The **retained baseline** is what this root keeps in AWS between
runtime windows: 21 Terraform addresses, 14 for the network and 7 for identity, secrets and
configuration. A **runtime window** is a bounded period in which the EKS cluster, its nodes and
the NAT gateway are created on top of the retained baseline, exercised and destroyed.

The resources, the address plan, the routing, the S3 gateway endpoint and the tagging are in the
root README ([What it creates](../../terraform/dev/README.md#what-it-creates),
[Address plan](../../terraform/dev/README.md#address-plan),
[Routing](../../terraform/dev/README.md#routing),
[The S3 gateway endpoint](../../terraform/dev/README.md#the-s3-gateway-endpoint),
[Tagging](../../terraform/dev/README.md#tagging)), and the retained, runtime and alerting classes
with their counts are in
[Lifecycle and current state](../../terraform/dev/README.md#lifecycle-and-current-state). This
runbook adds the measured address lists and the procedures around them.

Covered elsewhere, and linked from the steps that need it:

- [Runtime Validation](../validation/runtime-validation.md): a summary of the runtime windows that
  ran, meaning runtime creation, targeted teardown and the post-teardown census. Runtime windows
  are outside this suite, and no runtime creation or teardown procedure is published in it.
- [terraform-operations.md](terraform-operations.md): the workflow every root shares, meaning
  static checks, backend initialisation, saved plans, their review and binding, applies, locks,
  drift detection and reconciliation, and interrupted applies.
- [dev-datastore.md](dev-datastore.md) and its [README](../../terraform/dev-datastore/README.md):
  the datastore root.
- [cost-and-residue.md](cost-and-residue.md): the budget, pricing re-checks, the orphan census
  and the weekly cost review.
- [evidence-handling.md](evidence-handling.md): capturing and keeping evidence.
- [operator-access.md](operator-access.md): sign-in and the account check.

> **Warning: a plain `terraform apply` in `terraform/dev` creates billable runtime.** It creates
> the runtime as well as the retained baseline: the EKS control plane, the NAT gateway with its
> Elastic IP, and two `m6a.large` nodes
> ([Estimated planning baseline](../../terraform/dev/README.md#estimated-planning-baseline)).
> `worker_capacity_enabled = false` still creates the EKS control plane. Build the retained
> baseline only with the targeted stages in
> [Build only the retained baseline](#build-only-the-retained-baseline).

> **Warning: never run an untargeted `terraform destroy` in `terraform/dev`.** It removes the
> retained baseline, schedules both Secrets Manager entries for deletion, and tries to remove a
> VPC and subnets that the datastore's resources occupy. No reviewed command-level decommission
> procedure exists ([Not yet exercised](#not-yet-exercised)).

> **Warning: the Dev datastore sits inside this network.** The datastore root finds the Dev VPC
> and the two private subnets by their `Name` tags, never through this root's state; its
> security group admits TCP 5432 from the two private subnet ranges; and its subnet group,
> security group and instance network interface sit inside this VPC. Renaming or re-addressing
> those resources therefore changes or breaks the datastore root's plan, and the datastore root
> is destroyed before this network
> ([datastore Decommission](../../terraform/dev-datastore/README.md#decommission)). While a
> runtime window is open, every node and pod in the private subnets can reach the datastore on
> TCP 5432 ([datastore Boundary](../../terraform/dev-datastore/README.md#boundary)).

## Normal path

1. [Check the zone mapping before the first build](#check-the-zone-mapping-before-the-first-build).
   Read-only, once, before anything is built. Checks that the two hard-coded zones suit EKS, the
   node type and the datastore engine in your account.
2. [Build only the retained baseline](#build-only-the-retained-baseline). Two targeted, approved
   applies: the 14 network addresses, then the 7 identity, secret and configuration addresses.
   No runtime.
3. [Confirm the retained and runtime split](#confirm-the-retained-and-runtime-split). Read-only.
   State holds exactly the 21 retained addresses, and a plan that is never applied shows exactly
   the 17 runtime addresses.
4. [Read back the retained network](#read-back-the-retained-network), with
   [Read back the two Secrets Manager entries](#read-back-the-two-secrets-manager-entries).
   Read-only. AWS itself, not state, matches the README.
5. Once the datastore root is built (dev-datastore.md):
   [Verify the retained side with the datastore present](#verify-the-retained-side-with-the-datastore-present).
   Read-only. Tells the datastore's footprint in this VPC apart from runtime residue, and repeats
   the network read-back as its last step.

Steps 3 and 4 are the last step of the build, so a first build runs them from inside step 2.

To find where to start, initialize the root: steps 1 to 3 of
[Initialize a root against the state backend](terraform-operations.md#initialize-a-root-against-the-state-backend),
with `<root>` set to `dev` (PASS: `git check-ignore` lists `backend.hcl` and `terraform.tfvars`,
`init` reports the backend configured and Terraform initialized, and `git status` prints
nothing). Then list state with step 1 of
[Inspect state without writing it](terraform-operations.md#inspect-state-without-writing-it) and
return here. If it lists nothing, start at step 1. If it lists addresses, skip steps 1 and 2 and
start at step 3, which checks the listing against the 21 retained addresses. A build that stopped
between its two stages leaves the 14 network addresses alone; no procedure resumes it, and step 3
stops on it. So run both stages of step 2 in one sitting.

## Before you start

- [ ] **Account and access.** A dedicated AWS account, its 12-digit ID for `allowed_account_id`,
  and an Identity Center profile for it on the `AdministratorAccess` permission set, set up at
  step 1 of the runbook index's Build order.
- [ ] **Shell.** This page's steps run in a **profile shell**, from the directories in the table
  **Where each step runs** below: a shell with `AWS_PROFILE=<profile>` and `AWS_REGION=us-east-1`
  exported, where `<profile>` is the `AdministratorAccess` profile. The account check confirms
  that the shell is on the project account: run steps 1 and 2 of
  [Check the account before AWS commands](operator-access.md#check-the-account-before-aws-commands)
  in it, with `<root-tfvars>` set to the dev root's `<inputs-dir>/terraform.tfvars`, and continue
  only on `ACCOUNT_MATCH=PASS`; then return to this list. Its AWS CLI commands therefore name no
  profile: this page is an exception to the rule in
  [operator-access.md](operator-access.md#before-you-start) that no command relies on an
  inherited `AWS_PROFILE`. Commands taken from [dev-datastore.md](dev-datastore.md), such as
  step 4 of the zone check, keep their `--profile <profile>`, which names the same profile.
- [ ] **Exported shell.** The budget read and the price re-check that the build requires run in
  an exported shell: a clean shell that holds one role credential and no profile. When
  [Build only the retained baseline](#build-only-the-retained-baseline) calls for them, prepare it
  with steps 1 to 4 of [Export role credentials once](operator-access.md#export-role-credentials-once)
  (PASS: `ACCOUNT_MATCH=PASS` with no HOLD line, and the headroom line with exit 0). Then return
  to that procedure's **Before you start** and run the two reads in the shell, as step 5 of the
  export procedure; exit the shell afterwards, as its step 6. No published rule requires one for
  this page's own steps. If you run one of them in an exported shell, as
  [terraform-operations.md](terraform-operations.md) does for a long or sensitive operation, leave
  `AWS_PROFILE` unset there, drop `AWS_PROFILE=<profile>` from the Terraform commands and
  `--profile <profile>` from any command that carries it, and define the target arrays and
  `VPC_ID` inside it.
- [ ] **State backend.** The name of the state bucket the bootstrap root created, in an untracked
  `backend.hcl`.
- [ ] **Root inputs.** An untracked `terraform.tfvars` with `allowed_account_id` and
  `operator_cidr`. Every plan needs both, including network-only and read-only plans
  ([Input](../../terraform/dev/README.md#input)). Leave the alerting inputs
  `alerting_campaign_enabled`, `alerting_email_subscription_enabled` and `alerting_email_endpoint`
  unset ([Alerting](../../terraform/dev/README.md#alerting)). A set alerting flag does not change
  the plan counts, so the saved-plan procedures below check the variables themselves.
- [ ] **Operator address.** Your public IPv4 address as a `/32` for `operator_cidr`. Every plan of
  this root requires it, and it changes with the network you work from.
- [ ] **Tools.** Terraform 1.11 or later and below 2.0, as
  [`versions.tf`](../../terraform/dev/versions.tf) allows, validated here on 1.15.5 only; the AWS
  provider the committed lock file pins (6.58.0); the AWS CLI v2; and `jq`, `git`, `unzip` and
  `shasum` for the saved-plan review and binding in
  [terraform-operations.md](terraform-operations.md).
- [ ] **Private working location.** A new `<private-dir>` for each plan, outside every Git
  working tree and created under `umask 077`, for saved plans, plan JSON, plan text and read-back
  output. They carry account and resource identifiers, and saved plans hold `operator_cidr` in
  clear text.
- [ ] **Approver.** Someone with authority over the account who reviews and approves each saved
  plan before it is applied.
- [ ] **Cost controls.** The budget and its alerts in place before the first billable resource,
  and a current Secrets Manager price, both read as the **Before you start** of
  [Build only the retained baseline](#build-only-the-retained-baseline) lists.

**Where each step runs.**

| Work | Shell | Directory |
|---|---|---|
| The budget read-back and the price re-check before the build | The exported shell (**Exported shell** above): no profile, and no command names one | Any; give `<root-tfvars>` as an absolute path |
| Terraform: initialize, list state, plan, review, bind and apply, as in [terraform-operations.md](terraform-operations.md) | Profile shell. The commands keep their `AWS_PROFILE=<profile>` prefix, which names the same profile. The build's target arrays are defined in this same shell | `<work-dir>/terraform/dev`, the working tree that [Initialize a root against the state backend](terraform-operations.md#initialize-a-root-against-the-state-backend) creates, except where a step there names another directory |
| AWS CLI: the zone check, the read-backs and the check with the datastore present | Profile shell. `VPC_ID` stays set only in the shell that resolved it | Any: these commands read no local file |

`<inputs-dir>`, `<work-dir>`, `<private-dir>`, `<plan-file>` and `<plan-json>` are as defined in
[terraform-operations.md](terraform-operations.md). Dates are UTC. No command here reads a secret
value.

## Procedures

### Check the zone mapping before the first build

**Validation:** DESIGNED-NOT-EXECUTED (never) · **Published command form:** not executed as written

**What this does.** [`networking.tf`](../../terraform/dev/networking.tf) hard-codes the zone
names `us-east-1a` and `us-east-1b`. A zone name maps to a physical zone per account, so the same
names can land in different physical zones in your account. EKS, the node instance type and the
datastore engine all have to be available in the zones you actually get.

This check maps the two names to zone IDs and tests all three before the first build. The
datastore reuses the two private subnets, so the zones chosen here are its zones too.

**Before you start.**

- [ ] A session on the project account, confirmed with the account check as the **Shell** item of
  [Before you start](#before-you-start) describes; continue only on `ACCOUNT_MATCH=PASS`, then
  return to this list.
- [ ] The network has not been built yet. After the first apply, a zone change replaces subnets
  (see [Not yet exercised](#not-yet-exercised)).

**Safety and authority.** Read-only. No approval and no cost.

**Steps.**

1. Map the two names to zone IDs:

   ```
   aws ec2 describe-availability-zones --zone-names us-east-1a us-east-1b \
     --query 'AvailabilityZones[].{name:ZoneName,zoneId:ZoneId,state:State}' --output table
   ```

2. Check both zone IDs against the current Amazon EKS documentation on zone IDs that cannot
   hold cluster subnets. AWS maintains that list; this step has no command.
3. Check that the node instance type is offered in both zone IDs. Put the two zone IDs from
   step 1 in place of `<zone-id-a>` and `<zone-id-b>`:

   ```
   aws ec2 describe-instance-type-offerings --location-type availability-zone-id \
     --filters Name=instance-type,Values=m6a.large Name=location,Values=<zone-id-a>,<zone-id-b> \
     --query 'sort(InstanceTypeOfferings[].Location)' --output text
   ```

4. Check that the datastore engine can be ordered in both zone names. The command names the
   profile this shell already exports; inside an exported shell, drop `--profile <profile>`:

   ```
   aws rds describe-orderable-db-instance-options --profile <profile> --region us-east-1 \
     --engine postgres --engine-version 17.11 --db-instance-class db.t4g.micro \
     --query 'OrderableDBInstanceOptions[?StorageType==`"gp3"`].AvailabilityZones[].Name'
   ```

**Expected result.** Two rows in step 1, both `available`; neither zone ID is excluded by the
EKS documentation; step 3 prints both zone IDs; step 4 lists both zone names.

**PASS when.**

- [ ] Both zones are `available`, and EKS excludes neither zone ID.
- [ ] Step 3 prints both zone IDs, and step 4 lists both zone names.

**STOP if.**

- A zone is not `available`.
- EKS excludes a zone ID.
- Step 3 prints fewer than two zone IDs.
- A zone name is missing from step 4.

**If it fails.** Choose two us-east-1 zone names whose IDs pass all four checks, and change the
four `availability_zone` arguments in `networking.tf` as a reviewed change before the first
plan: `aws_subnet.private_a` and `aws_subnet.public_a` share one zone, `aws_subnet.private_b`
and `aws_subnet.public_b` the other. The README's
[What it creates](../../terraform/dev/README.md#what-it-creates) and
[Address plan](../../terraform/dev/README.md#address-plan), and the zone names expected by
[Read back the retained network](#read-back-the-retained-network), would then differ from
your build. This path has never been exercised.

**Evidence to keep.** The name-to-ID mapping. Later read-backs compare the subnets' zone IDs
against it.

**Next step.** If another runbook sent you here, return to the step that sent you.
[Build only the retained baseline](#build-only-the-retained-baseline).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | DESIGNED-NOT-EXECUTED (never) |
| Published form | not executed as written (never run; derived from the README's requirement that the node type be checked in both zones, and from the datastore's capacity prerequisite) |
| Evidence basis | [Address plan](../../terraform/dev/README.md#address-plan). No check of the zone mapping, EKS zone support or the datastore engine before the first build is recorded. What is recorded are facts about the reference account, not runs of this check, and none has retained command output: the built subnets' zone IDs were read back after the network was built, on 2026-08-10, and `m6a.large` availability in both zone IDs was recorded as satisfied before the first runtime apply. Retained private evidence of later runtime windows shows the cluster and nodes created in these subnets; that is an outcome, not this check |
| Authority | none (read-only) |
| Cost | none |

Step 4 is the engine check of [Run the pre-apply gate](dev-datastore.md#run-the-pre-apply-gate),
step 2, run on its own and as written. The gate's other prerequisites, such as a bound saved plan,
belong to the datastore apply.

### Build only the retained baseline

**Validation:** COMPOSED FROM AWS-VALIDATED STEPS; END-TO-END COMMAND FORM NOT YET EXERCISED; targeted plans and applies and the alerting check DESIGNED-NOT-EXECUTED; part of step 6 EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (Engineering notes) · **Published command form:** not executed as written

**What this does.** Creates the 21 retained addresses and nothing else. The root has no switch
that builds only them, so the build is two reviewed, targeted stages: the network (14
addresses), then the identity, secret and configuration resources (7). Each stage's plan passes
every address of that stage with `-target`, and must contain exactly one `create` for each
target. The order repeats how the set was first created and keeps each saved plan to one class;
neither stage depends on the other.

Each stage uses a **saved plan**: a plan written to a file, reviewed, bound to its hash and to
the state it was made from, approved, and then applied exactly as reviewed
([terraform-operations.md](terraform-operations.md)). Both Secrets Manager entries are created
empty.

**Before you start.**

- [ ] The bootstrap root has created the state bucket. Nothing runs here:
  [Build the state backend and migrate into it](terraform-operations.md#build-the-state-backend-and-migrate-into-it)
  runs once per project, at step 3 of the runbook index's Build order (PASS: state lists exactly
  the five bootstrap resources, and Confirm convergence returns 0). If it has not passed, run it
  first, then return to this list.
- [ ] The root passes [Run the static checks](terraform-operations.md#run-the-static-checks),
  steps 1 to 3, on `terraform/dev` at `<commit>`; for a first build, `<main-commit>` is that same
  commit. PASS: `fmt`, `validate`, `tflint` and every `trivy config` exit 0, `git status` prints
  nothing, and `diff` prints no line beginning `>`. Then return to this list.
- [ ] The root is
  [initialized against the backend](terraform-operations.md#initialize-a-root-against-the-state-backend),
  steps 1 to 3 with `<root>` set to `dev`, at the reviewed commit. PASS: `git check-ignore` lists
  `backend.hcl` and `terraform.tfvars`, `init` reports the backend configured and Terraform
  initialized, and `git status` prints nothing. Then return to this list.
- [ ] No state exists yet under `dev/terraform.tfstate`: run step 1 of
  [Inspect state without writing it](terraform-operations.md#inspect-state-without-writing-it)
  (PASS: it lists nothing, the expected set for a root never applied), then return to this list.
  This build is therefore the root's first apply: if the binding check's state read in step 4
  prints nothing, the network stage stops before its apply, and no published procedure resolves
  that ([Bind the saved plan](terraform-operations.md#bind-the-saved-plan-to-its-hash-and-to-state),
  **If it fails**). For an existing state, use
  [Confirm the retained and runtime split](#confirm-the-retained-and-runtime-split) instead.
- [ ] [Check the zone mapping before the first build](#check-the-zone-mapping-before-the-first-build)
  has passed.
- [ ] The budget and its alerts are in place, which
  [ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md) requires before the
  first billable resource, and Secrets Manager pricing has been re-checked. Run both reads in the
  exported shell that **Exported shell** in this page's [Before you start](#before-you-start)
  prepares, not in this page's profile shell:
  [Read back the budget and its alert states](cost-and-residue.md#read-back-the-budget-and-its-alert-states),
  steps 1 to 6 (PASS: one `cloud-platform-reference` row with `COST`, `MONTHLY`, `200.0` and
  `USD`, and the five notifications all `OK`, each with at least one subscriber; on an `ALARM`,
  follow its **Next step**); then
  [Re-check prices before billable work](cost-and-residue.md#re-check-prices-before-billable-work),
  steps 1 to 3, with only the `price AWSSecretsManager` line of step 2 (PASS: its values equal
  the price table, 0.40 USD per secret-month for the secret). Then exit that shell and return to
  this list.
- [ ] The campaign's evidence set opened before step 2: steps 1 and 2 of
  [Capture a campaign evidence set](evidence-handling.md#capture-a-campaign-evidence-set) (PASS: one
  campaign directory under the evidence root, mode 0700), with your own redaction filter. The whole
  build, both stages and the step 6 checks, is one campaign, closed after step 6. Then return to
  this list.
- [ ] Inputs: `backend.hcl`; `terraform.tfvars` with `allowed_account_id` and `operator_cidr` and
  the alerting inputs unset; a new `<private-dir>` for each stage's plan.
- [ ] Time to run both stages in one sitting: the approver available for both saved plans, and a
  session that outlasts both applies
  ([Check session headroom before long operations](operator-access.md#check-session-headroom-before-long-operations)).
  This runbook states no minimum session time and publishes no measured duration for either
  stage, and neither has run with these target lists. Set `<required-minutes>` as step 1 of
  that procedure describes; no margin rule has been established.
  A build that stops after the network stage leaves state with the 14 network addresses alone; no
  procedure resumes it, and
  [Confirm the retained and runtime split](#confirm-the-retained-and-runtime-split) stops on it.
  Run steps 1 to 3 of the headroom check (PASS: the headroom line, exit 0), then return to this
  list.

**Safety and authority.** Mutating, billable, owner-authorized. The account owner explicitly
approves each reviewed saved plan before it is applied. The two Secrets Manager entries cost about
0.80 USD a month, prorated from creation.

> **Warning:** Every plan in this procedure carries its target list. Without it the plan covers
> the whole root, and applying it creates the billable runtime (see the warning at the top of
> this page).

**Steps.**

1. Define the two target lists. An array keeps every target in the command; a broken line
   continuation once dropped the targets from a plan of this root (Engineering notes).

   ```
   network_targets=(
     -target=aws_vpc.dev
     -target=aws_subnet.private_a -target=aws_subnet.private_b
     -target=aws_subnet.public_a -target=aws_subnet.public_b
     -target=aws_internet_gateway.dev
     -target=aws_route_table.public -target=aws_route.public_default
     -target=aws_route_table.private
     -target=aws_route_table_association.public_a -target=aws_route_table_association.public_b
     -target=aws_route_table_association.private_a -target=aws_route_table_association.private_b
     -target=aws_vpc_endpoint.s3
   )
   identity_targets=(
     -target=aws_secretsmanager_secret.workload
     -target=aws_secretsmanager_secret.argocd_gitops_deploy_key
     -target=aws_ssm_parameter.workload
     -target=aws_iam_role.workload -target=aws_iam_role_policy.workload
     -target=aws_iam_role.external_secrets -target=aws_iam_role_policy.external_secrets
   )
   ```

   The arrays exist only in the shell that defined them. Define them again in any new shell, an
   exported shell included: an undefined array expands to nothing, and the plan then covers the
   whole root.

2. Record the reviewed list first, as the campaign record's **Expected** field: one `create` line
   for each network target. Then plan the network stage with step 1 of
   [Plan to a saved file](terraform-operations.md#plan-to-a-saved-file), once every item of its
   **Before you start** holds, debug logging off included, with `"${network_targets[@]}"`
   appended on the same line:

   ```
   AWS_PROFILE=<profile> terraform plan -lock=false -input=false -no-color -detailed-exitcode -out=<plan-file> "${network_targets[@]}"
   echo $?
   ```

   > **Warning:** Go on only if the plan output contains the summary line
   > `Plan: 14 to add, 0 to change, 0 to destroy.` and Terraform's warning that resource
   > targeting is in effect.

   PASS: exit 2 and the saved plan at `<plan-file>`. Then continue at step 3.

3. Run steps 1 to 5 of [Review the saved plan](terraform-operations.md#review-the-saved-plan)
   against the reviewed list from step 2. Then confirm that the alerting inputs are off. This
   prints two booleans and no input value:

   ```
   jq -r '.variables | "alerting_campaign_enabled=\(.alerting_campaign_enabled.value) alerting_email_subscription_enabled=\(.alerting_email_subscription_enabled.value)"' <plan-json>
   ```

   This targeted plan shows `complete` as `false`. That is expected here, and it is the one
   exception to the review's criteria; every other criterion applies. PASS: `applyable` `true`
   and `errored` `false` on the validated Terraform version, exactly the 14 network `create`
   lines, no drift line and no output change, and both alerting variables `false`. Then continue
   at step 4.

4. Run steps 1 and 2 of
   [Bind the plan](terraform-operations.md#bind-the-saved-plan-to-its-hash-and-to-state) now, have
   the plan approved, and run its step 3 immediately before the apply. PASS: `same` for every
   file and the lock file with no `diff` output, and in step 3 the recorded hash and the plan's
   serial and lineage; on the network stage, the root's first apply, steps 1 and 3 both show
   serial 0 and no lineage. Then apply exactly that plan with steps 1 and 2 of
   [Apply the reviewed saved plan](terraform-operations.md#apply-the-reviewed-saved-plan). Its
   **Before you start** is already met by this procedure's **Before you start** and steps 2 to 4,
   and its step 3, the read-back, is step 6 here.

   After this apply, the check is the state listing in step 2 of that procedure: exactly the 14
   network addresses. Do not go on to its next step, Confirm convergence: while no runtime exists,
   an untargeted plan here shows the runtime still to add and exits 2. Do not run
   [Confirm the retained and runtime split](#confirm-the-retained-and-runtime-split) yet either:
   it expects all 21 addresses and stops on the 14. Step 6 runs it and the read-backs after both
   stages. Continue at step 5.
5. Plan the identity, secret and configuration stage the same way, with
   `"${identity_targets[@]}"` appended, in a new `<private-dir>` with its own `<plan-file>`:

   ```
   AWS_PROFILE=<profile> terraform plan -lock=false -input=false -no-color -detailed-exitcode -out=<plan-file> "${identity_targets[@]}"
   echo $?
   ```

   > **Warning:** Go on only if the plan output contains the summary line
   > `Plan: 7 to add, 0 to change, 0 to destroy.` and Terraform's warning that resource targeting
   > is in effect.

   Then review it with the same checks, bind it, have it approved and apply it, as in steps 3
   and 4. After this apply, too, do not run Confirm convergence; continue at step 6, where
   Confirm the retained and runtime split is the check for the whole build.
6. Run [Confirm the retained and runtime split](#confirm-the-retained-and-runtime-split),
   [Read back the retained network](#read-back-the-retained-network) and
   [Read back the two Secrets Manager entries](#read-back-the-two-secrets-manager-entries). Then
   close the campaign: steps 4 to 7 of the [Normal path](evidence-handling.md#normal-path) of
   evidence-handling.md (PASS: every manifest entry reports `OK`, the set holds no file the
   manifest does not list, and the manifest's full SHA-256 is in the private record outside the
   set). Then return here for **Expected result** and the **Next step**; the export steps that
   follow in that path run only around a teardown.

**Expected result.**

- Step 2 exits 2 and the plan text contains the summary line
  `Plan: 14 to add, 0 to change, 0 to destroy.`, with Terraform's warning that resource targeting
  is in effect.
- Step 3: the action list is exactly 14 `create` lines, one for each network target; the drift
  list and the output changes are empty; the alerting check prints
  `alerting_campaign_enabled=false alerting_email_subscription_enabled=false`. `applyable` is
  `true` and `errored` is `false`, but `complete` is `false`: Terraform marks a targeted plan
  incomplete, as the retained targeted plans of this root show on Terraform 1.15.5. That is the
  one expected difference from the review's criteria.
- Step 5: `Plan: 7 to add, 0 to change, 0 to destroy.`, with seven `create` lines and the same
  checks.
- Each apply reports the same counts as its plan.
- After the network apply, the state listing taken in step 4 holds exactly the 14 network
  addresses. After the second apply, state holds the 21 that
  [Confirm the retained and runtime split](#confirm-the-retained-and-runtime-split) lists.

**PASS when.**

- [ ] Each stage's plan held only its targets, all `create`: 14, then 7.
- [ ] In both reviews `applyable` was `true`, `errored` `false` and `complete` `false`, and every
  other review criterion held.
- [ ] Both alerting variables were `false` in both plans.
- [ ] Each apply reported the same counts as its plan.
- [ ] The three verification procedures in step 6 pass.

**STOP if.**

- A listing with any address that stage did not target, or any action other than `create`.
- Any runtime or alerting-campaign address in either plan, or either alerting variable `true`.
- A plan that fails the provider's account check, or a session on another account.
- A state lock error. The plans on this page run with `-lock=false`, so the error comes from an
  apply, and that apply has failed: handle it as **Failed or interrupted apply** under
  **If it fails**, not by going to
  [Handle a held state lock](terraform-operations.md#handle-a-held-state-lock) first.
- An apply that errors or is interrupted.
- The binding check's state read prints nothing before the first stage's apply. On a root never
  applied, what that read prints has not been recorded, so an empty result is a mismatch no
  published procedure resolves ([Bind the saved plan](terraform-operations.md#bind-the-saved-plan-to-its-hash-and-to-state)).

**If it fails.**

- **Wrong account.** Follow
  [Recover from a wrong account](operator-access.md#recover-from-a-wrong-account): part A when no
  mutating command has run, part B when a mutating command already ran against another account.
  PASS: its part A, step 4, both identity values `True` and `ACCOUNT_MATCH=PASS`; if that fails,
  work stays stopped as that procedure says. Then return to step 1 of this procedure, never to
  the plan command that stopped, even in the same shell: the recovery exits any exported shell,
  and a plan in a shell without the target lists covers the whole root. In the profile shell that
  **Shell** in this page's [Before you start](#before-you-start) prepares, account check included,
  and from `<work-dir>/terraform/dev`, define both target lists again with step 1. Then continue
  at step 2 if the network stage has not been applied, or at step 5 if its apply completed and the
  step 4 state listing showed exactly the 14 network addresses, with a new `<private-dir>` for the
  new plan. Any other state is handled as **Failed or interrupted apply** below.
- **Failed or interrupted apply.** Stop and inspect read-only as
  [Stop after a failed or interrupted apply](terraform-operations.md#stop-after-a-failed-or-interrupted-apply)
  describes, before any further apply or destroy. This page's path ends at that procedure's
  **Next step**, the owner's reviewed recovery decision, which also decides any lock release.
  Recovering a partial apply of this root has not been exercised.
- **A secret name is already in use.** Either a secret of that name exists outside this state or
  one is scheduled for deletion. Both are a STOP: read its metadata with
  [Read back the two Secrets Manager entries](#read-back-the-two-secrets-manager-entries), where a
  `deletedDate` marks one scheduled for deletion, and take no further action. No reviewed
  recovery exists for either case: restoring within the window, importing, or waiting for the
  deletion to complete. Work stays stopped until a reviewed decision is taken under explicit
  approval ([When to stop](README.md#when-to-stop)).
- **Rollback.** No reviewed rollback exists. Removing what this build created is the
  decommission, which has not been exercised; an untargeted `terraform destroy` is not a
  rollback (see the warning at the top of this page). Both Secrets Manager entries are configured
  with a seven-day recovery window; deletion and recovery have not been exercised (see
  [Not yet exercised](#not-yet-exercised)).

**Evidence to keep.** For each stage, what [terraform-operations.md](terraform-operations.md)
lists for a review and an apply, plus the alerting check; and the output of the three
verification procedures. Keep all of it privately, as
[evidence-handling.md](evidence-handling.md) describes. The saved plans never leave
`<private-dir>`: they hold every input value, `operator_cidr` included, in clear text.

**Next step.** Build the datastore root ([dev-datastore.md](dev-datastore.md)). The two secret
values are needed before a runtime window uses them.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | COMPOSED FROM AWS-VALIDATED STEPS; END-TO-END COMMAND FORM NOT YET EXERCISED (end to end: never), except these parts: DESIGNED-NOT-EXECUTED (never) for the plans and applies with the two target lists, for the alerting check's `jq` form and for the zone-mapping precondition; for step 6's network read-back, EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-10) for the checks that procedure lists and DESIGNED-NOT-EXECUTED (never) for the rest |
| Published form | not executed as written (the two target lists are derived from how the retained set was first created and from the recorded 21-address set; the plan, review, binding and apply forms are those of [terraform-operations.md](terraform-operations.md); this sequence has never run) |
| Evidence basis | AWS-validated steps it composes, as recorded where they are published: initializing a root, planning to a saved file, reviewing the saved plan, binding it to its hash and to state, and applying it ([terraform-operations.md](terraform-operations.md)); [Confirm the retained and runtime split](#confirm-the-retained-and-runtime-split) and [Read back the two Secrets Manager entries](#read-back-the-two-secrets-manager-entries). Not AWS-validated: [Read back the retained network](#read-back-the-retained-network) (recorded only), [Check the zone mapping before the first build](#check-the-zone-mapping-before-the-first-build) (never run), saved plans with these target lists (never run) and the alerting check's `jq` form (never run). History of the set, from commits `bf8dfd5` and `df05255` (network) and `5cf12a7`, `3485b34` and `d5effce` (identity, secret and configuration resources) on public main: the network was created by one apply of 14 resources on 2026-08-09 or 2026-08-10 (the apply's time was not recorded; its S3 endpoint was created at 00:00 on 2026-08-10), before the root declared any runtime, and then received its `Name` tags in place; the identity, secret and configuration resources were created by three targeted applies between 2026-08-12 and 2026-08-17, against a root that already declared the runtime. Those executions are EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-09 to 2026-08-17). The resulting state, 21 addresses with an ordinary plan of 17 to add, is covered by retained private evidence of 2026-09-22 |
| Authority | Explicit approval of each reviewed saved plan by the account owner before it is applied |
| Cost | About 0.80 USD a month for the two Secrets Manager entries (0.40 USD per secret-month, the us-east-1 list price last read from the AWS Price List on 2026-09-24), prorated from creation. The network, the parameter and the IAM resources carry no charge |

The broken line continuation that step 1 guards against is recorded under **Known limitations**
in [Stop after a failed or interrupted apply](terraform-operations.md#stop-after-a-failed-or-interrupted-apply).

**Known limitations.**

- Both Secrets Manager entries are created empty, and placing their values has no public
  procedure (see [Background prerequisites](#background-prerequisites)).
- Neither stage has run with these target lists. The network stage has never run against a
  root that declares the runtime. The identity resources were created by three smaller targeted
  applies against such a root, and those are EXECUTED — RECORDED ONLY; RETAINED EXECUTION
  EVIDENCE NOT AVAILABLE (2026-08-12 to 2026-08-17).
- On the network stage no state exists yet, so the binding compares an empty state. On
  2026-09-22 the first apply of the datastore root was bound this way: the backend reported
  serial 0 with no lineage and no resources, and the saved plan's prior state carried serial 0
  and an empty lineage. That check has not run on this root.
- The alerting check is derived from a reviewed private plan check that held a plan of this
  root on exactly that condition on 2026-09-22; this `jq` form has not run.
- Step 6 reads the network and the two secrets back from AWS. The Parameter Store entry, the
  two Pod Identity roles and their inline policies are covered only by the state listing (see
  [Not yet exercised](#not-yet-exercised)).

### Confirm the retained and runtime split

**Validation:** AWS-VALIDATED (2026-09-22) · **Published command form:** not executed as written

**What this does.** Shows that state holds the retained set and nothing else, that the
configuration still declares exactly the runtime set on top of it, and that state has not drifted
from AWS. It lists state, then makes an ordinary saved plan without targets that is only read.
When state already exists, start here instead of building.

The **runtime set** is 17 addresses: 10 created only when `worker_capacity_enabled` is true, and
7 created by every apply that is not targeted. The expected result lists both.

**Before you start.**

- [ ] The root is
  [initialized against the backend](terraform-operations.md#initialize-a-root-against-the-state-backend),
  steps 1 to 3, with the same inputs as the build, the alerting inputs unset and
  `worker_capacity_enabled` unset or `true`, its default. Arriving from step 6 of
  [Build only the retained baseline](#build-only-the-retained-baseline), it already is. Then
  return to this list.
- [ ] The account is confirmed first with the account check, as the **Shell** item of
  [Before you start](#before-you-start) describes; continue only on `ACCOUNT_MATCH=PASS`, then
  return to this list. `terraform state list` reads only the backend, so the provider's account
  check does not guard it.

**Safety and authority.** Read-only. The plan writes no state and is never applied. No approval
and no cost.

> **Warning:** Never apply this plan. It has no targets, so applying it would create the 17
> runtime addresses below, the billable runtime. A saved plan applies without a confirmation
> prompt.

**Steps.**

1. List state:

   ```
   terraform state list
   ```

2. Plan with step 1 of
   [Plan to a saved file](terraform-operations.md#plan-to-a-saved-file), in a new `<private-dir>`,
   without targets, following the rule of Plan without taking the state lock for plans that are
   only read: leave out `-lock=false` unless no other writer can be active on the root. This plan
   is never applied. Name `<plan-file>` so that it cannot be mistaken for a plan to apply, for
   example `<private-dir>/never-apply.tfplan`.

   ```
   AWS_PROFILE=<profile> terraform plan -lock=false -input=false -no-color -detailed-exitcode -out=<plan-file>
   echo $?
   ```

   PASS: exit 2 and the saved plan at `<plan-file>`. Then continue at step 3.

3. Run steps 1 to 4 of [Review the saved plan](terraform-operations.md#review-the-saved-plan);
   the runtime table under **Expected result** is the reviewed list, each address a `create`.
   PASS: `applyable` and `complete` `true`, `errored` `false`, exactly the 17 `create` lines, and
   an empty drift list. Then run the alerting check here:

   ```
   jq -r '.variables | "alerting_campaign_enabled=\(.alerting_campaign_enabled.value) alerting_email_subscription_enabled=\(.alerting_email_subscription_enabled.value)"' <plan-json>
   ```

**Expected result.** Step 1 prints exactly these 21 addresses:

| Retained class | Addresses |
|---|---|
| Network (14) | `aws_vpc.dev`, `aws_subnet.private_a`, `aws_subnet.private_b`, `aws_subnet.public_a`, `aws_subnet.public_b`, `aws_internet_gateway.dev`, `aws_route_table.public`, `aws_route.public_default`, `aws_route_table.private`, `aws_route_table_association.public_a`, `aws_route_table_association.public_b`, `aws_route_table_association.private_a`, `aws_route_table_association.private_b`, `aws_vpc_endpoint.s3` |
| Identity, secrets and configuration (7) | `aws_secretsmanager_secret.workload`, `aws_secretsmanager_secret.argocd_gitops_deploy_key`, `aws_ssm_parameter.workload`, `aws_iam_role.workload`, `aws_iam_role_policy.workload`, `aws_iam_role.external_secrets`, `aws_iam_role_policy.external_secrets` |

Step 2 exits 2 and the plan text contains the summary line
`Plan: 17 to add, 0 to change, 0 to destroy.`. In step 3, `applyable` and `complete` are `true`
and `errored` is `false`; the action list is exactly
17 `create` lines, one for each runtime address below; the drift list is empty; and the alerting
check prints `alerting_campaign_enabled=false alerting_email_subscription_enabled=false`.

| Runtime class | Addresses |
|---|---|
| Created only when `worker_capacity_enabled` is true (10) | `aws_eip.nat[0]`, `aws_nat_gateway.dev[0]`, `aws_route.private_default[0]`, `aws_iam_role.eks_node[0]`, `aws_iam_role_policy_attachment.eks_node_worker[0]`, `aws_iam_role_policy_attachment.eks_node_cni[0]`, `aws_iam_role_policy_attachment.eks_node_ecr_pull[0]`, `aws_launch_template.eks_node[0]`, `aws_eks_node_group.dev[0]`, `aws_eks_pod_identity_association.external_secrets[0]` |
| Created by every apply that is not targeted (7) | `aws_iam_role.eks_cluster`, `aws_iam_role_policy_attachment.eks_cluster_policy`, `aws_eks_cluster.dev`, `aws_eks_addon.vpc_cni`, `aws_eks_addon.coredns`, `aws_eks_addon.kube_proxy`, `aws_eks_addon.pod_identity_agent` |

With `worker_capacity_enabled = false`, the plan shows 7 to add: the second row only. The
five alerting-campaign addresses ([Alerting](../../terraform/dev/README.md#alerting)) appear
in neither list while their inputs are unset.

**PASS when.**

- [ ] The state listing equals the 21 addresses, with none extra and none missing.
- [ ] The planned creations equal the 17.
- [ ] The drift list is empty, and both alerting variables are `false`.

**STOP if.**

- Any address in state outside the 21, or any of the 21 missing.
- Any runtime address already in state: a runtime is live or a teardown was incomplete
  ([Runtime Validation](../validation/runtime-validation.md)).
- Any update, destroy or replacement in the plan.
- Either alerting variable `true`.
- Any drift line other than the route-table case under If it fails.

**If it fails.**

- **Route-table drift.** If the drift list is exactly `aws_route_table.private` with the
  attribute `route`, and that address has a `no-op` action, state still holds the `0.0.0.0/0`
  NAT route that a targeted runtime teardown removed from AWS. The plan text does not show it: on
  2026-09-22 the ordinary plan printed 17 to add and no `Objects have changed outside of
  Terraform` note while its JSON carried the entry. Detect and reconcile it with the refresh-only
  procedures [Detect state drift](terraform-operations.md#detect-state-drift) and
  [Reconcile explained state-only drift](terraform-operations.md#reconcile-explained-state-only-drift),
  then repeat this procedure. The reconciliation writes state, so its refresh-only plan needs the
  owner's approval.
- **An alerting variable is `true`.** Correct the private `terraform.tfvars`, both the copy in
  `<inputs-dir>` and the copy that
  [initialization](terraform-operations.md#initialize-a-root-against-the-state-backend) installed
  in `terraform/dev`, and repeat from step 2 in a new `<private-dir>`. A stale subscription flag
  and endpoint left from an alerting window were found this way on 2026-09-22.
- **7 to add, the second runtime row only.** `worker_capacity_enabled` is `false`, so the
  prerequisite above is not met. Unset it in both copies of `terraform.tfvars`, or set it to
  `true`, and repeat from step 2 in a new `<private-dir>`.
- **A runtime address in state.** A runtime is live or a teardown was incomplete;
  [Runtime Validation](../validation/runtime-validation.md) summarizes the windows that ran. No
  procedure in this suite tears down a runtime. Keep the output; work stays stopped until a
  reviewed decision is taken under explicit approval ([When to stop](README.md#when-to-stop)).
- **Any other address in state, or any of the 21 missing.** No procedure exists for it,
  including the 14 network addresses alone after a build that stopped between its stages. Keep
  the listing; work stays stopped as [When to stop](README.md#when-to-stop) describes.

**Evidence to keep.** The state listing and the review output, privately: the plan text
carries resource identifiers and ARNs.

**Next step.** [Read back the retained network](#read-back-the-retained-network).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22) |
| Published form | not executed as written (derived from the retained 2026-09-22 state listing and from a reviewed private check that read the saved plans' JSON for the create set, drift and the alerting variables; the review filters are those of [terraform-operations.md](terraform-operations.md) and the alerting check is derived from that private check) |
| Evidence basis | [Lifecycle and current state](../../terraform/dev/README.md#lifecycle-and-current-state); commit `c6c4230`, which put ten runtime addresses behind `worker_capacity_enabled`. Retained private evidence of 2026-09-22 on the current configuration: a state listing of exactly the 21 retained addresses; a first ordinary plan held by the private check on two conditions, a stale alerting input and the route-table drift under Failure handling, while its text still read 17 to add and carried no drift note; and, after both were resolved, an ordinary plan of 17 to add naming the 17 runtime addresses below and an observation-mode plan of 7 to add, both passing. Plans at the opening of earlier windows, on 2026-08-26, 2026-09-10 and 2026-09-11, measured the same 21 unchanged and 17 to add on earlier revisions of the root, and their retained JSON carries the same route-table drift entry |
| Authority | none (read-only; the plan writes no state and is never applied) |
| Cost | none |

In the Evidence basis, "Failure handling" is this procedure's **If it fails**, and the 17 runtime
addresses are those in the runtime table under **Expected result**.

**Known limitations.** Not re-measured since the datastore instance was created on 2026-09-24.
No resource in this root reads the datastore, so the result is expected to be unchanged, but
that is unmeasured. Every recorded run used the administrator permission set; running this
under the read-only permission set has not been exercised.

### Read back the retained network

**Validation:** EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-10); DESIGNED-NOT-EXECUTED (DNS attributes, gateway attachment, main route table) · **Published command form:** not executed as written

**What this does.** Verifies from AWS, not from state, that the retained network matches the
README. It finds the VPC by its `Name` tag, then reads the VPC, its subnets, the internet
gateway, the route tables and the S3 gateway endpoint.

**Before you start.**

- [ ] A session on the project account, confirmed with the account check as the **Shell** item of
  [Before you start](#before-you-start) describes; continue only on `ACCOUNT_MATCH=PASS`, then
  return to this list.
- [ ] No runtime window open: during a window the private route table also carries the NAT route.

**Safety and authority.** Read-only. No approval and no cost.

**Steps.**

1. Resolve the VPC, confirm it is unique, and read it. `VPC_ID` stays set for the later steps:

   ```
   VPC_ID=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=cloud-platform-reference-dev-vpc \
     --query 'Vpcs[].VpcId' --output text)
   echo "$VPC_ID" | wc -w
   aws ec2 describe-vpcs --vpc-ids "$VPC_ID" \
     --query 'Vpcs[].{cidr:CidrBlock,state:State,isDefault:IsDefault,tags:sort_by(Tags,&Key)[].join(`"="`,[Key,Value])}' --output json
   aws ec2 describe-vpc-attribute --vpc-id "$VPC_ID" --attribute enableDnsSupport --query 'EnableDnsSupport.Value'
   aws ec2 describe-vpc-attribute --vpc-id "$VPC_ID" --attribute enableDnsHostnames --query 'EnableDnsHostnames.Value'
   ```

2. Subnets:

   ```
   aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" \
     --query 'sort_by(Subnets,&CidrBlock)[].{name:Tags[?Key==`Name`]|[0].Value,cidr:CidrBlock,zone:AvailabilityZone,zoneId:AvailabilityZoneId,publicIpOnLaunch:MapPublicIpOnLaunch,roleTag:Tags[?starts_with(Key,`"kubernetes.io/role/"`)]|[0].Key,tags:sort_by(Tags,&Key)[].join(`"="`,[Key,Value])}' --output json
   ```

3. Internet gateway:

   ```
   aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values="$VPC_ID" \
     --query 'InternetGateways[].{name:Tags[?Key==`Name`]|[0].Value,attachment:Attachments[0].State}' --output table
   ```

4. Route tables:

   ```
   aws ec2 describe-route-tables --filters Name=vpc-id,Values="$VPC_ID" \
     --query 'RouteTables[].{name:Tags[?Key==`Name`]|[0].Value,main:length(Associations[?Main]),subnets:length(Associations[?SubnetId]),routes:Routes[].join(`" "`,[DestinationCidrBlock || DestinationPrefixListId,GatewayId || NatGatewayId || `"none"`,State])}' --output json
   ```

5. S3 gateway endpoint:

   ```
   aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values="$VPC_ID" \
     --query 'VpcEndpoints[].{service:ServiceName,type:VpcEndpointType,state:State,routeTables:length(RouteTableIds)}' --output table
   ```

**Expected result.**

| Object | Expected |
|---|---|
| VPC | Step 1 counts exactly one. `10.20.0.0/16`, `available`, not the default VPC; both DNS attributes `true` |
| Subnets | Exactly four, matching the address plan in CIDR and zone name; `publicIpOnLaunch` false on all four; `kubernetes.io/role/internal-elb` on the two private subnets and `kubernetes.io/role/elb` on the two public ones; zone IDs as recorded at the zone check |
| Internet gateway | Exactly one, `cloud-platform-reference-dev-igw`, attachment `available` |
| Route tables | Three. `cloud-platform-reference-dev-public-rt`: two subnets, `10.20.0.0/16 local active` and `0.0.0.0/0 igw-… active`. `cloud-platform-reference-dev-private-rt`: two subnets, `10.20.0.0/16 local active` and a prefix-list route `pl-… vpce-… active`, and no `0.0.0.0/0` route. The unnamed table AWS created with the VPC: `main` 1, no subnets, the local route only |
| Endpoint | One: `com.amazonaws.us-east-1.s3`, `Gateway`, `available`, one route table, which step 4 shows is the private table |
| Tags | On the VPC and each subnet: `Component=network`, `Environment=dev`, `Lifecycle=ephemeral`, `ManagedBy=terraform`, `Owner=platform-engineer`, `Project=cloud-platform-reference` and `Name`, plus the role tag on each subnet. `Lifecycle=ephemeral` is the environment-lifecycle default; it does not mean the network is destroyed at the end of each working session ([Tagging](../../terraform/dev/README.md#tagging)) |

**PASS when.**

- [ ] Every row of the expected-result table matches.

**STOP if.**

- A VPC count other than one.
- A fifth subnet.
- A subnet associated with the main table.
- A `0.0.0.0/0` route in the private table outside a runtime window, whatever its state.
- Any other value that differs from the table.

**If it fails.** A difference from the README is a change made outside Terraform. Record it and
stop. Only a difference whose cause is an explained class of
[Reconcile explained state-only drift](terraform-operations.md#reconcile-explained-state-only-drift)
has a published path, which records it in state under its own approval and changes nothing in AWS;
on this root that is the route-table drift. For any other difference no procedure exists, and work
stays stopped until a reviewed decision is taken under explicit approval
([When to stop](README.md#when-to-stop)).

**Evidence to keep.** The command output, privately; it carries resource identifiers.

**Next step.** [Read back the two Secrets Manager entries](#read-back-the-two-secrets-manager-entries),
unless another procedure sent you here: then return to it.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-10) for the checks listed under Evidence basis; DESIGNED-NOT-EXECUTED (never) for the VPC DNS attributes, the internet gateway's attachment state and the main route table |
| Published form | not executed as written (the 2026-08-10 read-back commands were not retained; the VPC and endpoint queries are derived from retained 2026-09-10 `describe-vpcs` and `describe-vpc-endpoints` output taken without filters or projections) |
| Evidence basis | [Address plan](../../terraform/dev/README.md#address-plan), [Routing](../../terraform/dev/README.md#routing), [The S3 gateway endpoint](../../terraform/dev/README.md#the-s3-gateway-endpoint), [Tagging](../../terraform/dev/README.md#tagging). The recorded read-back of 2026-08-10, after the build and its `Name` tags, covered public-address assignment off on all four subnets, the public default route, no private default route, the S3 prefix-list route on the private table, four explicit associations, the six tags, the subnet role tags, the `Name` tags, the subnets' zone IDs, and no NAT gateway, Elastic IP or EKS cluster; it is recorded without retained output. No record shows the VPC DNS attributes, the internet gateway's attachment state or the main route table being read. Retained private evidence of 2026-09-10 covers only the VPC (CIDR, state and its seven tags), the endpoint (S3 gateway, available, one route table) and a summary line on the subnet count (see Known limitations) |
| Authority | none (read-only) |
| Cost | none |

**Known limitations.**

- No full read-back of the network has ever been retained; the 2026-08-10 read-back is
  recorded without output.
- The last retained summary of this network, on 2026-09-10, recorded five non-default subnets
  against the four declared, with no raw subnet output. The difference is unexplained and stays
  unresolved until a subnet read-back runs.
- The datastore adds resources to this VPC that this procedure does not look at;
  [Verify the retained side with the datastore present](#verify-the-retained-side-with-the-datastore-present)
  covers them.

**Next gate.** The next run of this procedure, which settles the 2026-09-10 subnet count.

### Read back the two Secrets Manager entries

**Validation:** AWS-VALIDATED (2026-09-10) · **Published command form:** not executed as written

**What this does.** Confirms that both entries exist, are not scheduled for deletion, carry the
retained-resource tags, and hold the number of versions you expect, without reading any value.
[Build only the retained baseline](#build-only-the-retained-baseline) runs it in step 6 and in
its failure handling.

**Before you start.**

- [ ] The shell from [Before you start](#before-you-start), with the account check passed.

**Safety and authority.** Read-only, metadata only: no secret value is read. Negligible cost: two
Secrets Manager API requests.

**Steps.**

1. Read the metadata of both entries:

   ```
   for s in cloud-platform-reference-dev-workload-secret cloud-platform-reference-dev-argocd-gitops-deploy-key; do
     aws secretsmanager describe-secret --secret-id "$s" \
       --query '{name:Name,deletedDate:DeletedDate,rotation:RotationEnabled,versions:length(keys(VersionIdsToStages || `{}`)),stages:sort(values(VersionIdsToStages || `{}`)[]),tags:sort_by(Tags,&Key)[].join(`"="`,[Key,Value])}' --output json
   done
   ```

**Expected result.** For each entry: `deletedDate` null; `rotation` null, meaning rotation is
not configured; tags `Component=identity`, `Environment=dev`, `Lifecycle=persistent`,
`ManagedBy=terraform`, `Owner=platform-engineer` and `Project=cloud-platform-reference`. After
a fresh build, `versions` is 0 and `stages` is empty until a value is placed. In the reference
environment on 2026-09-10, the workload secret held two labelled versions, `AWSCURRENT` and
`AWSPREVIOUS` (synthetic validation material after one rotation), and the deploy key held one,
`AWSCURRENT`; the 2026-09-22 listing gave the same counts.

**PASS when.**

- [ ] Both entries exist, with `deletedDate` null and `rotation` null.
- [ ] Both carry the six tags.
- [ ] Each version count equals the last read made with this projection, or a recorded placement
  or rotation explains the difference.

**STOP if.**

- A missing entry.
- A `deletedDate`, which means the entry is scheduled for deletion and its recovery has not been
  exercised.
- A version count that differs from the last read made with this projection, with no recorded
  placement or rotation to explain it.

**If it fails.** No procedure exists for any of these. Deletion and recovery of these entries
have never been exercised ([Not yet exercised](#not-yet-exercised)). Keep the output and take no
further action; work stays stopped until a reviewed decision is taken under explicit approval
([When to stop](README.md#when-to-stop)).

**Evidence to keep.** The output, privately.

**Next step.** Return to the procedure that sent you here. After a build, that is building the
datastore root ([dev-datastore.md](dev-datastore.md)). Otherwise, once the datastore root is
built, [Verify the retained side with the datastore present](#verify-the-retained-side-with-the-datastore-present).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-10) |
| Published form | not executed as written (derived from the retained 2026-09-10 `describe-secret` output for both names, taken without a projection) |
| Evidence basis | [Identity, secrets and configuration](../../terraform/dev/README.md#identity-secrets-and-configuration); [`secrets.tf`](../../terraform/dev/secrets.tf). Retained private evidence: the 2026-09-10 metadata of both entries (the six tags with `Component=identity` and `Lifecycle=persistent`, no deletion scheduled, no rotation configured, version stages). Version counts were read again on 2026-09-22 with a version listing that also counts versions without a staging label; it matches this projection only while every version carries a label |
| Authority | none (read-only; metadata only) |
| Cost | Negligible: two Secrets Manager API requests |

**Known limitations.** The seven-day recovery window is a Terraform deletion setting
(`recovery_window_in_days`) that AWS does not return, so it cannot be read back before a
deletion. Deletion and recovery have never been exercised. This projection counts only
versions that carry a staging label.

### Verify the retained side with the datastore present

**Validation:** DESIGNED-NOT-EXECUTED (never) · **Published command form:** not executed as written

**What this does.** Since 2026-09-22 the datastore's security group, and since 2026-09-24 the
instance's network interface in a private subnet, sit inside this VPC. The earlier
retained-side expectations no longer hold: only the default security group held until
2026-09-22, and no network interface held until 2026-09-24. A retained-side check now has to
tell the datastore's footprint apart from runtime residue, meaning resources a runtime window
left behind.

It lists the VPC's security groups and network interfaces, checks the datastore group's rules
with the datastore runbook, and repeats the network read-back.

**Before you start.**

- [ ] The datastore's security group and instance exist ([dev-datastore.md](dev-datastore.md));
  the expected result assumes both.
- [ ] No runtime window open.
- [ ] `VPC_ID` resolved as in [Read back the retained network](#read-back-the-retained-network).

**Safety and authority.** Read-only. No approval and no cost.

**Steps.**

1. Security groups in the VPC:

   ```
   aws ec2 describe-security-groups --filters Name=vpc-id,Values="$VPC_ID" \
     --query 'sort(SecurityGroups[].GroupName)' --output text
   ```

2. The datastore group's rules: run
   [Read back the network boundary](dev-datastore.md#read-back-the-network-boundary) in
   [dev-datastore.md](dev-datastore.md).
3. Network interfaces in the VPC:

   ```
   aws ec2 describe-network-interfaces --filters Name=vpc-id,Values="$VPC_ID" \
     --query 'NetworkInterfaces[].{type:InterfaceType,requesterManaged:RequesterManaged,description:Description,zone:AvailabilityZone,ip:PrivateIpAddress,groups:Groups[].GroupName,status:Status}' --output json
   ```

4. Run [Read back the retained network](#read-back-the-retained-network). The datastore
   changes none of its expected values.

**Expected result.**

- Step 1 prints exactly two names, `cloud-platform-reference-dev-datastore` and `default`.
- Step 2 passes as [dev-datastore.md](dev-datastore.md) describes.
- Network interfaces: only the datastore's, one for the single-AZ instance, with an address
  inside `10.20.0.0/20` or `10.20.16.0/20`, and matching the datastore-interface classification
  that the [orphan census](cost-and-residue.md#run-the-orphan-census) asserts:
  `requesterManaged` `true`, `description` `RDSNetworkInterface`, and exactly one group, the
  datastore's security group `cloud-platform-reference-dev-datastore`. That classification has
  passed offline controls only and has never run against a live instance. `type` is recorded,
  not asserted.
- Step 4 passes unchanged.

**PASS when.**

- [ ] Step 1 prints exactly the two expected security groups.
- [ ] Step 2 passes.
- [ ] The only network interface is the datastore's, as described above.
- [ ] Step 4 passes.

**STOP if.**

- Any other security group or network interface between windows.
- A datastore interface with values other than those above, attached to any other group, or
  with an address outside the private ranges.
- A failure of the rule check in step 2.

**If it fails.**

- **Another security group or network interface between windows.** Treat it as possible runtime
  residue and run the [orphan census](cost-and-residue.md#run-the-orphan-census).
- **Any other STOP.** This runbook has no recovery procedure for it. Keep the output and stay
  stopped until a reviewed decision is taken under explicit approval
  ([When to stop](README.md#when-to-stop)).

**Evidence to keep.** The command output, privately. On the first run, the observed fields of
the datastore interface, so later runs can assert them. The first run confirms the census
classification or corrects it in [cost-and-residue.md](cost-and-residue.md).

**Next step.** If another runbook sent you here, return to the step that sent you. None in this
runbook. The first run of this procedure is due at the next retained-side check or at the
teardown of the next runtime window.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | DESIGNED-NOT-EXECUTED (never) |
| Published form | not executed as written (never run) |
| Evidence basis | [`terraform/dev-datastore/network.tf`](../../terraform/dev-datastore/network.tf); [datastore What it creates](../../terraform/dev-datastore/README.md#what-it-creates) and [Boundary](../../terraform/dev-datastore/README.md#boundary). Retained private evidence of 2026-09-10 shows the Dev VPC holding only its default security group and no network interface; of 2026-09-22, one datastore security group and still no interface, before the instance existed. The instance was created on 2026-09-24, and CloudTrail recorded the RDS service creating one network interface for it. That interface has not been read |
| Authority | none (read-only) |
| Cost | none |

**Known limitations.** Never run. The datastore interface is expected to carry no project tags,
so a scan that selects by tag will not find it; this procedure identifies it by its security
group instead. That expectation is unobserved too. The datastore root's own state is not
planned here ([dev-datastore.md](dev-datastore.md)).

## Not yet exercised

The labels are those defined in the [runbook index](README.md#validation-labels).

| Item | Label | What exists |
|---|---|---|
| [Check the zone mapping before the first build](#check-the-zone-mapping-before-the-first-build) | DESIGNED-NOT-EXECUTED | The procedure above. The reference account's zone IDs were read back only after the build, and the node-type check was recorded before the first runtime apply without a command |
| [Verify the retained side with the datastore present](#verify-the-retained-side-with-the-datastore-present) | DESIGNED-NOT-EXECUTED | The procedure above |
| [Build only the retained baseline](#build-only-the-retained-baseline): the plans and applies with the two target lists, and the alerting check's `jq` form | DESIGNED-NOT-EXECUTED | The procedure above. Neither stage has run with these target lists, the alerting check has not run in this form, and the sequence has never run end to end |
| [Read back the retained network](#read-back-the-retained-network): the VPC DNS attributes, the internet gateway's attachment state and the main route table | DESIGNED-NOT-EXECUTED | The queries in that procedure. No record shows them read |
| AWS read-back of the Parameter Store entry, the two Pod Identity roles and their inline policies | UNEXERCISED | Their trust, policy scope and tags were read back when they were created, between 2026-08-12 and 2026-08-17 (EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE). Retained private evidence of 2026-09-10 holds only a parameter listing and the role names. No read-back procedure is published |
| Recover from a partial apply of this root | UNEXERCISED | A partial runtime apply was recovered once, on 2026-08-10, for an earlier shape of the root whose retained set was the 14 network addresses, with no secrets or identities (EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE): its commands were not retained and no complete orphan scan was claimed. Recovering today's root while preserving its 21 retained addresses, including both Secrets Manager entries, has not been exercised. Read-only inspection after an interrupted apply is in [terraform-operations.md](terraform-operations.md) |
| Decommission the Dev network | UNEXERCISED | The order only: no runtime present; the datastore root decommissioned first ([datastore Decommission](../../terraform/dev-datastore/README.md#decommission)); then this root's retained set. No reviewed command-level procedure exists |
| Change the address plan, the zones or the network `Name` tags after the first build | UNEXERCISED | Changing a subnet's CIDR block or zone replaces the subnet. The datastore root looks up the VPC and the private subnets by `Name` tag and derives its ingress rules from their CIDR blocks, so any of these changes also changes or breaks that root's plan |
| Delete and recover the two Secrets Manager entries within the recovery window | UNEXERCISED | Required by [ADR-0011](../decisions/0011-define-the-backup-and-recovery-model.md); the seven-day window is configured and nothing more |
| Check the datastore root for drift after a network or runtime operation | UNEXERCISED | Retained private evidence of 2026-09-22 compared that root's state serial, lineage and address list before and after operations on this root; no refresh-only plan of the datastore root has been part of any network or runtime procedure |

## Reproducibility gaps

What a new engineer cannot reproduce from the public repositories today.

| What cannot be reproduced | Public contract that exists | Later public procedure or tool |
|---|---|---|
| Placing the Dev workload secret value and the deploy key's private key. Both are placed out of band after the containers exist, never through Terraform; no public placement procedure exists, and the datastore master-value placement does not cover them | The two empty containers in [`secrets.tf`](../../terraform/dev/secrets.tf) and [Identity, secrets and configuration](../../terraform/dev/README.md#identity-secrets-and-configuration); the metadata check in [Read back the two Secrets Manager entries](#read-back-the-two-secrets-manager-entries); the deploy key's role in [GitOps Delivery](../implementation/gitops-delivery.md#4-bootstrap-and-reconciliation) | Needed: a public placement procedure for both values, before a runtime window uses them |
| Decommissioning the Dev network. Only the order is published, and an untargeted destroy is unsafe | The order in [Not yet exercised](#not-yet-exercised) and [datastore Decommission](../../terraform/dev-datastore/README.md#decommission) | Needed: a reviewed command-level decommission procedure |
| Recovering a partial apply of this root while preserving its 21 retained addresses. The one earlier recovery, for an older shape of the root, kept no commands | Read-only inspection in [Stop after a failed or interrupted apply](terraform-operations.md#stop-after-a-failed-or-interrupted-apply) | Needed: a reviewed recovery procedure for this root |
| Deleting and recovering the two Secrets Manager entries within their recovery window, which [ADR-0011](../decisions/0011-define-the-backup-and-recovery-model.md) requires | The seven-day `recovery_window_in_days` in [`secrets.tf`](../../terraform/dev/secrets.tf); AWS does not return it, so it cannot be read back before a deletion | Needed: a deletion-and-recovery procedure and its first exercise |
| Reading back the Parameter Store entry, the two Pod Identity roles and their inline policies from AWS | Their configuration in [Identity, secrets and configuration](../../terraform/dev/README.md#identity-secrets-and-configuration); their addresses in the state listing of [Confirm the retained and runtime split](#confirm-the-retained-and-runtime-split) | Needed: a read-back procedure |
| Changing the address plan, the zones or the network `Name` tags after the first build. The change replaces subnets and changes or breaks the datastore root's plan | Before the first build only: the zone change under [Check the zone mapping before the first build](#check-the-zone-mapping-before-the-first-build), itself never exercised | Needed only if a built environment must change them: a reviewed procedure that covers the datastore root's plan too |
| The command forms that actually ran. The recorded plan checks ran through reviewed private checks that are not published, and every procedure on this page is published in a form that was not executed as written | The command forms, target lists and expected results on this page, and the review filters in [Review the saved plan](terraform-operations.md#review-the-saved-plan) | No new tool: the published forms need a first run as written |

## Background prerequisites

- **Zone mapping.** Your account's mapping of `us-east-1a` and `us-east-1b` to zone IDs, checked
  for EKS support, the node instance type and the datastore engine.
  [Check the zone mapping before the first build](#check-the-zone-mapping-before-the-first-build)
  produces it.
- **Secret values.** A value for the Dev workload secret (the reference environment has only
  held synthetic validation material there) and the private key of a read-only deploy key for
  your own desired-state repository
  ([GitOps Delivery](../implementation/gitops-delivery.md#4-bootstrap-and-reconciliation)).
  Both are placed out of band after the containers exist, never through Terraform. No public
  placement procedure exists for either; the master-value placement in
  [dev-datastore.md](dev-datastore.md) does not cover them. A runtime window needs them; this
  runbook does not.
