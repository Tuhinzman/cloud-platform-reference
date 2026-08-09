# Terraform state backend bootstrap

Terraform manages the platform, but it cannot create its own remote state
backend from remote state. This root resolves that. It creates the S3 bucket
that holds Terraform state for every other configuration root, starting from
local state and migrating into the bucket once the bucket exists. ADR-0003
fixes that model and this directory implements it.

It is deliberately the smallest root in the repository. One bucket, and the
four settings that protect it. The region is us-east-1, fixed by ADR-0004.

## Why the backend block arrived second

The first run used Terraform's default local backend. That was the only backend
available then, because the bucket an S3 backend needs did not exist until this
root created it.

`terraform init -backend=false` does not close that gap. It installs providers
and prepares the configuration for validation, and it deliberately leaves the
working directory without an initialized backend, so it cannot carry a plan or
an apply.

`backend.tf` now holds the active partial backend configuration, added at step 3
of the migration stage below. Nothing is commented out. This directory holds
configuration that runs, not disabled HCL kept for illustration.

## What it creates

| Resource | Purpose |
|---|---|
| `aws_s3_bucket` | Holds the state object for every configuration root |
| `aws_s3_bucket_versioning` | Enabled. Prior object versions are the state recovery path |
| `aws_s3_bucket_server_side_encryption_configuration` | SSE-S3 with AES256 |
| `aws_s3_bucket_public_access_block` | All four block settings enabled |
| `aws_s3_bucket_policy` | Denies any request that arrives without TLS |

### Locking, as it currently stands

`backend.tf` carries `use_lockfile = true` and no `dynamodb_table`, so S3 native
locking is configured and in force for this root. Configured is not the same as
proven. Proving it needs a controlled contention test run against an isolated
test key or path, never against the active state object, and that test has not
been run. There is no DynamoDB table in this design to create, pay for, or
recover.

### Encryption, versioning, and tags

Encryption uses S3 managed keys. A customer-managed KMS key would add a
recurring charge, a second access-control surface, and its own lifecycle and
decommission duties. The accepted architecture requires encryption for state,
not customer key ownership, so the extra ownership is not taken on here.

Versioning runs without a noncurrent-version expiry rule. Those versions are
the recovery path, and expiring them would trade recovery history for a
negligible saving on objects this small.

The six mandatory tags are applied through the provider's `default_tags`. The
bucket is the only taggable AWS resource in this root. The other four are
configuration sub-resources of that bucket and carry no tags of their own.

## Input

Two required variables, neither with a default, both supplied at execution time
and neither committed. `terraform.tfvars.example` shows their shape with
placeholder values.

`state_bucket_name` names the bucket. S3 bucket names are globally unique, so
the real value belongs to whoever runs this. Choose a name that identifies the
platform and the bucket's purpose, that is unlikely to collide, and that
reveals nothing about the account behind it. A validation rule rejects anything
outside the S3 naming rule, and also rejects periods: they are legal in a bucket
name but break the wildcard certificate on virtual-hosted-style HTTPS requests,
and this bucket refuses plain HTTP.

`allowed_account_id` is the dedicated project account. The provider checks the
caller's account against it before doing anything, so running with a credential
for some other account fails immediately rather than creating this project's
first billable resource in the wrong place. The variable exists because the
account ID must not be committed, and the check exists because a globally
unique bucket name would otherwise succeed anywhere.

Neither variable is declared `sensitive`, and that is deliberate. The marking
controls display, not storage, so it would keep neither value out of state nor
out of a saved plan file. What it would do is replace the bucket name with
`(sensitive value)` in the plan, and under ADR-0003 the plan is the artifact the
owner reviews before approving an apply. Hiding the destination from that review
would weaken the one check that catches a wrong or mistyped target, in exchange
for protection it does not actually provide. Both values are kept out of the
repository by `.gitignore` instead, which is where that job belongs.

