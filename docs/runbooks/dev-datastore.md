# Dev Datastore Runbook

## Scope

This runbook operates [terraform/dev-datastore](../../terraform/dev-datastore/README.md): its two
secret containers, the one-time placement of the master value, and the two-stage build of the
PostgreSQL instance and its endpoint parameter, with the checks that show each step did what it
should and nothing more.

The root README stays the authority for what the root creates and why
([What it creates](../../terraform/dev-datastore/README.md#what-it-creates), which also gives the
build order), what it leaves out
([What this root does not create](../../terraform/dev-datastore/README.md#what-this-root-does-not-create)),
the network [Boundary](../../terraform/dev-datastore/README.md#boundary), the
[Debug logging](../../terraform/dev-datastore/README.md#debug-logging) rule,
[Decommission](../../terraform/dev-datastore/README.md#decommission) with the cost figures, and the
measured [Status](../../terraform/dev-datastore/README.md#status). The reasoning is in
[ADR-0008](../decisions/0008-define-the-secrets-and-workload-identity-model.md) (secrets),
[ADR-0011](../decisions/0011-define-the-backup-and-recovery-model.md) (recovery),
[ADR-0012](../decisions/0012-formalize-the-reference-workload.md) (workload data) and
[ADR-0013](../decisions/0013-define-operations-and-cost-guardrails.md) (cost and operations).

Linked, not repeated:

- [terraform-operations.md](terraform-operations.md): initializing a working tree, keeping debug
  logging off, planning to a saved file, reviewing and binding it, applying it, convergence, and the
  stop rule after a failed or interrupted apply. This runbook adds what this root's plans must
  contain and how its resources are read back.
- [operator-access.md](operator-access.md): signing in, confirming the account, and session lifetime.
- [dev-network.md](dev-network.md): the Dev network this root depends on.
- [cost-and-residue.md](cost-and-residue.md): the price re-check, the budget, the CPU-credit check,
  the weekly ADR-0013 review and the orphan census.
- [evidence-handling.md](evidence-handling.md): capture, redaction, sealing and remediation.
- [Runtime validation](../validation/runtime-validation.md): runtime windows and workload use of the
  datastore, which are outside this runbook.

Validation labels are defined in the [runbook index](README.md). Terraform steps follow the
conventions of [terraform-operations.md](terraform-operations.md), including `<profile>`,
`<work-dir>`, `<private-dir>`, `<plan-file>` and `<plan-json>`; use a new `<private-dir>` for each
plan. AWS CLI reads run with `--profile <profile> --region us-east-1` and are projected so that they
print no ARN, account number or secret version ID. The executed Stage 2 plan, pre-apply gate, apply,
read-back with its convergence plan, and every secret-absence proof ran in a shell prepared by
Export role credentials once in [operator-access.md](operator-access.md); run them that way, and
drop `--profile <profile>` and `AWS_PROFILE=<profile>` inside that shell.

The owner is the person accountable for the AWS account, who gives each grant this runbook
names.

## Procedures

### Stage 1: create the network boundary and the empty secret containers

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22) |
| Published form | not executed as written (the 2026-09-22 apply planned this root from public main at `2604e6c`, whose `terraform/dev-datastore` tree is identical to the tree at `aeb1622`, through private tooling; the linked workflow has not run for this stage) |
| Evidence basis | [What it creates](../../terraform/dev-datastore/README.md#what-it-creates), [Status](../../terraform/dev-datastore/README.md#status); retained private evidence of the 2026-09-22 plan, apply and read-back |
| Authority | Explicit owner grant naming the saved plan's hash |
| Cost | About 0.80 USD a month for the two containers from creation; the subnet group, security group and rules carry no charge ([cost](../../terraform/dev-datastore/README.md#decommission)) |

**Purpose.** Create what must exist before the master value can be placed: the DB subnet group, the
security group with its two ingress rules, and the two secret containers, with no value in either.
Planning `database.tf` reads the master value, so this stage plans a configuration that does not
contain that file.

**Preconditions.**
- The Dev network exists, with the VPC and private subnets `a` and `b` carrying their `Name` tags
  ([dev-network.md](dev-network.md)).
- The containers bill from creation, so the budget read-back and the price re-check for the
  Secrets Manager rate pass first ([cost-and-residue.md](cost-and-residue.md)).
- No resource with these names exists, and no secret with either container name is pending
  deletion. The counts below print `0`, and
  [Verify the secret containers](#verify-the-secret-containers-without-reading-a-value) step 4
  prints `[]`. A failed read prints an error, never a count, and is not absence. These two reads are
  derived from the executed check for pre-existing resources and have not run in this form.
  ```
  aws ec2 describe-security-groups --profile <profile> --region us-east-1 \
    --filters Name=group-name,Values=cloud-platform-reference-dev-datastore \
    --query 'length(SecurityGroups)'
  aws rds describe-db-subnet-groups --profile <profile> --region us-east-1 \
    --query "length(DBSubnetGroups[?DBSubnetGroupName=='cloud-platform-reference-dev-datastore'])"
  ```

**Procedure.**
1. Initialize the root in its own working tree at commit `aeb1622`
   ([terraform-operations.md](terraform-operations.md)). That commit's Terraform configuration
   differs from the current root only by the absence of `database.tf`; its README is an older
   version.
2. Keep debug logging off, plan to a saved file, review the plan and bind it
   ([terraform-operations.md](terraform-operations.md)).
3. Under the grant, apply the reviewed saved plan
   ([terraform-operations.md](terraform-operations.md)).
4. Remove the Stage 1 working tree, which holds copies of the untracked inputs. Stage 2 is planned
   from a new working tree at the reviewed commit that contains `database.tf`.
   ```
   git worktree remove --force <work-dir>
   ```

**Expected result.** The review lists exactly six `create` actions, on
`aws_db_subnet_group.datastore`, `aws_security_group.datastore`,
`aws_vpc_security_group_ingress_rule.postgres["a"]` and `["b"]`,
`aws_secretsmanager_secret.master` and `aws_secretsmanager_secret.app`, with no drift and no
outputs. The apply ends with `Apply complete! Resources: 6 added, 0 changed, 0 destroyed.`

**Validation.** [Read back the network boundary](#read-back-the-network-boundary) and
[Verify the secret containers](#verify-the-secret-containers-without-reading-a-value): both
containers hold zero versions. Convergence ([terraform-operations.md](terraform-operations.md)) has
not been run after Stage 1. If it is run, it runs before step 4, from the Stage 1 working tree; at
that commit the configuration does not read the master value.

**Evidence to retain.** The plan hash, the reviewed action list, the apply summary line and both
read-backs, privately.

**STOP conditions.** Any action other than the six creates; a failed network lookup (a missing or
duplicated `Name` tag fails the plan); any apply outcome other than the expected summary
([terraform-operations.md](terraform-operations.md)).

**Failure handling.** Follow the stop rule in [terraform-operations.md](terraform-operations.md).
Its read-back for this stage is [Read back the network boundary](#read-back-the-network-boundary)
and [Verify the secret containers](#verify-the-secret-containers-without-reading-a-value), recording
each of the six addresses as that rule classifies it. No secret-absence proof runs, because no value
exists yet; [Read the datastore after a failed or interrupted apply](#read-the-datastore-after-a-failed-or-interrupted-apply)
covers Stage 2 only. This path has never been exercised.

**Known limitations.** The README's other option, a `-target` plan of these six addresses from the
current checkout, has never run. Deleting a container is not a clean retry: its name stays reserved
through the recovery window.

**Next gate.** [Place the master value](#place-the-master-value).

### Read back the network boundary

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22, 2026-09-24) |
| Published form | not executed as written (derived from the reads of the two executed read-backs, whose output was compared in memory; `--query` projections added) |
| Evidence basis | [Boundary](../../terraform/dev-datastore/README.md#boundary), [network.tf](../../terraform/dev-datastore/network.tf); retained private evidence of the 2026-09-22 and 2026-09-24 read-backs |
| Authority | None (read-only) |
| Cost | None |

**Purpose.** Confirm that the security group admits TCP 5432 from the two private subnet ranges and
nothing else, has no egress rule, and that the subnet group spans the two private subnets.

**Procedure.**
1. Find the security group by name:
   ```
   sg=$(aws ec2 describe-security-groups --profile <profile> --region us-east-1 \
     --filters Name=group-name,Values=cloud-platform-reference-dev-datastore \
     --query 'SecurityGroups[].GroupId' --output text)
   echo "$sg" | wc -w
   ```
2. Read its rules and tags:
   ```
   aws ec2 describe-security-group-rules --profile <profile> --region us-east-1 \
     --filters Name=group-id,Values="$sg" \
     --query 'SecurityGroupRules[].[IsEgress,IpProtocol,FromPort,ToPort,CidrIpv4]' --output text
   aws ec2 describe-security-groups --profile <profile> --region us-east-1 \
     --group-ids "$sg" --query 'SecurityGroups[0].Tags'
   ```
3. Read the subnet group and its tags:
   ```
   aws rds describe-db-subnet-groups --profile <profile> --region us-east-1 \
     --db-subnet-group-name cloud-platform-reference-dev-datastore \
     --query 'DBSubnetGroups[0].{status:SubnetGroupStatus,zones:Subnets[].SubnetAvailabilityZone.Name}'
   aws rds list-tags-for-resource --profile <profile> --region us-east-1 \
     --resource-name "$(aws rds describe-db-subnet-groups --profile <profile> --region us-east-1 \
       --db-subnet-group-name cloud-platform-reference-dev-datastore \
       --query 'DBSubnetGroups[0].DBSubnetGroupArn' --output text)" \
     --query 'TagList'
   ```

**Expected result.**

| Read | Expected |
|---|---|
| Security groups with the name | 1 |
| Rules | Exactly two lines, `False tcp 5432 5432` from `10.20.0.0/20` and from `10.20.16.0/20`, the private ranges in the [address plan](../../terraform/dev/README.md#address-plan); no line beginning `True` |
| Tags | The six tags in [providers.tf](../../terraform/dev-datastore/providers.tf) on both; the security group also carries `Name` |
| Subnet group | `Complete`, over two different zones |

**STOP conditions.** Any other rule, any egress rule, more than one group with the name, or a failed
read. A failed read is never read as absence.

**Known limitations.** The boundary is a network position, not least privilege
([Boundary](../../terraform/dev-datastore/README.md#boundary)). It has been read back with the
instance absent and present, never during a runtime window. The 2026-09-24 read-back covered only
the rules, the absence of egress and the subnet group's membership; the tags and the subnet group's
`Complete` status were last read back on 2026-09-22. The VPC-wide view with the datastore present
is in [dev-network.md](dev-network.md).

### Verify the secret containers without reading a value

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22, 2026-09-24) |
| Published form | not executed as written (derived from the read-only commands executed after Stage 1, after placement and after the Stage 2 apply; `--query` projections added so no ARN or version ID prints) |
| Evidence basis | [What this root does not create](../../terraform/dev-datastore/README.md#what-this-root-does-not-create), [Status](../../terraform/dev-datastore/README.md#status); retained private evidence of the three verifications |
| Authority | None (read-only; never calls `GetSecretValue`) |
| Cost | None beyond per-request API charges |

**Purpose.** Establish each container's state from metadata alone: both empty before placement, the
master holding exactly one version after it, and, before every plan or apply of this root, the
master unchanged and the application container still empty.

**Preconditions.** A signed-in session ([operator-access.md](operator-access.md)). The commands set
`TZ=UTC` because the CLI renders some timestamps in the host's local offset, which the executed
reads had to correct.

**Procedure.**
1. Describe each container. `<container>` is `cloud-platform-reference-dev-datastore-master` or
   `cloud-platform-reference-dev-datastore-app`:
   ```
   TZ=UTC aws secretsmanager describe-secret --profile <profile> --region us-east-1 \
     --secret-id <container> \
     --query '{name:Name,deleted:DeletedDate,rotation:RotationEnabled,key:KmsKeyId && `"customer-managed"` || `"default"`,lastChanged:LastChangedDate,lastAccessed:LastAccessedDate,stages:values(VersionIdsToStages || `{}`),tags:Tags}'
   ```
2. List each container's versions, including deprecated ones:
   ```
   TZ=UTC aws secretsmanager list-secret-version-ids --profile <profile> --region us-east-1 \
     --secret-id <container> --include-deprecated \
     --query '{versions:length(Versions),stages:Versions[].VersionStages,created:Versions[].CreatedDate}'
   ```
3. After placement, confirm that the master's only version is the placement token, without printing
   it:
   ```
   aws secretsmanager list-secret-version-ids --profile <profile> --region us-east-1 \
     --secret-id cloud-platform-reference-dev-datastore-master --include-deprecated \
     --query "length(Versions[?VersionId=='<placement-token>'])"
   ```
4. Confirm that these are the only datastore secrets and that neither is scheduled for deletion:
   ```
   aws secretsmanager list-secrets --profile <profile> --region us-east-1 --include-planned-deletion \
     --filters Key=name,Values=cloud-platform-reference-dev-datastore \
     --query 'SecretList[].{name:Name,deleted:DeletedDate}'
   ```

**Expected result.**

| Field | Master, before placement | Master, after placement | Application container |
|---|---|---|---|
| `deleted` | `null` | `null` | `null` |
| `rotation` | `null` or `false` | `null` or `false` | `null` or `false` |
| `key` | `default` | `default` | `default` |
| `versions`, `stages` | `0`, `[]` | `1`, `[["AWSCURRENT"]]`, created inside the placement window | `0`, `[]` |
| Token check (step 3) | not applicable | `1` | not applicable |
| `lastAccessed` | `null` | `null` until the first plan reads the value, then that day | `null` |
| `tags` | the six tags in [providers.tf](../../terraform/dev-datastore/providers.tf) | unchanged | unchanged |
| Step 4 | the two names, `deleted` `null` | same | same |

**STOP conditions.** The application container holds any version or staging label; the master
holds more than one version, a stage other than `AWSCURRENT`, a version other than the placement
token, rotation, a customer-managed key or a deletion date; any other datastore-named secret exists;
any read fails. Nothing is planned, applied or placed until the cause is understood.

**Known limitations.** `LastAccessedDate` is truncated to the day, so retrieval within a day is
accounted for only in CloudTrail. The seven-day recovery window is a Terraform argument used at
deletion; no read shows it. These reads do not include the containers' resource policies. The
executed reads used the administrator profile; the read-only profile has not been tried for them.

### Account for secret reads and writes in CloudTrail

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-24) |
| Published form | not executed as written (the executed lookups filtered by event name and by write events, and reduced their output in memory before anything was kept; this form filters by event source and reduces the output with `jq`) |
| Evidence basis | Retained private evidence of the post-placement CloudTrail check and of the Stage 2 plan and apply accounting, 2026-09-24 |
| Authority | None (read-only) |
| Cost | None |

**Purpose.** Show that every read and write of the datastore secrets since a given time was an
authorized one, without printing an ARN, account number, principal, source address or version ID.

**Inputs.** `<utc-start>`, the time from which to account, for example the start of a placement or a
plan; `<placement-token>`, kept privately.

**Procedure.**
1. List every Secrets Manager event since `<utc-start>`, newest first. The subshell makes a failed
   lookup fail the whole pipeline, so the last line reports it:
   ```
   ( set -o pipefail
     aws cloudtrail lookup-events --profile <profile> --region us-east-1 \
       --lookup-attributes AttributeKey=EventSource,AttributeValue=secretsmanager.amazonaws.com \
       --start-time <utc-start> --query 'Events[].CloudTrailEvent' --output json \
     | jq -r --arg token '<placement-token>' '.[] | fromjson
         | [ .eventTime, .eventName,
             (if .readOnly == true then "read" elif .readOnly == false then "write" else "-" end),
             ((.requestParameters.secretId // "-")
               | if startswith("arn:") then sub("^.*:secret:"; "") | sub("-[A-Za-z0-9]{6}$"; "") else . end),
             ((.requestParameters.versionId // .requestParameters.clientRequestToken // null)
               | if . == null then "-" elif . == $token then "placement-token" else "other-id" end),
             ((.userAgent // "") | if test("terraform-provider-aws") then "terraform"
                                    elif startswith("aws-cli/") then "aws-cli" else "other" end),
             (.errorCode // "ok") ]
         | @tsv' )
   echo "exit $?"
   ```
2. Classify each line against the expected events below. The listing, including an empty one, is a
   result only when the last line is `exit 0`.

**Expected result.**

| Event | Expected |
|---|---|
| `CreateSecret` | Two, from the Stage 1 apply, when `<utc-start>` precedes it; none after. Stage 1 itself was not accounted in CloudTrail when it ran. |
| `PutSecretValue` | Exactly one since the containers were created: on the master, `placement-token`, `ok`, inside the placement window; none on the application container |
| `GetSecretValue`, `terraform`, no ID | One per plan or apply of this root, on the master |
| `GetSecretValue`, `aws-cli`, `placement-token` | One per run of the [secret-absence proof](#prove-the-master-value-is-absent-from-plans-state-and-logs) |
| Any other `GetSecretValue`, any `BatchGetSecretValue` | None |
| Other writes (`UpdateSecret`, `UpdateSecretVersionStage`, `RotateSecret`, `DeleteSecret`, `PutResourcePolicy`, `TagResource` and similar) | None |
| `DescribeSecret`, `ListSecretVersionIds`, `ListSecrets`, `GetResourcePolicy` | Metadata reads by the verification steps and by Terraform refresh |

On 2026-09-24 the placement produced exactly one `PutSecretValue`, and the Stage 2 plan, apply,
convergence plan and their proofs produced exactly the reads in this table.

**STOP conditions.** Any unexpected read or write, any value read (`GetSecretValue` or
`BatchGetSecretValue`) or any write on the application container, or a lookup that fails. Treat an
unexplained read of the master as a possible exposure
([Contain an exposed or unproven master value](#contain-an-exposed-or-unproven-master-value)).

**Known limitations.** Event history holds management events for this region and 90 days; S3 data
events on the state object are not visible there. Events can take several minutes to appear, so an
absence holds only up to the lookup time minus that delay. `lookup-events` accepts one attribute per
call.

### Place the master value

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-24) for the single run of the reviewed placement tool; DESIGNED-NOT-EXECUTED (never) for this step-level procedure with an equivalent tool |
| Published form | not executed as written (executed once through a reviewed placement tool, qualified offline before use, not published; this section gives the placement's scope, validation and STOP rules and no runnable placement command) |
| Evidence basis | [What this root does not create](../../terraform/dev-datastore/README.md#what-this-root-does-not-create), [Status](../../terraform/dev-datastore/README.md#status); retained private evidence of the tool's offline qualification and of the independent metadata and CloudTrail verification after the 2026-09-24 placement |
| Authority | Explicit owner grant naming the master container only and a single write attempt |
| Cost | No new resource; one API request |

**Purpose.** Put the master password into the master container as its first and only version,
before `database.tf` is planned. Terraform never writes it, and it is never displayed or recorded.
It is read only by the provider during each plan and apply of this root, and once by each run of
the [secret-absence proof](#prove-the-master-value-is-absent-from-plans-state-and-logs).

**Preconditions.**
- Stage 1 is applied.
- A written owner grant for this placement: the master container only, one write attempt, and
  whether a refusal before the write uses that attempt up.
- A signed-in session on the intended account with at least 30 minutes remaining
  ([operator-access.md](operator-access.md)).
- A fixed client request token, a UUID chosen in advance and recorded privately. It becomes the
  version ID. It is never published.
- The value's interface: one plain `SecretString`, not a key/value JSON document and not
  `SecretBinary`. [database.tf](../../terraform/dev-datastore/database.tf) passes it unchanged as
  the instance's master password, so it must also meet the RDS for PostgreSQL master-password
  constraints (`MasterUserPassword` in the Amazon RDS `CreateDBInstance` API reference). A value
  that does not cannot be corrected by placing again: a placement never writes to a container that
  already holds a value, and replacing it is rotation, which is [not yet exercised](#not-yet-exercised).

**Scope.** Master only; a placement never targets another container. The application container's
value is DEFERRED: that container stays empty until the path that consumes it is designed and
independently reviewed.

**Owner-execution boundary.** Placement is an owner step, run only by the owner in the owner's own
signed-in administrator permission-set session ([operator-access.md](operator-access.md)), never as
the account root user. No pipeline, scheduled job or other process runs it, and nobody else
receives the value.

**Tooling.** A reviewed placement tool, qualified offline before use, not published.

**Procedure.**
1. Run [Verify the secret containers](#verify-the-secret-containers-without-reading-a-value) and
   confirm the before-placement values.
2. Record the UTC start time.
3. Run the placement tool once, for the master container only, with the placement token.
4. Record the UTC end time and the tool's outcome line. Any outcome other than placed is a STOP.
5. Run [Verify the secret containers](#verify-the-secret-containers-without-reading-a-value) with the
   token check.
6. Run [Account for secret reads and writes in CloudTrail](#account-for-secret-reads-and-writes-in-cloudtrail)
   from the start time, after the event-history delay; the executed check ran about ten minutes
   after the write. Before then, a missing `PutSecretValue` is not yet a finding: repeat the
   read-only lookup, never the placement.

**Expected result.** The outcome is placed for the master, with the application container untouched.
The metadata shows the after-placement values. CloudTrail shows one successful `PutSecretValue` on
the master with the placement token inside the window, and no `GetSecretValue`.

**Validation.** Metadata and CloudTrail only, before and after the write; the value is not read to
validate the placement.

**STOP and no-retry.** The no-retry rule applies to write attempts. There is exactly one write
attempt, and it is never retried. The placement token makes it idempotent, so a repeated attempt
cannot add a second version; even so, a placement is never rerun after the write has been
attempted.

**Evidence to retain.** The start and end times, the outcome line, and the metadata and CloudTrail
outputs; never the value, the token or an ARN ([evidence-handling.md](evidence-handling.md)).

**STOP conditions.** Any preflight failure, any outcome other than placed, any unexpected CloudTrail
event, or the value appearing anywhere.

**Failure handling.** Never rerun the tool and never place a value by other means. Follow
[Respond to a failed or uncertain placement](#respond-to-a-failed-or-uncertain-placement).

**Recovery / rollback.** None is exercised. A placement never writes to a container that already
holds a value, so replacing a placed value is rotation ([Not yet exercised](#not-yet-exercised)).

**Evidence status.** Executed once, 2026-09-24. The result rests on the independent metadata and
CloudTrail verification retained as private evidence; the terminal output of the placement run
itself was not retained.

**Known limitations.** The tool is not published, so a reproducer supplies an equivalent that keeps
the scope, validation and STOP rules above and qualifies it offline before use; that path has never
run. The offline qualification before the executed placement ran against mocked AWS responses
only.

**Next gate.** [Stage 2: plan the instance and its endpoint parameter](#stage-2-plan-the-instance-and-its-endpoint-parameter).

### Respond to a failed or uncertain placement

| Field | Value |
|---|---|
| Validation status | OFFLINE-VALIDATED (2026-09-24) |
| Published form | not executed as written (the outcome classes below are the placement's required response classes, exercised only in offline qualification against mocked failures) |
| Evidence basis | Retained private evidence of the placement tool's offline qualification, 2026-09-24 |
| Authority | None for the read-only steps; any recovery needs a separate explicit owner grant |
| Cost | None |

**Purpose.** Leave the master container in a known state after a placement that did not end in a
clean placed outcome, without ever creating a second version.

**Procedure.**
1. Match the outcome to its class:

   | Outcome | Meaning |
   |---|---|
   | Refused before the write | A target, environment, account, session or preflight check failed. Nothing was written. |
   | Write may have succeeded | The write call returned an error, and the master now shows one version. |
   | No version visible yet | The write call returned an error, and the master showed zero versions at that moment; a committed write can still appear. |
   | Post-check failed | The write returned success, but a metadata post-check failed. |
   | Interrupted or state unknown | A signal arrived during the write, or the version count could not be read. |

2. For a refusal before the write, correct the cause. Run the placement again only if the grant
   states that a refusal before the write does not use up its attempt; otherwise only under a new
   grant.
3. For every other class, STOP. Do not rerun the tool. Run
   [Verify the secret containers](#verify-the-secret-containers-without-reading-a-value) and
   [Account for secret reads and writes in CloudTrail](#account-for-secret-reads-and-writes-in-cloudtrail),
   and record both.
4. Decide the next step in a separately reviewed decision under a new grant.

**Expected result.** The container's state is known from metadata and CloudTrail, and at most one
version exists.

**Known limitations.** No live failure has occurred, and no recovery after one has been reviewed or
exercised.

### Stage 2: plan the instance and its endpoint parameter

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-24) |
| Published form | not executed as written (the executed plan used the linked plan command through private tooling, from an extracted copy of the committed root, with credentials exported instead of `AWS_PROFILE`, a local provider directory and an allowlisted environment; its review ran as a 48-property check that is not published, from which the `jq` filters below are derived) |
| Evidence basis | [What it creates](../../terraform/dev-datastore/README.md#what-it-creates), [database.tf](../../terraform/dev-datastore/database.tf); retained private evidence of the 2026-09-24 plan, its expected-value check and its secret-absence proof |
| Authority | Explicit owner grant: the plan reads the master value once |
| Cost | None beyond per-request API charges |

**Purpose.** Produce one saved plan that creates the instance and its endpoint parameter and nothing
else, and check it against the expected values before anyone approves an apply.

**Preconditions.**
- The master is placed and the application container is empty
  ([Verify the secret containers](#verify-the-secret-containers-without-reading-a-value)).
- Stage 1 is applied to the same state, and a working tree at the reviewed commit, which contains
  `database.tf`, is initialized ([terraform-operations.md](terraform-operations.md)).
- Prices are re-checked before the instance is created ([cost-and-residue.md](cost-and-residue.md)).
- A session with at least 45 minutes remaining, the margin the executed plan and its proof used.

**Procedure.**
1. Keep debug logging off ([terraform-operations.md](terraform-operations.md)).
2. Record the UTC time, then plan to a saved file in a new `<private-dir>`
   ([terraform-operations.md](terraform-operations.md)), redirecting the plan's output to
   `<private-dir>/plan.log` so that the proof covers it.
3. Review the saved plan ([terraform-operations.md](terraform-operations.md)) against the expected
   result below.
4. Check the planned values of the instance and the parameter:
   ```
   jq '.resource_changes[] | select(.address == "aws_db_instance.datastore") | .change.after
       | {identifier, engine_version, instance_class, allocated_storage, storage_type,
          storage_encrypted, publicly_accessible, multi_az, backup_retention_period,
          deletion_protection, skip_final_snapshot, final_snapshot_identifier,
          manage_master_user_password, password, password_wo_version, tags_all}' <plan-json>
   jq '.resource_changes[] | select(.address == "aws_ssm_parameter.endpoint")
       | {name: .change.after.name, type: .change.after.type, tier: .change.after.tier,
          value_known_after_apply: .change.after_unknown.value}' <plan-json>
   ```
5. Run the [secret-absence proof](#prove-the-master-value-is-absent-from-plans-state-and-logs).
6. Only after the proof finds no occurrence, bind the saved plan
   ([terraform-operations.md](terraform-operations.md)). The apply grant names its hash.

**Expected result.**
- The plan exits 2. `plan.log` shows `ephemeral.aws_secretsmanager_secret_version.master` opening
  and closing once.
- The review lists exactly two actions, `create` on `aws_db_instance.datastore` and on
  `aws_ssm_parameter.endpoint`; the six Stage 1 addresses are `no-op`. No outputs.
- Drift, if listed, is limited to `tags` on `aws_db_subnet_group.datastore`,
  `aws_secretsmanager_secret.master` and `aws_secretsmanager_secret.app`, and `ingress` on
  `aws_security_group.datastore`. The 2026-09-24 plan showed exactly these four: the refresh
  recorded empty tag maps where Stage 1 stored none, and the security group mirrors the two ingress
  rules managed as separate resources. Each was planned `no-op`.
- The instance values equal [database.tf](../../terraform/dev-datastore/database.tf);
  `password` and `manage_master_user_password` are `null`, `password_wo_version` is `1`, and
  `tags_all` holds the six tags in [providers.tf](../../terraform/dev-datastore/providers.tf).
- The parameter is `cloud-platform-reference-dev-datastore-endpoint`, `String`, `Standard`, with
  `value_known_after_apply` `true`.
- The proof finds no occurrence.

**Evidence to retain.** The UTC time the plan started, the exit code, the review lists, both value
checks, the plan hash and the proof's counts. The saved plan and `plan.log` stay in `<private-dir>`.

**STOP conditions.** An exit code other than 2; any other action, address, drift or output; any
value that differs from the configuration; the master opened more than once; a proof that finds the
value or cannot complete.

**Known limitations.** The executed check also proved that the configuration held no module,
provisioner or other secret read; the published review covers actions, drift, outputs and the
principal values. The executed runs reduced Terraform's environment to an allowlist and recorded
what each run received; the published form relies on the debug-logging check.

**Next gate.** [Run the pre-apply gate](#run-the-pre-apply-gate), then an owner grant naming the
plan hash.

### Run the pre-apply gate

| Field | Value |
|---|---|
| Validation status | DESIGNED-NOT-EXECUTED (never) |
| Published form | not executed as written (a checklist derived from a single-use read-only gate that ran once, 2026-09-24, immediately before the apply, and passed every check; that gate was bound to one commit, one saved plan and one expiry and cannot be reused) |
| Evidence basis | Retained private evidence of the single-use gate, its offline qualification and its 2026-09-24 run |
| Authority | None (read-only; never reads a secret value) |
| Cost | None beyond per-request API charges |

**Purpose.** Immediately before the Stage 2 apply, confirm that nothing the saved plan assumed has
changed. This checklist covers the first creation of the instance; no gate exists for a later apply
of this root.

**Procedure.**
1. Confirm each absence by its error code, never by an empty or failed read. Each command prints the
   value it reads, or only the error code:
   ```
   aws rds describe-db-instances --profile <profile> --region us-east-1 \
     --db-instance-identifier cloud-platform-reference-dev-datastore \
     --query 'DBInstances[0].[DBInstanceStatus,DeletionProtection]' --output text 2>&1 \
     | sed -E 's/^.*An error occurred \(([A-Za-z]+)\).*$/error: \1/'
   aws rds describe-db-snapshots --profile <profile> --region us-east-1 \
     --db-snapshot-identifier cloud-platform-reference-dev-datastore-final \
     --query 'DBSnapshots[0].Status' --output text 2>&1 \
     | sed -E 's/^.*An error occurred \(([A-Za-z]+)\).*$/error: \1/'
   aws ssm get-parameter --profile <profile> --region us-east-1 \
     --name cloud-platform-reference-dev-datastore-endpoint \
     --query 'Parameter.Type' --output text 2>&1 \
     | sed -E 's/^.*An error occurred \(([A-Za-z]+)\).*$/error: \1/'
   ```
2. Confirm that the engine can be ordered in both subnet zones:
   ```
   aws rds describe-orderable-db-instance-options --profile <profile> --region us-east-1 \
     --engine postgres --engine-version 17.11 --db-instance-class db.t4g.micro \
     --query 'OrderableDBInstanceOptions[?StorageType==`"gp3"`].AvailabilityZones[].Name'
   ```
3. Work through the checklist. Any failed or unreadable check is a HOLD.

   | Check | Pass condition |
   |---|---|
   | Plan age | No more than 72 hours after the recorded plan start, the maximum the executed gate allowed, with at least 30 minutes of that left |
   | Saved plan | Bound as in [terraform-operations.md](terraform-operations.md); its hash equals the hash in the grant; it has never been applied |
   | Terraform and provider | `terraform version -json \| jq -r .terraform_version` prints the `terraform_version` in `<plan-json>`, and the bind step printed `same` for the lock file ([terraform-operations.md](terraform-operations.md)) |
   | Session | On the intended account, with at least 50 minutes remaining |
   | Master container | Exactly the placed version, `AWSCURRENT` only, rotation off ([Verify the secret containers](#verify-the-secret-containers-without-reading-a-value)) |
   | Application container | Empty |
   | Instance | `error: DBInstanceNotFound` |
   | Final snapshot name | `error: DBSnapshotNotFound` |
   | Endpoint parameter | `error: ParameterNotFound` |
   | Network boundary | Unchanged ([Read back the network boundary](#read-back-the-network-boundary)) |
   | Engine | Step 2 lists both subnet zones |
   | Prices | Every rate the instance bills equal to the price table in [cost-and-residue.md](cost-and-residue.md) |
   | Budget | The budget and its alerts intact, each alert with a subscriber ([cost-and-residue.md](cost-and-residue.md)) |
   | Runtime | Every runtime class of the census is zero ([cost-and-residue.md](cost-and-residue.md)) |

4. Start the apply straight after a full pass.

**Expected result.** Every check passes. Any other error code, for example `AccessDenied`, is not an
absence.

**STOP conditions.** Any HOLD. A HOLD applies nothing; a new plan needs a new `<private-dir>`.

**Known limitations.** The executed gate ran as one command that checked all of these and pinned the
plan's expiry. It compared the Terraform and provider binaries by hash and the prices against the
reviewed cost package; this checklist compares the Terraform version, the lock file and the price
table instead. This checklist has never run as written.

### Stage 2: apply the reviewed saved plan

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-24) |
| Published form | not executed as written (the executed apply used the linked apply command through private tooling, with credentials exported instead of `AWS_PROFILE`, an allowlisted environment, a 50-minute session margin and Terraform shielded from a terminal hangup) |
| Evidence basis | [Status](../../terraform/dev-datastore/README.md#status); retained private evidence of the 2026-09-24 gate, apply, post-apply proof and CloudTrail accounting |
| Authority | Explicit owner grant naming the saved plan's hash |
| Cost | Billing starts at creation, whatever follows: about 0.0192 USD an hour for the instance and storage, plus CPU-credit charges with no cap, up to about 0.15 USD an hour at full load ([cost](../../terraform/dev-datastore/README.md#decommission)) |

**Purpose.** Create the instance and its endpoint parameter from the reviewed saved plan, once.

**Preconditions.**
- The pre-apply gate passed just now.
- An owner grant naming the plan hash.
- A session with at least 50 minutes remaining. The executed create took 6 minutes 10 seconds.
- Debug logging is off ([terraform-operations.md](terraform-operations.md)).
- The apply runs so that closing or losing the terminal cannot end Terraform. The executed apply was
  shielded from a terminal hangup by private tooling that is not published; no published form of
  that shielding has been exercised.

**Procedure.**
1. Apply the reviewed saved plan ([terraform-operations.md](terraform-operations.md)), redirecting
   its output to `<private-dir>/apply.log`.
2. Run the [secret-absence proof](#prove-the-master-value-is-absent-from-plans-state-and-logs).
3. Take the first CPU-credit reading ([cost-and-residue.md](cost-and-residue.md)).

**Expected result.** Exit 0. `apply.log` shows the master opened and closed once,
`aws_db_instance.datastore: Creation complete`, `aws_ssm_parameter.endpoint: Creation complete` and
`Apply complete! Resources: 2 added, 0 changed, 0 destroyed.` The proof finds no occurrence.
[Account for secret reads and writes in CloudTrail](#account-for-secret-reads-and-writes-in-cloudtrail)
shows one provider read of the master for the apply, one proof read and no secret write.

**Evidence to retain.** The hash check, the exit code, the summary line, the proof's counts and the
Secrets Manager accounting.

**STOP conditions.** A non-zero exit, an interrupt, a terminal hangup or a summary that differs.
Never re-apply. Follow the stop rule in [terraform-operations.md](terraform-operations.md), with
[Read the datastore after a failed or interrupted apply](#read-the-datastore-after-a-failed-or-interrupted-apply)
as its read-back for this root.

**Known limitations.** In offline qualification, a terminal hangup during an RDS create killed
Terraform mid-create unless it was shielded from the hangup; the linked command is not shielded.
Only the Secrets Manager events have a published accounting command. On 2026-09-24 the apply's
other management events were also accounted, by reads that are not published: exactly the two
creates (`CreateDBInstance` and `PutParameter`) and, as AWS service side effects of the create,
KMS grants and the instance's network interface. A reproducer has no published command for that
check.

**Teardown / decommission.** Not exercised; see
[Decommission](../../terraform/dev-datastore/README.md#decommission).

**Next gate.** [Read back the instance and its endpoint parameter](#read-back-the-instance-and-its-endpoint-parameter)
and [Confirm convergence](#confirm-convergence).

### Read the datastore after a failed or interrupted apply

| Field | Value |
|---|---|
| Validation status | OFFLINE-VALIDATED (2026-09-24) |
| Published form | not executed as written (derived from the qualified read-only inspection, exercised only in offline qualification; confirming absences by error code has run before an apply, never after a failed one) |
| Evidence basis | Retained private evidence of the offline qualification of the apply's failure classes and inspection |
| Authority | None for steps 1, 2 and 4; step 3 reads the master value once and needs an explicit owner grant; any recovery, import or deletion needs a separate explicit owner grant |
| Cost | The instance bills from creation if it exists |

**Purpose.** Supply the read-back step of the stop rule in
[terraform-operations.md](terraform-operations.md) for this root, without changing anything.

**Procedure.**
1. Read the instance and the endpoint parameter with the first and third commands in
   [Run the pre-apply gate](#run-the-pre-apply-gate), step 1.
2. Run [Verify the secret containers](#verify-the-secret-containers-without-reading-a-value).
3. Run the [secret-absence proof](#prove-the-master-value-is-absent-from-plans-state-and-logs)
   before anything from `<private-dir>` or the working tree is shared.
4. Record each of the two planned addresses as the stop rule classifies it, and decide any recovery
   in a separately reviewed decision.

**Expected result.** A recorded state: whether the instance exists, with its status and deletion
protection; whether the parameter exists; the master unchanged; the proof's result.

**Known limitations.** An instance that exists bills until it is deleted and carries deletion
protection, so removing it needs the reviewed change in
[Decommission](../../terraform/dev-datastore/README.md#decommission). No recovery after a failed
apply has been reviewed or exercised.

### Read back the instance and its endpoint parameter

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-24) |
| Published form | not executed as written (derived from the executed read-back, whose `describe` output and Terraform state were compared in memory against the expected values; `--query` and `jq` projections added) |
| Evidence basis | [Status](../../terraform/dev-datastore/README.md#status); retained private evidence of the 2026-09-24 read-back and of an independent read-only read the same day |
| Authority | None (read-only) |
| Cost | None |

**Purpose.** Confirm that the instance and the parameter in AWS match the configuration, and that
the state keeps the protections and holds no password.

**Procedure.**
1. Read the instance:
   ```
   aws rds describe-db-instances --profile <profile> --region us-east-1 \
     --db-instance-identifier cloud-platform-reference-dev-datastore \
     --query 'DBInstances[0].{status:DBInstanceStatus,engine:Engine,version:EngineVersion,class:DBInstanceClass,storage:AllocatedStorage,storageType:StorageType,encrypted:StorageEncrypted,public:PubliclyAccessible,multiAZ:MultiAZ,network:NetworkType,port:Endpoint.Port,backupDays:BackupRetentionPeriod,backupWindow:PreferredBackupWindow,maintenanceWindow:PreferredMaintenanceWindow,deletionProtection:DeletionProtection,copyTags:CopyTagsToSnapshot,autoMinorUpgrade:AutoMinorVersionUpgrade,iamAuth:IAMDatabaseAuthenticationEnabled,managedSecret:MasterUserSecret && `true` || `false`,user:MasterUsername,dbName:DBName,ca:CACertificateIdentifier,lifecycle:EngineLifecycleSupport,parameterGroups:DBParameterGroups[].[DBParameterGroupName,ParameterApplyStatus],subnetGroup:DBSubnetGroup.DBSubnetGroupName,subnetZones:DBSubnetGroup.Subnets[].SubnetAvailabilityZone.Name,maxStorage:MaxAllocatedStorage,performanceInsights:PerformanceInsightsEnabled,monitoring:MonitoringInterval,logExports:EnabledCloudwatchLogsExports,tags:TagList}'
   ```
2. Confirm that the instance sits behind the datastore security group alone, using `$sg` from
   [Read back the network boundary](#read-back-the-network-boundary), step 1, and that its storage
   key is AWS-managed:
   ```
   aws rds describe-db-instances --profile <profile> --region us-east-1 \
     --db-instance-identifier cloud-platform-reference-dev-datastore \
     --query "DBInstances[0].{groups:length(VpcSecurityGroups),datastoreGroup:VpcSecurityGroups[?VpcSecurityGroupId=='$sg'].Status}"
   aws kms describe-key --profile <profile> --region us-east-1 \
     --key-id "$(aws rds describe-db-instances --profile <profile> --region us-east-1 \
       --db-instance-identifier cloud-platform-reference-dev-datastore \
       --query 'DBInstances[0].KmsKeyId' --output text)" \
     --query 'KeyMetadata.[KeyManager,KeyState]' --output text
   ```
3. Read the endpoint parameter and its tags, and compare its value with the instance address
   without printing either. A failed or empty read prints `MISMATCH`:
   ```
   aws ssm describe-parameters --profile <profile> --region us-east-1 \
     --parameter-filters Key=Name,Values=cloud-platform-reference-dev-datastore-endpoint \
     --query 'Parameters[].[Name,Type,Tier,Version]' --output text
   aws ssm list-tags-for-resource --profile <profile> --region us-east-1 \
     --resource-type Parameter --resource-id cloud-platform-reference-dev-datastore-endpoint \
     --query 'TagList'
   p=$(aws ssm get-parameter --profile <profile> --region us-east-1 \
       --name cloud-platform-reference-dev-datastore-endpoint --query 'Parameter.Value' --output text) &&
   d=$(aws rds describe-db-instances --profile <profile> --region us-east-1 \
       --db-instance-identifier cloud-platform-reference-dev-datastore \
       --query 'DBInstances[0].Endpoint.Address' --output text) &&
   [ -n "$p" ] && [ "$p" = "$d" ] && echo MATCH || echo MISMATCH
   unset p d
   ```
4. From `terraform/dev-datastore` in the working tree, read the protections and the password fields
   from the state:
   ```
   AWS_PROFILE=<profile> terraform show -json \
     | jq '.values.root_module.resources[] | select(.address == "aws_db_instance.datastore") | .values
         | {deletion_protection, skip_final_snapshot, final_snapshot_identifier,
            password, password_wo, password_wo_version}'
   ```
5. Run [Read back the network boundary](#read-back-the-network-boundary) and
   [Verify the secret containers](#verify-the-secret-containers-without-reading-a-value).

**Expected result.**

| Read | Expected |
|---|---|
| Instance | `available`; `postgres` `17.11`; `db.t4g.micro`; `20` GiB `gp3`, encrypted; not public; not Multi-AZ; `IPV4`; port `5432` |
| Backups and maintenance | `7` days, `04:00-04:30`; `sun:05:00-sun:05:30`; automatic minor upgrades off; tags copied to snapshots |
| Protection and access | Deletion protection `true`; IAM authentication `false`; `managedSecret` `false`; user `otel_admin`, database `otel` |
| Engine settings | CA `rds-ca-rsa2048-g1`; `default.postgres17`, `in-sync`; lifecycle `open-source-rds-extended-support-disabled` |
| Extras | `maxStorage`, `logExports` `null`; Performance Insights `false`; monitoring `0` |
| Placement | Subnet group `cloud-platform-reference-dev-datastore` over two different zones; `groups` `1`, `datastoreGroup` `["active"]` |
| Storage key | `AWS Enabled` |
| Tags | The six tags in [providers.tf](../../terraform/dev-datastore/providers.tf) on the instance and the parameter |
| Parameter | One line, `String Standard 1`; `MATCH` |
| State | `true`, `false`, `cloud-platform-reference-dev-datastore-final`; `password` and `password_wo` `null`; `password_wo_version` `1` |

**Evidence to retain.** The output of every step, projected as above.

**STOP conditions.** Any value that differs, `MISMATCH`, a failed read, or a public or open path.

**Known limitations.** The final-snapshot settings and `prevent_destroy` are visible only in
Terraform state and configuration; AWS applies the snapshot settings at deletion. A configured final
snapshot does not exist until deletion, and an automated backup is not proof that data can be
restored. The executed read-back also counted the account's DB instances and snapshots; that census
belongs to [cost-and-residue.md](cost-and-residue.md).

**Next gate.** The weekly ADR-0013 review while the instance exists
([cost-and-residue.md](cost-and-residue.md)).

### Confirm convergence

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-24) |
| Published form | not executed as written (the executed convergence plan used the linked command through private tooling, with credentials exported instead of `AWS_PROFILE`, an allowlisted environment and its output captured for the proof) |
| Evidence basis | [Status](../../terraform/dev-datastore/README.md#status); retained private evidence of the 2026-09-24 convergence plan and its proof |
| Authority | Explicit owner grant: the plan reads the master value once |
| Cost | None beyond per-request API charges |

**Purpose.** Show that the configuration and the account agree after the apply, and that the check
itself left no copy of the value.

**Procedure.**
1. Keep debug logging off and confirm convergence ([terraform-operations.md](terraform-operations.md)),
   redirecting the plan's output to `<private-dir>/converge.log`.
2. Run the [secret-absence proof](#prove-the-master-value-is-absent-from-plans-state-and-logs),
   which covers `converge.log`.

**Expected result.** Exit 0 and `No changes. Your infrastructure matches the configuration.`, with
all eight managed resources refreshed and the master opened and closed once. The proof finds no
occurrence.

**STOP conditions.** Exit 2 or 1: find the cause as in [terraform-operations.md](terraform-operations.md)
before anything else runs. A proof that finds the value or cannot complete.

**Known limitations.** Like the Stage 1 tree, the Stage 2 working tree holds copies of the untracked
inputs. No rule for removing it has been defined or exercised
([terraform-operations.md](terraform-operations.md)); it stays private, and nothing from it is
shared before a proof over it has found no occurrence.

### Prove the master value is absent from plans, state and logs

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-24) |
| Published form | not executed as written (method only; the executed proof is a reviewed tool that is not published, because every runnable form reads the value) |
| Evidence basis | [Status](../../terraform/dev-datastore/README.md#status) records the result; retained private evidence of the plan, post-apply and read-back proofs and of an independent check that never read the value, 2026-09-24 |
| Authority | Explicit owner grant: each run reads the master value once |
| Cost | None beyond per-request API charges |

**Purpose.** Show that no artifact of a run holds the master value, although every plan and apply of
this root passes it through the provider. Write-only handling keeps it out of state and plan files
by design; this proof measures that.

**Method.**
1. When: after the Stage 2 plan, after the apply, and after the read-back and convergence plan. A
   proof also runs after a failed apply, before anything from it is shared.
2. What is searched: every regular file in that run's `<private-dir>` and in the root's directory
   of the working tree, `<work-dir>/terraform/dev-datastore`, including `.terraform/` and any
   `errored.tfstate` Terraform leaves there; the saved plan and each of its archive members; its
   JSON rendering; every captured Terraform output; and a fresh pull of the state held only for the
   search. Only the provider binaries under `.terraform/providers` are skipped, as the executed
   proof skipped them. The executed runs kept Terraform's working directory inside the searched
   directory; the layout of `<work-dir>` and `<private-dir>` used here has not run.
3. What is prevented rather than searched: Terraform debug logs and protocol dumps. The executed
   runs recorded the names of the environment variables each Terraform run received, and the proof
   required every name to be on an allowlist with no `TF_LOG*`, `TF_CLI_ARGS*`, `TF_VAR_*`,
   `TF_REATTACH_PROVIDERS` or `TF_DATA_DIR`
   ([Debug logging](../../terraform/dev-datastore/README.md#debug-logging)).
4. How: the value is read once through the AWS CLI, by the placement token's version ID, straight
   into the search on standard input. It is never displayed or stored. The search looks for the
   value in its literal form and in common encodings, including base64 at every alignment and inside
   compressed plan members, and prints counts only.
5. Fail-closed rules: the search must first find a planted copy of the value in every form; a failed
   read of the value, the state or any artifact is a HOLD, never a zero; any occurrence is a finding.
6. Cross-check without the value: the retained evidence is swept for strings in the value's format,
   as chosen at placement, and every hit is accounted for. The executed format is not published.

**Expected result.** Zero occurrences in every artifact. The measured result is in
[Status](../../terraform/dev-datastore/README.md#status).

**STOP conditions.** Any occurrence, or a proof that cannot complete:
[Contain an exposed or unproven master value](#contain-an-exposed-or-unproven-master-value).

**Known limitations.** Each proof run adds one `GetSecretValue` to CloudTrail. The proof covers
`<private-dir>` and the root's directory of the working tree, not the operator's terminal
scrollback, clipboard or shell history.

### Contain an exposed or unproven master value

| Field | Value |
|---|---|
| Validation status | DESIGNED-NOT-EXECUTED (never) |
| Published form | not executed as written (derived from the reviewed stop behaviour of the plan, apply and proof tooling, whose detection side was exercised only in offline qualification with planted values) |
| Evidence basis | Retained private evidence of the offline qualification, 2026-09-24; no exposure has occurred |
| Authority | Explicit owner grant for any step beyond the STOP and the record |
| Cost | None |

**Purpose.** Stop the spread of the master value when a proof finds it, when a proof cannot
complete, or when the value appears anywhere else.

**Procedure.**
1. STOP. No further plan, apply or proof run, and no rerun of the step that produced the artifact.
2. Do not share, copy, commit, upload, export or remove `<private-dir>`, the working tree or any
   artifact from that run. Both stay where they are; `<private-dir>` keeps its owner-only
   permissions.
3. Record which artifact and which step, by name and occurrence count only, never the content.
4. If the proof could not complete, the artifacts are unproven rather than exposed: they stay
   unshared until a proof run under the grant's read scope completes.
5. If the value was found, treat it as compromised. The remedy is rotation, which is
   [not yet exercised](#not-yet-exercised) and needs its own reviewed procedure and grant. An
   artifact already retained or exported is remediated as in
   [evidence-handling.md](evidence-handling.md).

**Known limitations.** Containment has never been needed or exercised, and no rotation procedure
exists.

## Not yet exercised

| Item | Label | Note |
|---|---|---|
| [Run the pre-apply gate](#run-the-pre-apply-gate) as a reusable checklist | DESIGNED-NOT-EXECUTED | Only its single-use form ran, once. No gate exists for a later apply of this root. |
| [Contain an exposed or unproven master value](#contain-an-exposed-or-unproven-master-value) | DESIGNED-NOT-EXECUTED | Never needed. |
| [Place the master value](#place-the-master-value) as a step-level procedure with an equivalent tool | DESIGNED-NOT-EXECUTED | Only the reviewed placement tool ran, once. |
| Recovery after a failed or uncertain placement | UNEXERCISED | No reviewed procedure. Removing a stray version or placing again needs its own reviewed decision and grant. |
| Stage 2 apply protected from a terminal hangup, in a published form | UNEXERCISED | The executed apply was shielded by private tooling that is not published. |
| Stage 1 from the current checkout with `-target` | UNEXERCISED | The README's alternative to planning commit `aeb1622`; never run. |
| Master rotation | UNEXERCISED | An operational procedure with no reviewed form. Here rotation means a new master version together with a `password_wo_version` increment in [database.tf](../../terraform/dev-datastore/database.tf). A placement never writes to a non-empty container, so rotation needs its own reviewed procedure and grant. The rotation exercise [ADR-0008](../decisions/0008-define-the-secrets-and-workload-identity-model.md) requires was met on the dev secret path ([Identity, secrets and configuration](../../terraform/dev/README.md#identity-secrets-and-configuration)) and does not cover this secret. |
| Stop and start the instance | UNEXERCISED | No procedure exists. |
| Restore from a snapshot or an automated backup | UNEXERCISED | The workload-data restore exercise that [ADR-0011](../decisions/0011-define-the-backup-and-recovery-model.md) requires is owed now that the datastore exists. It runs only under a separately reviewed recovery package. A retained snapshot or an automated backup is not restore proof. |
| Secret accidental-deletion recovery | UNEXERCISED | [ADR-0011](../decisions/0011-define-the-backup-and-recovery-model.md) requires a secret to be retrieved after a simulated accidental deletion. The seven-day recovery window is configured and has never been verified. |
| Maintenance | UNEXERCISED | Minor-version upgrades (automatic upgrades are off), pending maintenance actions and CA certificate rotation. No procedure exists. |
| Decommission, including the final snapshot's retention and deletion | UNEXERCISED | Designed in [Decommission](../../terraform/dev-datastore/README.md#decommission) as one reviewed change in three steps; no reviewed command sheet exists, and it needs a separate owner grant. No final snapshot exists. |
| Application value and application database role | UNEXERCISED, DEFERRED | The application container stays empty until its consumer path is designed and independently reviewed. |

## Hidden prerequisites

- **Account and inputs.** An AWS account of your own. Its 12-digit ID goes in the untracked
  `terraform.tfvars` ([terraform.tfvars.example](../../terraform/dev-datastore/terraform.tfvars.example)),
  and the state bucket from the bootstrap root goes in the untracked `backend.hcl`
  ([backend.hcl.example](../../terraform/dev-datastore/backend.hcl.example)).
- **Identity and sessions.** An IAM Identity Center operator with an administrator permission set and
  a CLI profile ([operator-access.md](operator-access.md)). The executed runs required this much
  session time remaining: 30 minutes for placement, 45 for a plan with its proof, 50 for the
  pre-apply gate and the apply, and 5 for the read-back with its convergence plan and for each
  secret-absence proof after a plan or apply.
- **Network.** The Dev network baseline applied ([dev-network.md](dev-network.md)).
- **Toolchain.** Terraform 1.11 or later and below 2.0 (1.15.5 was used) with the `hashicorp/aws`
  provider the committed lock file selects (6.58.0 was used); AWS CLI v2; `jq`; `git`; `unzip`;
  `shasum`.
- **Placement tool.** A tool that keeps the scope, validation and STOP rules in
  [Place the master value](#place-the-master-value), qualified offline before use, and places a
  value with the interface stated in its preconditions. The reviewed tool used here is not
  published.
- **Placement token.** A fixed client request token (a UUID) chosen before placement and recorded
  privately.
- **Absence proof.** A tool that implements the
  [method](#prove-the-master-value-is-absent-from-plans-state-and-logs). The reviewed tool used here
  is not published.
- **Hangup protection.** A way to run the Stage 2 apply that closing or losing the terminal cannot
  end. The executed form is not published, and no published form has been exercised.
- **Private directories.** A new `<private-dir>` per plan, outside every Git working tree, created
  under `umask 077`, and a private evidence location ([evidence-handling.md](evidence-handling.md)).
- **Approvals.** A written owner grant for each mutation (the Stage 1 apply, placement, the Stage 2
  apply, any recovery, decommission) and for every run that reads the master value.
- **Cost controls.** The budget and its alerts, and a price re-check before each billable apply,
  Stage 1 and Stage 2 ([cost-and-residue.md](cost-and-residue.md)).
- **Capacity.** PostgreSQL 17.11 orderable on `db.t4g.micro` with gp3 in both zones of your private
  subnets. Zone names map to different physical zones in each account.
