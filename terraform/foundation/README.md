# Persistent shared foundations

This root holds the platform's persistent shared foundations: the resources
whose lifecycle and recovery duties outlive every environment window. Three are
declared here: the durable evidence destination, the artifact registry, and the
public DNS zone. The sections through Final decommission describe the evidence
destination, and the sections after them cover the other two.

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

## Evidence retention is not decided yet

Versioning runs without a noncurrent-version expiry rule, and no lifecycle rule
bounds the bucket. That is deliberate rather than overlooked.
[ADR-0013](../../docs/decisions/0013-define-operations-and-cost-guardrails.md)
defers retention figures to implementation, and a guessed rule would delete
evidence on a schedule nobody approved. Retention has to be bounded so cost
stays bounded, and the rule is written before evidence volume becomes material,
not before the first object lands.

## Input

Four required variables, none with a default, all supplied at execution time and
none committed. `terraform.tfvars.example` shows their shape.

`evidence_bucket_name` names this bucket. Choose a name that identifies the
platform and the bucket's purpose, that is unlikely to collide, and that reveals
nothing about the account behind it. A validation rule rejects anything outside
the S3 naming rule, and also rejects periods: they are legal in a bucket name but
break S3's own wildcard certificate on virtual-hosted-style HTTPS requests, and this
bucket refuses plain HTTP.

`allowed_account_id` is the dedicated project account. The provider checks the
caller's account against it before doing anything, so running with a credential
for another account fails immediately.

`gitlab_project_id` is the numeric ID of the GitLab project whose main-branch
pipelines may assume the CI push role.

`public_domain` is the registered apex domain for the public hosted zone,
lowercase and without a trailing dot. It is an owner-private input.

`backend.hcl` is a separate value and a different one. It carries the **state**
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

## Artifact registry

[ADR-0009](../../docs/decisions/0009-define-the-software-delivery-model.md)
declares Amazon ECR a persistent shared foundation: one repository per owned
service, created when that service enters the implemented delivery path.
checkout is the approved first-digest service. This root declares the
`astroshop/` workload repositories over one set, because they differ only by
name, and one `platform/` repository for the mirrored OpenTelemetry Collector
image separately. Every `astroshop/` repository carries the same lifecycle
policy. `platform/opentelemetry-collector` deliberately carries none and is
excluded from the CI push policy, because a mirrored image is not published by
the workload pipeline; keeping it outside the set is what makes that exclusion
structural rather than a list that happens to omit it.

The `astroshop/` prefix is the workload-artifact naming convention, covering the
services this project builds from source. The `platform/` prefix keeps a
third-party platform component out of that namespace, because the Collector is
pinned under ADR-0006 through ADR-0010 rather than the ADR-0012 workload rules.
In both cases the slash is part of the name and nothing more: it creates no
policy namespace and no security boundary in ECR.

| Resource | Purpose |
|---|---|
| `aws_ecr_repository` | The `astroshop/` workload repositories declared over one set, plus `platform/opentelemetry-collector` declared separately. Immutable tags, encryption at rest under an AWS-managed key, native scan-on-push off because Trivy owns the scanning gate |
| `aws_ecr_lifecycle_policy` | Bounds storage on every `astroshop/` repository with a count-based rule: the newest 10 tagged images are retained, and older ones expire only once the count passes 10. The Collector repository carries no lifecycle policy, because it is consumed by immutable digest and a tag-count rule could expire a digest still referenced |

Its purpose is to retain immutable workload artifacts across environment
lifecycles, so promotion moves a digest that already passed its gates instead
of rebuilding. The platform engineer role owns it through Terraform. It is
excluded from routine environment teardown. Its recovery path is rebuild from
source through the delivery pipeline, not restore from backup, because source
is authoritative. Its decommission path is deletion once no environment
references its images, through a deliberate reviewed change. `force_delete =
false` refuses to destroy the repository while images remain, and there is no
`prevent_destroy` here, because that refusal already blocks the destroy that
matters and the decommission path needs no further friction.

The latest-10 retention count is an initial bound for this reference project,
not a measured or production-derived figure. It carries one owner-review
trigger: before an eleventh tagged image is published to `astroshop/checkout`,
the owner reviews whether the Phase 6 first-digest artifact must stay retained
or whether its expiry is acceptable, because once the count exceeds 10 the
oldest applicable tagged image becomes the first expiry candidate. This is a
bounded review trigger, not an exemption mechanism, and nothing implements it
in the policy itself.

ECR cost is usage and storage dependent. Current pricing has been reviewed
separately, and no measured or attributable ECR cost has been observed yet.
The lifecycle policy provides an initial image-count bound, not measured cost
evidence.

The registry is currently required to produce and retain the Phase 6 first
immutable workload artifact digest, which is the evidence that it is still
needed. The shipping and quote repositories are declared because a project
pipeline for both services has been authored as a prerequisite of later work,
and the Collector repository is declared because that work requires its image
mirrored into this registry rather than pulled from an external one at pod
start. All three have since been performed: shipping and quote publish through
their own pipelines by digest, and the Collector image is mirrored into its
repository. `astroshop/image-provider` now holds one image, published by its
own pipeline and read back from this registry by digest; `astroshop/frontend-proxy`
is wired for the same path and holds no image yet. `astroshop/cart`,
`astroshop/frontend`, `astroshop/payment` and `astroshop/product-catalog` are
declared because each now has a build-and-scan pipeline; none holds an image until
its publication is separately authorized. Components without a pipeline are
absent: membership follows the delivery path ADR-0009 describes, not the fleet
inventory.

## CI push identity

Pushing to those repositories needs an AWS identity, and ADR-0009 puts pipeline
identity on OIDC federation, so this root also declares the trust anchor for
GitLab.com ID tokens and one role for the project's publication pipelines. The
pipeline exchanges its job token for short-lived STS credentials; no long-lived
AWS credential exists in CI.

