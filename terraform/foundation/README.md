# Evidence destination

Raw evidence has to outlive the environment that produced it. Environments are
created for an approved window and destroyed afterward, and raw evidence is
contemporaneous by nature, so anything left inside an environment is gone the
moment the teardown it documents completes. This root creates the durable
destination that problem needs.

It holds raw command output, exported logs, exported dashboards, and
screenshots: the system of record for the claims the public repository makes.
It is not a platform backup and not a running log store.

[ADR-0011](../../docs/decisions/0011-define-the-backup-and-recovery-model.md)
designates exported evidence as recoverable state, and
[architecture-baseline.md](../../docs/architecture-baseline.md) lists this
destination in the persistent-foundation register. This directory implements
that row.

## Why it is not in the bootstrap root

Both roots create an S3 bucket, which is the whole of what they have in common.
The bootstrap root exists to solve the ordering problem of a backend that cannot
store its own state, it is decommissioned last of everything, and a mistake in
its plan reaches the state of every other root. This root has none of those
properties, and keeping the two apart is what stops an error against evidence
from touching state, or the reverse.

Their state objects are separate for the same reason. ADR-0003 isolates state at
the configuration-root level, and `backend.tf` here uses the key
`foundation/terraform.tfstate`.

## What it creates

| Resource | Purpose |
|---|---|
| `aws_s3_bucket` | Holds the evidence objects |
| `aws_s3_bucket_versioning` | Enabled. An overwrite of contemporaneous evidence has to be recoverable |
| `aws_s3_bucket_server_side_encryption_configuration` | SSE-S3 with AES256 |
| `aws_s3_bucket_public_access_block` | All four block settings enabled |
| `aws_s3_bucket_policy` | Denies any request that arrives without TLS |

Encryption uses S3 managed keys. The accepted architecture requires evidence to
be encrypted at rest, not owned under a customer-managed key, and a KMS key
would add a recurring charge, a second access-control surface, and its own
lifecycle and decommission duties for no obligation this root has to meet.

## Retention is not decided yet

Versioning runs without a noncurrent-version expiry rule, and no lifecycle rule
bounds the bucket. That is deliberate rather than overlooked.
[ADR-0013](../../docs/decisions/0013-define-operations-and-cost-guardrails.md)
defers retention figures to implementation, and a guessed rule would delete
evidence on a schedule nobody approved. Retention has to be bounded so cost
stays bounded, and the rule is written before evidence volume becomes material,
not before the first object lands.

## Input

Two required variables, neither with a default, both supplied at execution time
and neither committed. `terraform.tfvars.example` shows their shape.

`evidence_bucket_name` names this bucket. Choose a name that identifies the
platform and the bucket's purpose, that is unlikely to collide, and that reveals
nothing about the account behind it. A validation rule rejects anything outside
the S3 naming rule, and also rejects periods: they are legal in a bucket name but
break the wildcard certificate on virtual-hosted-style HTTPS requests, and this
bucket refuses plain HTTP.

`allowed_account_id` is the dedicated project account. The provider checks the
caller's account against it before doing anything, so running with a credential
for another account fails immediately.

`backend.hcl` is a third value and a different one. It carries the **state**
bucket the bootstrap root created, which is where this root's own state object
goes. It is not this bucket. Both filled copies stay untracked.

## What the protections do, and what they do not

`force_destroy = false` stops Terraform from emptying the bucket in order to
delete it. `lifecycle { prevent_destroy = true }` makes Terraform reject any plan
that would destroy or replace it. Both are Terraform-side controls. Neither
prevents a deletion made through the console, the CLI, or any other path outside
Terraform.

**This root does not establish the evidence access model.** No IAM resource is
declared here, so who may read or write evidence is not expressed, and the
separation from the state backend's access path is a property of two distinct
buckets rather than of any policy written here. That separation belongs to the
identity implementation and to its own evidence.

## Recovery

Losing this bucket does not stop the platform from being rebuilt. What it
destroys is the project's ability to support claims it has already published,
and evidence cannot be reproduced after the fact because it must be
contemporaneous.

Recovery works from object versions: list the versions of the affected object,
identify a usable prior version, restore it, and confirm the restored object is
the evidence the claim referenced. There is no import fallback here, because
unlike Terraform state there is nothing to rebind. An object with no usable
version is lost, and the honest response is to withdraw the claim it supported
rather than reconstruct it.

## Final decommission

This bucket is decommissioned at project end and not before, once its contents
are no longer needed to support a public claim.

Decommission begins only when all of these hold:

1. every claim in the public repository is supported by sanitized evidence held
   there, or has been withdrawn
2. no environment window is open and none is planned
3. anything that has to outlive this bucket has been exported somewhere else
4. the owner has explicitly approved final destruction

Then, in order: confirm no remaining claim depends on it, export what has to
survive, lift the Terraform deletion protections through a reviewed code change,
empty the bucket including every object version and every delete marker, destroy
it through Terraform, verify it no longer exists, and run the residual and cost
checks every teardown owes under REQ-004 and ADR-0013.

A versioned bucket is not empty when its objects look deleted. Deleting a current
object writes a delete marker and leaves every earlier version underneath it, so
the bucket still bills and still refuses to be deleted.

## Status

The evidence bucket exists. `terraform apply` created the five resources above,
the plan after apply reported no changes, and this root runs on the S3 backend
at `foundation/terraform.tfstate`. Versioning is enabled, default encryption is
AES256, all four public access block settings are true, the bucket policy denies
requests without TLS, and the six mandatory tags are present.

Formatting, `terraform validate`, and `tflint` passed. Bounded retention is still
undecided, and the access boundary above remains undemonstrated.