The bucket name is needed twice, at two different points in the sequence. First
as the variable that creates the bucket. Later as the `bucket` argument of the
backend that points at it, supplied through `backend.hcl` at migration step 5.
Both filled copies stay untracked. `backend.hcl` in particular is local only,
ignored by Git, and never committed.

## Execution sequence

The bucket did not exist on the first run, so the first run could not use the
backend that would need it. Two stages resolved that in order. They carried
separate approvals and neither was implied by the other. Both stages have been
carried out.

### Stage 1, create the bucket

1. Initialize the root on the default local backend with `terraform init`
2. Validate the configuration, then produce and review the plan
3. Under separate first-billable-resource authorization, apply the reviewed
   plan, with state still on local disk
4. Verify the bucket controls against AWS: versioning, encryption, the public
   access block, the bucket policy, and the tags

Step 3 created the first billable resource of this project.

### Stage 2, migrate state into the backend

1. Inspect and capture the current local state inventory
2. Take a private backup of the local `terraform.tfstate`, outside every
   repository
3. Add the active partial `backend.tf`
4. Verify that `backend.tf` carries the S3 backend, the expected bootstrap
   state key, us-east-1, `encrypt = true`, and `use_lockfile = true`, and that
   it carries no `dynamodb_table`
5. Run `terraform init -migrate-state -backend-config=backend.hcl`
6. Read the migration prompt and confirm it deliberately
7. Verify that Terraform reads the migrated remote state
8. Compare the migrated state inventory against the pre-migration inventory
9. Run a clean plan
10. Secure or remove the residual local state file, and only after remote state
    has been proven readable

**Do not use `-force-copy`.** It suppresses the migration confirmation, which
is the last moment a person can catch a wrong backend target before state
moves.

Backend initialization and state migration are one operation, not two. The
command in step 5 configures the backend and moves the state together, which
is why step 6 exists.

`backend.hcl` carries operator-specific values only, which today means the
bucket name. Stable backend behaviour, `use_lockfile` included, belongs in
`backend.tf` where a reviewer can see it in the repository.

The backend arrives as configuration that runs. Commenting a backend block out
to work around the ordering above would hide from review the one piece of
configuration that decides where state lives, and it would leave the repository
holding HCL that is not meant to execute.

## Access boundary, not yet demonstrated

This root declares a bucket and four settings on it. That is storage
configuration, and it says nothing about who may reach the state inside. No IAM
resource is declared here, so least-privilege access to the backend is not
demonstrated by these five resources.

Backend validation, when it runs, has to confirm that the executing identity
holds the permissions the backend actually needs, and no more:

- listing the bucket for the state prefix in use
- reading and writing the state object
- reading, writing, and deleting the `.tflock` object, once native locking is
  enabled

Bootstrap execution runs on the short-lived federated human credentials that
ADR-0005 already selected, which that record applies to bootstrap work
explicitly. That is the existing decision restated where it first applies, not
a new one.

## What the destruction protections do, and what they do not

`force_destroy = false` stops Terraform from emptying the bucket in order to
delete it. A bucket still holding state objects fails to destroy rather than
quietly taking the state with it.

`lifecycle { prevent_destroy = true }` makes Terraform reject any plan that
would destroy or replace this bucket. Lifting it requires editing this
configuration, which is a reviewable change rather than an accident.

Both are Terraform-side controls. Neither prevents a deletion made through the
console, the CLI, or any other path outside Terraform. That gap is real and is
stated here rather than papered over.

## Recovery

Terraform state is designated recoverable state under ADR-0011, and it is the
one control asset with no other source. Losing it leaves infrastructure
running, unmanaged, and still billing.

Recovery works from object versions:

1. list the versions of the state object
2. identify a usable prior version
3. restore that version
4. confirm Terraform can read the recovered state
5. inspect it
6. run a clean plan and confirm it matches the resources expected

`terraform import` is the fallback for the case where no usable version
remains. It rebuilds the binding between configuration and live resources. It
does not restore the original state object, and it does not reproduce that
object's serial, outputs, or recorded relationships. The two are not
equivalent, and describing import as a state restore overstates what it
recovers.