One role rather than one per service. The subject claim this role trusts carries
the GitLab project and the ref and nothing that separates one service's pipeline
from another's, and checkout, shipping, quote and image-provider publish from
the same project on the same branch. Per-service roles would carry identical
trust conditions, so a
job able to assume one could assume any of them, and the separation would be in
name only. The permission boundary is the repository list below.

The trust is pinned to one GitLab project on branch `main` and to one
audience, so a token from another project, branch, tag, or merge-request
pipeline cannot assume the role. The project is identified by its immutable
GitLab project ID, supplied as a Terraform input and uncommitted, like the
other values this root takes.

The role's permissions are push side only: authenticate to the registry,
upload layers, publish a manifest, scoped to the declared `astroshop/`
repositories. The list is derived from the same set that declares them, so a
repository cannot enter the registry and be forgotten in the policy. Only the registry-level authentication
call is unscoped, because it accepts no repository ARN. Adding a repository to the set
widens only that resource list; it adds no action and changes no trust condition.
`platform/opentelemetry-collector` is absent from that list because it is not
a member of that set, so this role cannot push the Collector mirror; that mechanism is a separate
identity question and is not implemented here. Nothing here grants repository
deletion, lifecycle-policy mutation, IAM, or any other service. The permissions
the observed checkout push path required were exercised successfully by that
push; the set as a whole is not claimed to have been exhaustively exercised,
and shipping, quote and image-provider have since pushed through the same
identity.
Environment pull access is a separate identity concern and is not implemented
here.

## Public DNS

`dns.tf` creates one public hosted zone for the registered apex domain, which
[ADR-0018](../../docs/decisions/0018-define-the-public-entry-implementation-dns-and-certificate-model.md)
places in this root as a persistent shared foundation; the
[architecture baseline](../../docs/architecture-baseline.md) records its purpose,
recovery and lifecycle. The domain is the owner-private input `public_domain` and
is never committed. Environment records are to be created inside a window by the
record controller ADR-0018 requires, which is not implemented yet; this root
creates none.

No role this repository declares can write the zone. Until the record
controller's role exists, scoped to this zone alone, write access comes only from
administrative access to the account, and whoever can write the zone can have a
certificate issued for the domain. The zone is needed for as long as the platform
serves a public HTTPS endpoint under that domain.

The zone is applied on its own first. The registrar is then pointed at the four
name servers in the `public_zone_name_servers` output, and the certificate is
added only once the parent zone answers with them, because its DNS validation
depends on that delegation.

`certificate.tf` adds one ACM public certificate for the apex and a wildcard
beneath it, non-exportable so it carries no charge, validated through a record
in the zone. That record stays after validation, because ACM renews the
certificate through it.

A rebuild from nothing follows the same order, because a recreated zone gets new
name servers: `terraform apply -target=aws_route53_zone.public`, set the name
servers at the registrar and confirm the parent answers with them, then run the
full apply.

`prevent_destroy` guards the zone. To retire it, point the registrar elsewhere
first, wait out the longer of the parent's name-server TTL and the zone's own NS
TTL (172800 seconds in Route 53), then lift the guard in a reviewed change and
destroy. Retire the certificate first, once no listener uses it; the zone deletes
only when its NS and SOA records alone remain.

The zone costs 0.50 USD a month, not prorated, so the month of creation is
charged in full, plus 0.40 USD per million queries. The certificate is free.

## Status

The evidence bucket exists. `terraform apply` created the five evidence
resources, the plan after apply reported no changes, and this root runs on the
S3 backend at `foundation/terraform.tfstate`. Versioning is enabled, default
encryption is AES256, all four public access block settings are true, the
bucket policy denies requests without TLS, and the six mandatory tags are
present. Formatting, `terraform validate`, and `tflint` passed against that
evidence-only configuration, and evidence retention remains undecided.

The artifact registry is applied. `astroshop/checkout` exists as the first
artifact-registry repository together with its lifecycle policy: the apply
added those two resources and nothing else, AWS read-back verified the
declared repository configuration, the lifecycle policy, and the six
mandatory tags, and the plan after apply reported no changes. At that validation
the repository held one image, tag `bf07e2ea`, digest
`sha256:ff23800f3e82d75d1bf79331aae337a72bfff50f62c2d33746d02c7c535b8365`. The
checkout build and delivery path is validated.

The CI push identity is applied. The GitLab OIDC provider, the checkout role
and its inline push policy exist: the apply added those three resources and
nothing else, and the plan after apply reported no changes. AWS read-back
verified one trust statement allowing `sts:AssumeRoleWithWebIdentity` with the
audience pinned to `sts.amazonaws.com` and the subject pinned to
`project_id:<project-id>:ref_type:branch:ref:main`, no attached managed policy, one
inline policy, and the six mandatory tags.

A pipeline has assumed the role and pushed, so end-to-end OIDC authentication
is proven for the checkout push path. The access boundary of the evidence
destination remains undemonstrated.

The public DNS zone is applied: the apply added the hosted zone and nothing
else, AWS read-back verified a public zone with four assigned name servers and
the six mandatory tags, and the plan after apply reported no changes. The
parent zone now answers with those four name servers, so the registrar delegates
the domain to this zone.

The certificate is applied: the apply added the certificate, its validation
record and Terraform's validation step and nothing else. AWS read-back verified
an issued certificate for the apex and one wildcard, both validated through DNS,
not exportable, with the six mandatory tags; the zone holds only its NS and SOA
records and the one validation CNAME, with a TTL of 300 seconds; and the plan
after apply reported no changes. No AWS resource uses the certificate yet, and
ACM reports it as not eligible for managed renewal.
