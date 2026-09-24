# Dev Network Runbook

## Scope

This runbook operates the retained side of [`terraform/dev`](../../terraform/dev/README.md):
checking the zone choice before a first build, building only the retained baseline, confirming
the split between retained and runtime addresses, reading the network and the environment's
two Secrets Manager entries back from AWS, and checking what the Dev datastore now places
inside this network.

It does not repeat what the root creates or why. The resources, the address plan, the routing,
the S3 gateway endpoint and the tagging are in the root README
([What it creates](../../terraform/dev/README.md#what-it-creates),
[Address plan](../../terraform/dev/README.md#address-plan),
[Routing](../../terraform/dev/README.md#routing),
[The S3 gateway endpoint](../../terraform/dev/README.md#the-s3-gateway-endpoint),
[Tagging](../../terraform/dev/README.md#tagging)), and the retained, runtime and
alerting classes with their counts are in
[Lifecycle and current state](../../terraform/dev/README.md#lifecycle-and-current-state).
This runbook adds the measured address lists and the procedures around them.

Linked rather than repeated:

- Runtime windows, meaning runtime creation, targeted teardown and the post-teardown census:
  [Runtime Validation](../validation/runtime-validation.md).
- The workflow every root shares, meaning static checks, backend initialisation, saved plans,
  their review and binding, applies, locks, drift detection and reconciliation, and
  interrupted applies: [terraform-operations.md](terraform-operations.md).
- The datastore root: [dev-datastore.md](dev-datastore.md) and its
  [README](../../terraform/dev-datastore/README.md).
- The budget, pricing re-checks, the orphan census and the weekly cost review:
  [cost-and-residue.md](cost-and-residue.md).
- Capturing and keeping evidence: [evidence-handling.md](evidence-handling.md).
- Sign-in and the account check: [operator-access.md](operator-access.md).

Three rules hold for every command in this root:

- A plain `terraform apply` here creates the billable runtime as well as the retained
  baseline: the EKS control plane, the NAT gateway with its Elastic IP, and two `m6a.large`
  nodes ([Estimated planning baseline](../../terraform/dev/README.md#estimated-planning-baseline)).
  `worker_capacity_enabled = false` still creates the EKS control plane.
- Never run an untargeted `terraform destroy` here. It removes the retained baseline,
  schedules both Secrets Manager entries for deletion, and tries to remove a VPC and subnets
  that the datastore's resources occupy.
- Every plan needs `allowed_account_id` and `operator_cidr`, including network-only and
  read-only plans ([Input](../../terraform/dev/README.md#input)). Leave the alerting inputs
  unset. A set alerting flag does not change the plan counts, so the saved-plan procedures
  below check the variables themselves.

The datastore root is coupled to this network. It finds the Dev VPC and the two private
subnets by their `Name` tags, never through this root's state; its security group admits TCP
5432 from the two private subnet ranges; and its subnet group, security group and instance
network interface sit inside this VPC. Renaming or re-addressing those resources therefore
changes or breaks the datastore root's plan, and the datastore root is destroyed before this
network ([datastore Decommission](../../terraform/dev-datastore/README.md#decommission)).
While a runtime window is open, every node and pod in the private subnets can reach the
datastore on TCP 5432 ([datastore Boundary](../../terraform/dev-datastore/README.md#boundary)).

Conventions: commands run from `terraform/dev`, in a shell with `AWS_PROFILE=<profile>` and
`AWS_REGION=us-east-1` exported, where `<profile>` is the administrator profile from
[operator-access.md](operator-access.md). `<private-dir>`, `<plan-file>` and `<plan-json>` are
as defined in [terraform-operations.md](terraform-operations.md). Dates are UTC. No command here
reads a secret value.

## Procedures

### Check the zone mapping before the first build

| Field | Value |
|---|---|
| Validation status | DESIGNED-NOT-EXECUTED (never) |
| Published form | not executed as written (never run; derived from the README's requirement that the node type be checked in both zones, and from the datastore's capacity prerequisite) |
| Evidence basis | [Address plan](../../terraform/dev/README.md#address-plan). No check of the zone mapping, EKS zone support or the datastore engine before the first build is recorded. What is recorded are facts about the reference account, not runs of this check, and none has retained command output: the built subnets' zone IDs were read back after the network was built, on 2026-08-10, and `m6a.large` availability in both zone IDs was recorded as satisfied before the first runtime apply. Retained private evidence of later runtime windows shows the cluster and nodes created in these subnets; that is an outcome, not this check |
| Authority | none (read-only) |
| Cost | none |

**Purpose.** [`networking.tf`](../../terraform/dev/networking.tf) hard-codes the zone names
`us-east-1a` and `us-east-1b`. A zone name maps to a physical zone per account, so the same
names can land in different physical zones in your account. EKS, the node instance type and the
datastore engine all have to be available in the zones you actually get.

**Preconditions.** A session on the project account, confirmed as in
[operator-access.md](operator-access.md). The network has not been built yet; after the first
apply, a zone change replaces subnets (see [Not yet exercised](#not-yet-exercised)).

**Procedure.**

1. Map the two names to zone IDs:

   ```
   aws ec2 describe-availability-zones --zone-names us-east-1a us-east-1b \
     --query 'AvailabilityZones[].{name:ZoneName,zoneId:ZoneId,state:State}' --output table
   ```

2. Check both zone IDs against the current Amazon EKS documentation on zone IDs that cannot
   hold cluster subnets. AWS maintains that list; this step has no command.
3. Check that the node instance type is offered in both zone IDs:

   ```
   aws ec2 describe-instance-type-offerings --location-type availability-zone-id \
     --filters Name=instance-type,Values=m6a.large Name=location,Values=<zone-id-a>,<zone-id-b> \
     --query 'sort(InstanceTypeOfferings[].Location)' --output text
   ```

4. Check that the datastore engine can be ordered in both zone names, with the engine check of
   the pre-apply gate in [dev-datastore.md](dev-datastore.md). The datastore reuses the two
   private subnets, so the zones chosen here are its zones too.

**Expected result.** Two rows in step 1, both `available`; neither zone ID is excluded by the
EKS documentation; step 3 prints both zone IDs; step 4 lists both zone names.

**STOP conditions.** A zone that is not `available`, a zone ID EKS excludes, fewer than two
zone IDs in step 3, or a zone name missing from step 4.

**Failure handling.** Choose two us-east-1 zone names whose IDs pass all four checks, and change
the four `availability_zone` arguments in `networking.tf` as a reviewed change before the first
plan: `aws_subnet.private_a` and `aws_subnet.public_a` share one zone, `aws_subnet.private_b`
and `aws_subnet.public_b` the other. The README's
[What it creates](../../terraform/dev/README.md#what-it-creates) and
[Address plan](../../terraform/dev/README.md#address-plan), and the zone names expected by
[Read back the retained network](#read-back-the-retained-network), would then differ from
your build. This path has never been exercised.

**Evidence to retain.** The name-to-ID mapping. Later read-backs compare the subnets' zone IDs
against it.

### Build only the retained baseline

| Field | Value |
|---|---|
| Validation status | COMPOSED FROM AWS-VALIDATED STEPS; END-TO-END COMMAND FORM NOT YET EXERCISED (end to end: never), except these parts: DESIGNED-NOT-EXECUTED (never) for the plans and applies with the two target lists and for the zone-mapping precondition; for step 6's network read-back, EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-10) for the checks that procedure lists and DESIGNED-NOT-EXECUTED (never) for the rest |
| Published form | not executed as written (the two target lists are derived from how the retained set was first created and from the recorded 21-address set; the plan, review, binding and apply forms are those of [terraform-operations.md](terraform-operations.md); this sequence has never run) |
| Evidence basis | AWS-validated steps it composes, as recorded where they are published: initializing a root, planning to a saved file, reviewing the saved plan, binding it to its hash and to state, and applying it ([terraform-operations.md](terraform-operations.md)); [Confirm the retained and runtime split](#confirm-the-retained-and-runtime-split) and [Read back the two Secrets Manager entries](#read-back-the-two-secrets-manager-entries). Not AWS-validated: [Read back the retained network](#read-back-the-retained-network) (recorded only), [Check the zone mapping before the first build](#check-the-zone-mapping-before-the-first-build) (never run) and saved plans with these target lists (never run). History of the set, from commits `bf8dfd5` and `df05255` (network) and `5cf12a7`, `3485b34` and `d5effce` (identity, secret and configuration resources) on public main: the network was created by one apply of 14 resources on 2026-08-09 or 2026-08-10 (the apply's time was not recorded; its S3 endpoint was created at 00:00 on 2026-08-10), before the root declared any runtime, and then received its `Name` tags in place; the identity, secret and configuration resources were created by three targeted applies between 2026-08-12 and 2026-08-17, against a root that already declared the runtime. Those executions are EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-09 to 2026-08-17). The resulting state, 21 addresses with an ordinary plan of 17 to add, is covered by retained private evidence of 2026-09-22 |
| Authority | Explicit approval of each reviewed saved plan by the account owner before it is applied |
| Cost | About 0.80 USD a month for the two Secrets Manager entries (0.40 USD per secret-month, the us-east-1 list price last read from the AWS Price List on 2026-09-24), prorated from creation. The network, the parameter and the IAM resources carry no charge |

**Purpose.** Create the 21 retained addresses and nothing else. The root has no switch that
builds only them, so the build is two reviewed, targeted stages: the network, then the
identity, secret and configuration resources. The order repeats how the set was first
created and keeps each saved plan to one class; neither stage depends on the other.

**Preconditions.**

- The bootstrap root has created the state bucket.
- The root passes the static checks and is initialized against the backend at the reviewed
  commit, as in [terraform-operations.md](terraform-operations.md).
- No state exists yet under `dev/terraform.tfstate`: inspecting state without writing it, as in
  [terraform-operations.md](terraform-operations.md), lists nothing. For an existing state, use
  [Confirm the retained and runtime split](#confirm-the-retained-and-runtime-split) instead.
- [Check the zone mapping before the first build](#check-the-zone-mapping-before-the-first-build)
  has passed.
- The budget and its alerts are in place, which
  [ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md) requires before the
  first billable resource, and Secrets Manager pricing has been re-checked; both as in
  [cost-and-residue.md](cost-and-residue.md).

**Inputs.** `backend.hcl`; `terraform.tfvars` with `allowed_account_id` and `operator_cidr` and
the alerting inputs unset; `<private-dir>`.

**Procedure.**

1. Define the two target lists. An array keeps every target in the command; a broken line
   continuation once dropped the targets from a plan of this root
   ([terraform-operations.md](terraform-operations.md)).

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

2. Plan the network stage with the plan command of
   [terraform-operations.md](terraform-operations.md), with `"${network_targets[@]}"` appended.
3. Review the saved plan as [terraform-operations.md](terraform-operations.md) describes, and
   confirm that the alerting inputs are off. This prints two booleans and no input value:

   ```
   jq -r '.variables | "alerting_campaign_enabled=\(.alerting_campaign_enabled.value) alerting_email_subscription_enabled=\(.alerting_email_subscription_enabled.value)"' <plan-json>
   ```

4. Bind the plan, have it approved, and apply exactly that plan, as
   [terraform-operations.md](terraform-operations.md) describes.
5. Plan the identity, secret and configuration stage the same way, with
   `"${identity_targets[@]}"` appended, in a new `<plan-file>`; review it with the same checks,
   bind it, have it approved and apply it.
6. Run [Confirm the retained and runtime split](#confirm-the-retained-and-runtime-split),
   [Read back the retained network](#read-back-the-retained-network) and
   [Read back the two Secrets Manager entries](#read-back-the-two-secrets-manager-entries).

**Expected result.**

- Step 2 exits 2 and the plan text ends `Plan: 14 to add, 0 to change, 0 to destroy.`, with
  Terraform's warning that resource targeting is in effect.
- Step 3: the action list is exactly 14 `create` lines, one for each network target; the drift
  list and the output changes are empty; the alerting check prints
  `alerting_campaign_enabled=false alerting_email_subscription_enabled=false`. `applyable` is
  `true` and `errored` is `false`, but `complete` is `false`: Terraform marks a targeted plan
  incomplete, as the retained targeted plans of this root show on Terraform 1.15.5. That is the
  one expected difference from the review's criteria.
- Step 5: `Plan: 7 to add, 0 to change, 0 to destroy.`, with seven `create` lines and the same
  checks.
- Each apply reports the same counts as its plan.

**STOP conditions.**

- A listing with any address that stage did not target, or any action other than `create`.
- Any runtime or alerting-campaign address in either plan, or either alerting variable `true`.
- A plan that fails the provider's account check, or a session on another account.
- A state lock error. Follow [terraform-operations.md](terraform-operations.md).
- An apply that errors or is interrupted.

**Failure handling.** After a failed or interrupted apply, stop and inspect read-only as
[terraform-operations.md](terraform-operations.md) describes, before any further apply or
destroy; recovering a partial apply of this root has not been exercised. If a secret cannot be
created because its name is in use, either a secret of that name exists outside this state or
one is scheduled for deletion. Both are a STOP: read its metadata with
[Read back the two Secrets Manager entries](#read-back-the-two-secrets-manager-entries), where a
`deletedDate` marks one scheduled for deletion, and take no further action. No reviewed
recovery exists for either case: restoring within the window, importing, or waiting for the
deletion to complete.

**Recovery / rollback.** No reviewed rollback exists. Removing what this build created is the
decommission, which has not been exercised. Both Secrets Manager entries are configured with a
seven-day recovery window; deletion and recovery have not been exercised (see
[Not yet exercised](#not-yet-exercised)).

**Evidence to retain.** For each stage, what [terraform-operations.md](terraform-operations.md)
lists for a review and an apply, plus the alerting check; and the output of the three
verification procedures. Keep all of it privately, as
[evidence-handling.md](evidence-handling.md) describes. The saved plans never leave
`<private-dir>`: they hold every input value, `operator_cidr` included, in clear text.

**Known limitations.**

- Both Secrets Manager entries are created empty, and placing their values has no public
  procedure (see [Hidden prerequisites](#hidden-prerequisites)).
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

**Next gate.** Build the datastore root ([dev-datastore.md](dev-datastore.md)). The two secret
values are needed before a runtime window uses them.

### Confirm the retained and runtime split

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22) |
| Published form | not executed as written (derived from the retained 2026-09-22 state listing and from a reviewed private check that read the saved plans' JSON for the create set, drift and the alerting variables; the review filters are those of [terraform-operations.md](terraform-operations.md) and the alerting check is derived from that private check) |
| Evidence basis | [Lifecycle and current state](../../terraform/dev/README.md#lifecycle-and-current-state); commit `c6c4230`, which put ten runtime addresses behind `worker_capacity_enabled`. Retained private evidence of 2026-09-22 on the current configuration: a state listing of exactly the 21 retained addresses; a first ordinary plan held by the private check on two conditions, a stale alerting input and the route-table drift under Failure handling, while its text still read 17 to add and carried no drift note; and, after both were resolved, an ordinary plan of 17 to add naming the 17 runtime addresses below and an observation-mode plan of 7 to add, both passing. Plans at the opening of earlier windows, on 2026-08-26, 2026-09-10 and 2026-09-11, measured the same 21 unchanged and 17 to add on earlier revisions of the root, and their retained JSON carries the same route-table drift entry |
| Authority | none (read-only; the plan writes no state and is never applied) |
| Cost | none |

**Purpose.** Show that state holds the retained set and nothing else, that the configuration
still declares exactly the runtime set on top of it, and that state has not drifted from AWS.

**Preconditions.** The root is initialized against the backend
([terraform-operations.md](terraform-operations.md)), with the same inputs as the build and the
alerting inputs unset. `terraform state list` reads only the backend, so the provider's account
check does not guard it: confirm the account first ([operator-access.md](operator-access.md)).

**Procedure.**

1. List state:

   ```
   terraform state list
   ```

2. Plan to a saved file as in [terraform-operations.md](terraform-operations.md), without
   targets, following its rule for plans that are only read. This plan is never applied.
3. Review it with the plan text, completeness, action and drift steps of the review in
   [terraform-operations.md](terraform-operations.md), and run the alerting check:

   ```
   jq -r '.variables | "alerting_campaign_enabled=\(.alerting_campaign_enabled.value) alerting_email_subscription_enabled=\(.alerting_email_subscription_enabled.value)"' <plan-json>
   ```

**Expected result.** Step 1 prints exactly these 21 addresses:

| Retained class | Addresses |
|---|---|
| Network (14) | `aws_vpc.dev`, `aws_subnet.private_a`, `aws_subnet.private_b`, `aws_subnet.public_a`, `aws_subnet.public_b`, `aws_internet_gateway.dev`, `aws_route_table.public`, `aws_route.public_default`, `aws_route_table.private`, `aws_route_table_association.public_a`, `aws_route_table_association.public_b`, `aws_route_table_association.private_a`, `aws_route_table_association.private_b`, `aws_vpc_endpoint.s3` |
| Identity, secrets and configuration (7) | `aws_secretsmanager_secret.workload`, `aws_secretsmanager_secret.argocd_gitops_deploy_key`, `aws_ssm_parameter.workload`, `aws_iam_role.workload`, `aws_iam_role_policy.workload`, `aws_iam_role.external_secrets`, `aws_iam_role_policy.external_secrets` |

Step 2 exits 2 and the plan text ends `Plan: 17 to add, 0 to change, 0 to destroy.`. In step
3, `applyable` and `complete` are `true` and `errored` is `false`; the action list is exactly
17 `create` lines, one for each of these addresses; the drift list is empty; and the alerting
check prints `alerting_campaign_enabled=false alerting_email_subscription_enabled=false`.

| Runtime class | Addresses |
|---|---|
| Created only when `worker_capacity_enabled` is true (10) | `aws_eip.nat[0]`, `aws_nat_gateway.dev[0]`, `aws_route.private_default[0]`, `aws_iam_role.eks_node[0]`, `aws_iam_role_policy_attachment.eks_node_worker[0]`, `aws_iam_role_policy_attachment.eks_node_cni[0]`, `aws_iam_role_policy_attachment.eks_node_ecr_pull[0]`, `aws_launch_template.eks_node[0]`, `aws_eks_node_group.dev[0]`, `aws_eks_pod_identity_association.external_secrets[0]` |
| Created by every apply that is not targeted (7) | `aws_iam_role.eks_cluster`, `aws_iam_role_policy_attachment.eks_cluster_policy`, `aws_eks_cluster.dev`, `aws_eks_addon.vpc_cni`, `aws_eks_addon.coredns`, `aws_eks_addon.kube_proxy`, `aws_eks_addon.pod_identity_agent` |

With `worker_capacity_enabled = false`, the plan shows 7 to add: the second row only. The
five alerting-campaign addresses ([Alerting](../../terraform/dev/README.md#alerting)) appear
in neither list while their inputs are unset.

**Validation.** The state listing equals the 21 addresses, with none extra and none missing,
and the planned creations equal the 17.

**STOP conditions.**

- Any address in state outside the 21, or any of the 21 missing.
- Any runtime address already in state: a runtime is live or a teardown was incomplete
  ([Runtime Validation](../validation/runtime-validation.md)).
- Any update, destroy or replacement in the plan.
- Either alerting variable `true`.
- Any drift line other than the case under Failure handling.

**Failure handling.**

- If the drift list is exactly `aws_route_table.private` with the attribute `route`, and that
  address has a `no-op` action, state still holds the `0.0.0.0/0` NAT route that a targeted
  runtime teardown removed from AWS. The plan text does not show it: on 2026-09-22 the ordinary
  plan printed 17 to add and no `Objects have changed outside of Terraform` note while its JSON
  carried the entry. Detect and reconcile it with the refresh-only procedures in
  [terraform-operations.md](terraform-operations.md), then repeat this procedure.
- If an alerting variable is `true`, correct the private `terraform.tfvars` and repeat from
  step 2. A stale subscription flag and endpoint left from an alerting window were found this
  way on 2026-09-22.

**Evidence to retain.** The state listing and the review output, privately: the plan text
carries resource identifiers and ARNs.

**Known limitations.** Not re-measured since the datastore instance was created on 2026-09-24.
No resource in this root reads the datastore, so the result is expected to be unchanged, but
that is unmeasured. Every recorded run used the administrator permission set; running this
under the read-only permission set has not been exercised.

### Read back the retained network

| Field | Value |
|---|---|
| Validation status | EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-10) for the checks listed under Evidence basis; DESIGNED-NOT-EXECUTED (never) for the VPC DNS attributes, the internet gateway's attachment state and the main route table |
| Published form | not executed as written (the 2026-08-10 read-back commands were not retained; the VPC and endpoint queries are derived from retained 2026-09-10 `describe-vpcs` and `describe-vpc-endpoints` output taken without filters or projections) |
| Evidence basis | [Address plan](../../terraform/dev/README.md#address-plan), [Routing](../../terraform/dev/README.md#routing), [The S3 gateway endpoint](../../terraform/dev/README.md#the-s3-gateway-endpoint), [Tagging](../../terraform/dev/README.md#tagging). The recorded read-back of 2026-08-10, after the build and its `Name` tags, covered public-address assignment off on all four subnets, the public default route, no private default route, the S3 prefix-list route on the private table, four explicit associations, the six tags, the subnet role tags, the `Name` tags, the subnets' zone IDs, and no NAT gateway, Elastic IP or EKS cluster; it is recorded without retained output. No record shows the VPC DNS attributes, the internet gateway's attachment state or the main route table being read. Retained private evidence of 2026-09-10 covers only the VPC (CIDR, state and its seven tags), the endpoint (S3 gateway, available, one route table) and a summary line on the subnet count (see Known limitations) |
| Authority | none (read-only) |
| Cost | none |

**Purpose.** Verify from AWS, not from state, that the retained network matches the README.

**Preconditions.** A session on the project account. No runtime window open: during a window
the private route table also carries the NAT route.

**Procedure.**

1. Resolve the VPC, confirm it is unique, and read it:

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
| Tags | On the VPC and each subnet: `Component=network`, `Environment=dev`, `Lifecycle=ephemeral`, `ManagedBy=terraform`, `Owner=platform-engineer`, `Project=cloud-platform-reference` and `Name`, plus the role tag on each subnet |

**STOP conditions.** A VPC count other than one; a fifth subnet; a subnet associated with the
main table; a `0.0.0.0/0` route in the private table outside a runtime window, whatever its
state; any other value that differs from the table.

**Failure handling.** A difference from the README is a change made outside Terraform. Record
it and stop; reconciling it follows [terraform-operations.md](terraform-operations.md) under
its own approval.

**Evidence to retain.** The command output, privately; it carries resource identifiers.

**Known limitations.**

- No full read-back of the network has ever been retained; the 2026-08-10 read-back is
  recorded without output.
- The last retained summary of this network, on 2026-09-10, recorded five non-default subnets
  against the four declared, with no raw subnet output. The difference is unexplained and stays
  unresolved until a subnet read-back runs.
- The datastore adds resources to this VPC that this procedure does not look at; the next
  procedure covers them.

**Next gate.** The next run of this procedure, which settles the 2026-09-10 subnet count.

### Verify the retained side with the datastore present

| Field | Value |
|---|---|
| Validation status | DESIGNED-NOT-EXECUTED (never) |
| Published form | not executed as written (never run) |
| Evidence basis | [`terraform/dev-datastore/network.tf`](../../terraform/dev-datastore/network.tf); [datastore What it creates](../../terraform/dev-datastore/README.md#what-it-creates) and [Boundary](../../terraform/dev-datastore/README.md#boundary). Retained private evidence of 2026-09-10 shows the Dev VPC holding only its default security group and no network interface; of 2026-09-22, one datastore security group and still no interface, before the instance existed. The instance was created on 2026-09-24, and CloudTrail recorded the RDS service creating one network interface for it. That interface has not been read |
| Authority | none (read-only) |
| Cost | none |

**Purpose.** Since 2026-09-22 the datastore's security group, and since 2026-09-24 the
instance's network interface in a private subnet, sit inside this VPC. The earlier
retained-side expectations no longer hold: the default security group only ended on
2026-09-22, and no network interface on 2026-09-24. A retained-side check now has to tell the
datastore's footprint apart from runtime residue.

**Preconditions.** No runtime window open. `VPC_ID` resolved as in
[Read back the retained network](#read-back-the-retained-network).

**Procedure.**

1. Security groups in the VPC:

   ```
   aws ec2 describe-security-groups --filters Name=vpc-id,Values="$VPC_ID" \
     --query 'sort(SecurityGroups[].GroupName)' --output text
   ```

2. The datastore group's rules: run the network-boundary read-back in
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
  that the orphan census in [cost-and-residue.md](cost-and-residue.md) asserts. That
  classification has passed offline controls only and has never run against a live instance.
  `type` is recorded, not asserted. The first run confirms the classification or corrects it in
  [cost-and-residue.md](cost-and-residue.md).

**STOP conditions.**

- Any other security group or network interface between windows. Treat it as possible runtime
  residue and run the orphan census in [cost-and-residue.md](cost-and-residue.md).
- A datastore interface with values other than those above, attached to any other group, or
  with an address outside the private ranges.
- A failure of the rule check in step 2.

**Evidence to retain.** The command output, privately. On the first run, the observed fields of
the datastore interface, so later runs can assert them.

**Known limitations.** Never run. The datastore interface is expected to carry no project tags,
so a scan that selects by tag will not find it; this procedure identifies it by its security
group instead. That expectation is unobserved too. The datastore root's own state is not
planned here ([dev-datastore.md](dev-datastore.md)).

**Next gate.** The first run, at the next retained-side check or at the teardown of the next
runtime window.

### Read back the two Secrets Manager entries

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-10) |
| Published form | not executed as written (derived from the retained 2026-09-10 `describe-secret` output for both names, taken without a projection) |
| Evidence basis | [Identity, secrets and configuration](../../terraform/dev/README.md#identity-secrets-and-configuration); [`secrets.tf`](../../terraform/dev/secrets.tf). Retained private evidence: the 2026-09-10 metadata of both entries (the six tags with `Component=identity` and `Lifecycle=persistent`, no deletion scheduled, no rotation configured, version stages). Version counts were read again on 2026-09-22 with a version listing that also counts versions without a staging label; it matches this projection only while every version carries a label |
| Authority | none (read-only; metadata only) |
| Cost | Negligible: two Secrets Manager API requests |

**Purpose.** Confirm that both entries exist, are not scheduled for deletion, carry the
retained-resource tags, and hold the number of versions you expect, without reading any value.

**Procedure.**

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

**STOP conditions.** A missing entry; a `deletedDate`, which means the entry is scheduled for
deletion and its recovery has not been exercised; a version count that differs from the last
read made with this projection, with no recorded placement or rotation to explain it.

**Evidence to retain.** The output, privately.

**Known limitations.** The seven-day recovery window is a Terraform deletion setting
(`recovery_window_in_days`) that AWS does not return, so it cannot be read back before a
deletion. Deletion and recovery have never been exercised. This projection counts only
versions that carry a staging label.

## Not yet exercised

| Item | Label | What exists |
|---|---|---|
| [Check the zone mapping before the first build](#check-the-zone-mapping-before-the-first-build) | DESIGNED-NOT-EXECUTED | The procedure above. The reference account's zone IDs were read back only after the build, and the node-type check was recorded before the first runtime apply without a command |
| [Verify the retained side with the datastore present](#verify-the-retained-side-with-the-datastore-present) | DESIGNED-NOT-EXECUTED | The procedure above |
| [Build only the retained baseline](#build-only-the-retained-baseline): the plans and applies with the two target lists | DESIGNED-NOT-EXECUTED | The procedure above. Neither stage has run with these target lists, and the sequence has never run end to end |
| [Read back the retained network](#read-back-the-retained-network): the VPC DNS attributes, the internet gateway's attachment state and the main route table | DESIGNED-NOT-EXECUTED | The queries in that procedure. No record shows them read |
| AWS read-back of the Parameter Store entry, the two Pod Identity roles and their inline policies | UNEXERCISED | Their trust, policy scope and tags were read back when they were created, between 2026-08-12 and 2026-08-17 (EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE). Retained private evidence of 2026-09-10 holds only a parameter listing and the role names. No read-back procedure is published |
| Recover from a partial apply of this root | UNEXERCISED | A partial runtime apply was recovered once, on 2026-08-10, for an earlier shape of the root whose retained set was the 14 network addresses, with no secrets or identities (EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE): its commands were not retained and no complete orphan scan was claimed. Recovering today's root while preserving its 21 retained addresses, including both Secrets Manager entries, has not been exercised. Read-only inspection after an interrupted apply is in [terraform-operations.md](terraform-operations.md) |
| Decommission the Dev network | UNEXERCISED | The order only: no runtime present; the datastore root decommissioned first ([datastore Decommission](../../terraform/dev-datastore/README.md#decommission)); then this root's retained set. No reviewed command-level procedure exists |
| Change the address plan, the zones or the network `Name` tags after the first build | UNEXERCISED | Changing a subnet's CIDR block or zone replaces the subnet. The datastore root looks up the VPC and the private subnets by `Name` tag and derives its ingress rules from their CIDR blocks, so any of these changes also changes or breaks that root's plan |
| Delete and recover the two Secrets Manager entries within the recovery window | UNEXERCISED | Required by [ADR-0011](../decisions/0011-define-the-backup-and-recovery-model.md); the seven-day window is configured and nothing more |
| Check the datastore root for drift after a network or runtime operation | UNEXERCISED | Retained private evidence of 2026-09-22 compared that root's state serial, lineage and address list before and after operations on this root; no refresh-only plan of the datastore root has been part of any network or runtime procedure |

## Hidden prerequisites

- **Account and access.** A dedicated AWS account, its 12-digit ID for `allowed_account_id`,
  and an Identity Center administrator profile for it ([operator-access.md](operator-access.md)).
- **State backend.** The name of the state bucket the bootstrap root created, in an untracked
  `backend.hcl`.
- **Operator address.** Your public IPv4 address as a `/32` for `operator_cidr`. Every plan of
  this root requires it, and it changes with the network you work from.
- **Zone mapping.** Your account's mapping of `us-east-1a` and `us-east-1b` to zone IDs, checked
  for EKS support, the node instance type and the datastore engine.
- **Cost controls.** The budget and its alerts in place before the first billable resource, and
  a current Secrets Manager price ([cost-and-residue.md](cost-and-residue.md)).
- **Secret values.** A value for the Dev workload secret (the reference environment has only
  held synthetic validation material there) and the private key of a read-only deploy key for
  your own desired-state repository
  ([GitOps Delivery](../implementation/gitops-delivery.md#4-bootstrap-and-reconciliation)).
  Both are placed out of band after the containers exist, never through Terraform. No public
  placement procedure exists for either; the master-value placement in
  [dev-datastore.md](dev-datastore.md) does not cover them.
- **Approver.** Someone with authority over the account who reviews and approves each saved
  plan before it is applied.
- **Private working location.** `<private-dir>` as defined in
  [terraform-operations.md](terraform-operations.md), for saved plans, plan JSON, plan text and
  read-back output. They carry account and resource identifiers, and saved plans hold
  `operator_cidr` in clear text.
- **Tools.** Terraform 1.11 or later and below 2.0, as
  [`versions.tf`](../../terraform/dev/versions.tf) allows, validated here on 1.15.5 only; the
  AWS provider the committed lock file pins (6.58.0); the AWS CLI v2; and `jq`, `git`, `unzip`
  and `shasum` for the saved-plan review and binding in
  [terraform-operations.md](terraform-operations.md).