The recovery exercise ADR-0011 requires runs against an isolated test state
object, never against the only active state.

## Final decommission

ADR-0003 requires this backend to carry a decommission procedure of its own,
separate from any environment teardown. It is written before it is needed,
because the whole point is that nobody improvises it under pressure.

Decommission begins only when all six of these hold:

1. every environment Terraform root has itself been decommissioned
2. no active configuration still references this backend
3. the evidence that depends on this state has been captured
4. the state and recovery records that must be kept have been retained or
   exported to somewhere outside this bucket
5. the bucket holds no state that recovery could still need
6. the owner has explicitly approved final destruction of the backend

The controlled sequence, in order:

- confirm no consumer remains, by inspection rather than by assumption
- capture or export the state evidence that has to outlive the bucket
- lift the Terraform deletion protections through a reviewed code change, so
  that removing them is a visible commit rather than a console click
- empty the bucket completely, which happens only inside this procedure and
  never as a convenience step in any other workflow
- destroy the backend through Terraform
- verify that the bucket no longer exists
- run the residual, orphan, and cost checks that every teardown owes under
  REQ-004 and ADR-0013

**A versioned bucket is not empty when its objects look deleted.** Versioning is
what makes this state recoverable, and it is also what makes this step trip
people up. Deleting a current object in a versioned bucket removes no data. It
writes a delete marker and leaves every earlier version underneath it. The
bucket still holds the whole state history, still bills for it, and still
refuses to be deleted, because S3 will not delete a bucket that contains
anything at all. Emptying therefore means removing every object version and
every delete marker, not just the objects that are currently visible. Expect the
first deletion attempt to fail if that is missed, and read that failure as the
control working rather than as an obstacle to route around.

The exact commands belong to the decommission runbook written when this is
actually approved, not to this file. What is fixed here is the order and the
preconditions, because those are what make the operation safe. Until that day
`prevent_destroy` and `force_destroy = false` stay exactly as they are.

## Limitations

Two limits are worth stating in one place, because both are easy to read into
this configuration when they are not there.

**Terraform deletion protection is not an AWS-side boundary.** `prevent_destroy`
and `force_destroy = false` govern Terraform-driven workflows and nothing else.
An authorized Console, API, or CLI actor can still delete or reconfigure this
bucket outside Terraform, and neither control would stop it or notice it.

`prevent_destroy` is weaker than it first looks, because it lives in this
configuration rather than in AWS. Nothing is stored on the bucket marking it
protected. Delete the `lifecycle` block, or delete the resource block itself,
and the protection is gone on the very next plan. The real protection model is
therefore three things together: the setting, the code review that must approve
removing it, and the owner review that must approve the apply. What the setting
buys is that a destroy can no longer happen quietly. It has to arrive as a
visible diff first, and the two reviews are what act on that diff. Read alone it
resembles a lock. It is closer to a tripwire.

**This root does not establish the state access model.** What it does establish
is encryption at rest, TLS enforcement in transit, public-access prevention,
account targeting, and Terraform-side destruction control. What it does not
establish is who may read or write state, or any proof that state access is
audited. No IAM resource is declared here and no audit trail is configured or
verified, so this bucket is protected but not yet access-governed. Both belong
to the identity and access implementation and to its own evidence, not to this
root.

## Status

The state bucket exists. `terraform apply` created the five resources above,
`terraform state list` shows exactly those five, and the plan after apply
reported no changes. Versioning is enabled, default encryption is AES256, all
four public access block settings are true, and the bucket policy denies
requests that arrive without TLS.

State migration is complete. `terraform init -migrate-state` moved the local
state into the bucket at `bootstrap/terraform.tfstate`, the migrated inventory
matches the pre-migration inventory, and the plan after migration is still
clean. This root now runs on the S3 backend with `use_lockfile = true`.

Formatting, `terraform validate`, and the configured `tflint` static-analysis
step passed. Locking is configured but not proven under contention, and the
access boundary above remains undemonstrated.
