# Persistent Foundation Operations

## Scope

This runbook covers recurring operation and verification of three persistent foundations
declared in [`terraform/foundation`](../../terraform/foundation/README.md): the evidence store,
the artifact registry, and the CI push identity. What each one is, why it exists, its inputs,
its protections, its recovery path and its final decommission order are in that README and
are not repeated here. The persistent-foundation register is in the
[architecture baseline](../architecture-baseline.md#persistent-foundations).

It links, rather than owns:

- plan, apply, convergence, drift, refresh-only reconciliation, locks and interrupted applies:
  [terraform-operations.md](terraform-operations.md);
- evidence export, read-back after teardown, redaction and object-version restore:
  [evidence-handling.md](evidence-handling.md);
- the budget, pricing re-checks and registry storage cost: [cost-and-residue.md](cost-and-residue.md);
- the hosted zone and certificate in the same root: [public-dns-and-certificate.md](public-dns-and-certificate.md);
- signing in and confirming the account: [operator-access.md](operator-access.md);
- how a pipeline publishes through the push identity:
  [GitOps Delivery](../implementation/gitops-delivery.md#1-build-once-gitlab-ci-to-an-immutable-digest)
  and the workload repository's
  [`ecr-publish.yml`](https://gitlab.com/tuinzaman/cloud-platform-workload/-/blob/main/ci/templates/ecr-publish.yml).

This suite publishes no procedure for mirroring a third-party platform image into the
`platform/` namespace. The Collector image in `platform/opentelemetry-collector` was mirrored on
2026-09-07: copied by its single-platform digest, not the multi-platform index, from the
administrator session outside CI, because the push role cannot reach that repository
([CI push identity](../../terraform/foundation/README.md#ci-push-identity)), and then checked by
manifest hash. Its admission belongs to
[ADR-0015](../decisions/0015-define-security-admission-and-exception-governance-for-platform-managed-runtime-components.md)
and the pin-and-mirror rule of
[ADR-0017](../decisions/0017-adopt-a-full-fleet-end-to-end-platform-validation-program.md), which
this suite does not cover yet. An engineer rebuilding the platform therefore has no public
procedure for populating that repository, and it must hold the pinned image by digest before any
runtime uses it.

Placeholders: `<profile>`; `<evidence-bucket>` and `<allowed-account-id>`, the root's
`evidence_bucket_name` and `allowed_account_id` [inputs](../../terraform/foundation/README.md#input);
`<project-id>`, the GitLab project's numeric ID and the root's `gitlab_project_id`; and
`<service>`, `<repository>`, `<digest>` and `<tag>`. Each command sets its output format, so the
expected results do not depend on the profile's default. Successful output is projected with
`--query` or `jq` and contains no ARN and no account ID. Error messages are not projected: ECR's
not-found errors can name the registry ID, which is the account ID, so redact error output at
capture ([evidence-handling.md](evidence-handling.md)).

Every recorded operator read-only check in this runbook ran on the administrator permission set.
The 2026-09-17 manifest was read by the CI publish job on the push role. None has run on the
ReadOnly permission set that [operator-access.md](operator-access.md) prescribes for inspection.

## Procedures

### Read back the evidence-store controls

| Field | Value |
|---|---|
| Validation status | EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-08) |
| Published form | not executed as written (derived from the controls recorded as read back after the 2026-08-08 apply and from [`evidence-store.tf`](../../terraform/foundation/evidence-store.tf); no command was retained) |
| Evidence basis | [README Status](../../terraform/foundation/README.md#status). The full check was recorded as an outcome on 2026-08-08, and versioning alone on 2026-08-14 before the first evidence upload; the output of neither is retained. |
| Authority | None (read-only) |
| Cost | None |

- **Purpose.** Confirm that the evidence bucket still carries the controls listed in
  [What it creates](../../terraform/foundation/README.md#what-it-creates) and the six mandatory
  tags.
- **Preconditions.** A signed-in profile for the project account, confirmed as described in
  [operator-access.md](operator-access.md).
- **Inputs.** `<evidence-bucket>`, `<profile>`.
- **Procedure.**
  1. Versioning:
     ```
     aws s3api get-bucket-versioning --bucket <evidence-bucket> --profile <profile> \
       --query Status --output text
     ```
  2. Default encryption:
     ```
     aws s3api get-bucket-encryption --bucket <evidence-bucket> --profile <profile> \
       --query 'ServerSideEncryptionConfiguration.Rules[].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
       --output text
     ```
  3. Public access block:
     ```
     aws s3api get-public-access-block --bucket <evidence-bucket> --profile <profile> \
       --query PublicAccessBlockConfiguration --output json
     ```
  4. Bucket policy, statement fields only, because the resource field carries the bucket name:
     ```
     aws s3api get-bucket-policy --bucket <evidence-bucket> --profile <profile> \
       --query Policy --output text |
       jq '{statements: (.Statement | length), content: [.Statement[] | {Sid, Effect, Principal, Action, Condition}]}'
     ```
  5. Tags:
     ```
     aws s3api get-bucket-tagging --bucket <evidence-bucket> --profile <profile> \
       --query 'TagSet[].[Key,Value]' --output text
     ```
- **Expected result.**
  1. `Enabled`.
  2. `AES256`.
  3. `BlockPublicAcls`, `IgnorePublicAcls`, `BlockPublicPolicy` and `RestrictPublicBuckets` are all `true`.
  4. Exactly one statement: `Sid` `DenyUnencryptedTransport`, `Effect` `Deny`, `Principal` `*`,
     `Action` `s3:*`, and the condition `Bool` `aws:SecureTransport` = `"false"`.
  5. Exactly six tags: `Project` `cloud-platform-reference`, `Environment` `shared`, `Component`
     `evidence-store`, `Lifecycle` `persistent`, `Owner` `platform-engineer`, `ManagedBy` `terraform`.
- **Validation.** A plan of the foundation root that reports no changes
  ([terraform-operations.md](terraform-operations.md)) confirms the same five resources from
  Terraform's side.
- **Evidence to retain.** The output of the five commands, captured privately
  ([evidence-handling.md](evidence-handling.md)).
- **STOP conditions.** Any value differs from the expected result. Treat the difference as drift
  ([terraform-operations.md](terraform-operations.md)) and resolve it before exporting more
  evidence to the bucket.
- **Known limitations.**
  - The TLS-only rule has been verified only by reading the policy text. No request over plain
    HTTP has been sent to confirm that S3 refuses it.
  - The last full read-back is the 2026-08-08 record. Later records that restate these values
    without a retained capture are not counted as read-backs.
  - The controls say nothing about who may read or write evidence, because the access model is
    not implemented ([What the protections do](../../terraform/foundation/README.md#what-the-protections-do-and-what-they-do-not)),
    and no retention rule exists yet ([Evidence retention](../../terraform/foundation/README.md#evidence-retention-is-not-decided-yet)).
- **Next gate.** The first run of this form with its output retained.

### Add a registry repository and widen the CI push scope

| Field | Value |
|---|---|
| Validation status | DESIGNED-NOT-EXECUTED (never, against the current root) |
| Published form | not executed as written (derived from the applies executed 2026-09-02, 2026-09-17 and 2026-09-22; the 2026-09-22 apply and read-back ran through a private reviewed tool on exported credentials; the hosted-zone, certificate and `public_domain` criteria below, and the order of steps 8 and 9, were never part of an executed run) |
| Evidence basis | [Artifact registry](../../terraform/foundation/README.md#artifact-registry), [CI push identity](../../terraform/foundation/README.md#ci-push-identity) and [Status](../../terraform/foundation/README.md#status). The 2026-09-17 and 2026-09-22 applies and read-backs are retained as private evidence. The 2026-09-02 apply and read-back are recorded as outcomes only; its reviewed plan is retained. All three predate the hosted zone (2026-09-23) and the certificate, and ran before `public_domain` was a declared input. |
| Authority | Explicit owner grant for the ECR and IAM mutation. A refresh-only apply in step 9 needs its own explicit approval of that refresh-only plan, because applying it writes state. |
| Cost | None while the new repository holds no image; ECR then bills stored image data ([cost-and-residue.md](cost-and-residue.md)) |

- **Purpose.** Give a service that has entered the delivery path its own `astroshop/`
  repository, and let the CI push identity publish to it. Membership follows the delivery path,
  not the fleet inventory ([Artifact registry](../../terraform/foundation/README.md#artifact-registry)).
- **Preconditions.**
  - The service has a build-and-scan pipeline in the workload repository
    ([Artifact registry](../../terraform/foundation/README.md#artifact-registry)). Wiring its
    publish job with `ECR_REPOSITORY: astroshop/<service>` comes after the repository exists and
    belongs to the publication path, outside this runbook.
  - A written owner grant for this change.
  - The foundation root is initialized against its backend, and all four inputs, including
    `public_domain`, are in the untracked `terraform.tfvars`
    ([Input](../../terraform/foundation/README.md#input)).
- **Inputs.** `<service>`, `<profile>`.
- **Procedure.**
  1. Record the registry inventory:
     ```
     for repository in $(aws ecr describe-repositories --profile <profile> \
         --query 'repositories[].repositoryName' --output text); do
       printf '%s %s\n' "${repository}" "$(aws ecr describe-images --repository-name "${repository}" \
         --profile <profile> --query 'length(imageDetails)' --output text)"
     done
     ```
  2. Add `"<service>"` to `local.workload_repositories` in
     [`artifact-registry.tf`](../../terraform/foundation/artifact-registry.tf) and change nothing
     else. The push policy's resource list derives from that set.
  3. Run the static checks and create a reviewed saved plan
     ([terraform-operations.md](terraform-operations.md)). Accept the plan only if it holds exactly:
     - a create of `aws_ecr_repository.workload["<service>"]` and of
       `aws_ecr_lifecycle_policy.workload["<service>"]` for each added name;
     - one in-place update of `aws_iam_role_policy.ci_checkout_ecr_push`;
     - nothing else: no destroy, no replace, no output change, and no change to
       `aws_iam_role.ci_checkout`, `aws_iam_openid_connect_provider.gitlab`,
       `aws_ecr_repository.collector`, any evidence-store resource, `aws_route53_zone.public`,
       `aws_acm_certificate.public`, `aws_route53_record.certificate_validation` or
       `aws_acm_certificate_validation.public`.

     The planned policy document shows as known after apply, because the new repository's ARN
     does not exist yet (observed 2026-09-17), so step 6 confirms the scope. If the plan reports
     that `aws_iam_role.ci_checkout` changed outside Terraform, stop: that is drift left by an
     earlier change, not part of this one. Explain it and reconcile it through
     [terraform-operations.md](terraform-operations.md) under its own approval, then plan this
     change again.
  4. Apply exactly that saved plan ([terraform-operations.md](terraform-operations.md)).
  5. Read back each new repository:
     ```
     aws ecr describe-repositories --repository-names astroshop/<service> --profile <profile> \
       --query 'repositories[].{name:repositoryName,mutability:imageTagMutability,encryption:encryptionConfiguration.encryptionType,scanOnPush:imageScanningConfiguration.scanOnPush}' \
       --output json
     aws ecr get-lifecycle-policy --repository-name astroshop/<service> --profile <profile> \
       --query lifecyclePolicyText --output text
     aws ecr list-tags-for-resource --profile <profile> \
       --resource-arn "$(aws ecr describe-repositories --repository-names astroshop/<service> \
         --profile <profile> --query 'repositories[0].repositoryArn' --output text)" \
       --query 'tags[].[Key,Value]' --output text
     ```
  6. Run [Read back the CI push scope](#read-back-the-ci-push-scope).
  7. Repeat step 1 and compare it with the first run.
  8. Run the convergence plan (Confirm convergence in
     [terraform-operations.md](terraform-operations.md)).
  9. Run the refresh-only drift check (Detect state drift in
     [terraform-operations.md](terraform-operations.md)). If it reports no drift, the procedure
     ends. If its only drift is `aws_iam_role.ci_checkout` attribute `inline_policy`, and the live
     policy read in step 6 equals the configured one, it is the known state lag: reconcile it
     through Reconcile explained state-only drift in the same runbook, which binds the
     refresh-only plan and needs its own explicit owner approval before that plan is applied.
- **Expected result.**
  - Step 5: `IMMUTABLE`, `AES256`, `scanOnPush` `false`; a lifecycle policy with one rule that
    expires `tagged` images matching `*` once `imageCountMoreThan` 10; and exactly the six tags
    listed for the evidence store, except `Component` `artifact-registry`.
  - Step 6: the new repository is in scope and nothing else changed.
  - Step 7: every repository that existed before keeps its image count, and each new one holds 0.
  - Step 8: exit 0 and no changes.
  - Step 9: no drift, or only the role's `inline_policy` lag; after any reconciliation the drift
    check exits 0.
- **Evidence to retain.** The saved plan, the plan and apply logs, and the read-back output, all
  held privately. Plan and apply output prints the evidence bucket name and account identifiers
  (observed), so none of it is published ([evidence-handling.md](evidence-handling.md)).
- **STOP conditions.**
  - The plan holds any address, action or count outside step 3, or reports that
    `aws_iam_role.ci_checkout` changed outside Terraform.
  - An existing repository's image count changes.
  - The push scope lists `platform/opentelemetry-collector`, a wildcard repository, or any action
    beyond those in [Read back the CI push scope](#read-back-the-ci-push-scope).
  - The convergence plan in step 8 exits 1 or 2.
  - The drift check in step 9 reports anything other than the role's `inline_policy`, or the
    live policy differs from the configured one.
- **Failure handling.** An apply that stops partway follows the interrupted-apply procedure in
  [terraform-operations.md](terraform-operations.md).
- **Recovery / rollback.** Not exercised; see [Not yet exercised](#not-yet-exercised).
- **Known limitations.**
  - After the 2026-09-17 apply an ordinary plan exited 0 while Terraform's copy of the push policy
    under `aws_iam_role.ci_checkout` was already stale. The lag surfaced only in the next plan,
    on 2026-09-21, and step 9 exists for that reason. The same lag after the 2026-09-22 apply was
    reconciled that day by a separately approved refresh-only apply that changed no AWS resource.
  - The owner accepted the 2026-09-21 lag note for that one saved plan only; it is not a standing
    exception for later plans.
- **Next gate.** Wiring the service's publish job and its first publication, both outside this
  runbook ([GitOps Delivery](../implementation/gitops-delivery.md#1-build-once-gitlab-ci-to-an-immutable-digest)).

### Verify an image in the registry by digest

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-10) |
| Published form | not executed as written (the `describe-images` and `batch-get-image` reads are the forms executed 2026-09-10, with a `--query` projection, an output format and a profile added; like that run, `batch-get-image` omits the `--accepted-media-types` that the public [`ecr-publish.yml`](https://gitlab.com/tuinzaman/cloud-platform-workload/-/blob/main/ci/templates/ecr-publish.yml) passes; only the hash step's byte handling, `printf '%s'` of the command-substituted manifest, follows that template) |
| Evidence basis | Retained private evidence of the 2026-09-10 read-only registry check, in which four pinned digests were found by digest and one manifest's SHA-256 was compared with its digest. The same comparison is retained for the mirrored Collector image on 2026-09-07, and for an image published by CI on 2026-09-17 whose manifest bytes the publish job itself fetched on the push role. |
| Authority | None (read-only) |
| Cost | None |

- **Purpose.** Confirm that the registry holds an image under the digest a pin or a pipeline
  artifact names, and that the manifest it returns hashes to that digest.
- **Preconditions.** A signed-in profile for the project account ([operator-access.md](operator-access.md)).
- **Inputs.**
  - `<repository>`, for example `astroshop/checkout`.
  - `<digest>` as `sha256:<hex>`, taken from the publish job's `digest.txt` artifact or from the
    digest pin in your own GitOps images file
    ([GitOps Delivery](../implementation/gitops-delivery.md#3-pinning-by-digest)).
  - `<tag>`: for an image CI published, the publishing commit's short SHA
    (`CI_COMMIT_SHORT_SHA` in the publish template); for a mirrored image, the upstream version tag.
- **Procedure.**
  1. Find the image by digest:
     ```
     aws ecr describe-images --repository-name <repository> --image-ids imageDigest=<digest> \
       --profile <profile> \
       --query 'imageDetails[].{digest:imageDigest,tags:imageTags,pushedAt:imagePushedAt,mediaType:imageManifestMediaType}' \
       --output json
     ```
  2. Hash the exact manifest bytes. Command substitution drops the newline the CLI appends to
     text output, and `printf '%s'` writes the rest unchanged:
     ```
     manifest=$(aws ecr batch-get-image --repository-name <repository> \
       --image-ids imageDigest=<digest> --profile <profile> \
       --query 'images[0].imageManifest' --output text)
     printf '%s' "${manifest}" | shasum -a 256
     ```
- **Expected result.** Step 1 returns one image whose digest equals `<digest>` and whose tags
  include `<tag>`. Step 2 prints `<hex>  -`, where `<hex>` is the part of `<digest>` after
  `sha256:`.
- **Evidence to retain.** Both outputs, captured privately, with any error text redacted.
- **STOP conditions.** `ImageNotFoundException`, or a hash that differs from `<digest>`. Do not rely
  on the digest until the difference is explained. A missing image returns no manifest, so its
  hash cannot match.
- **Known limitations.**
  - A manifest that ends in a newline would lose it in step 2 and fail the comparison. That gives
    a false failure, never a false pass, and has not been observed.
  - Exercised only on Docker schema-2 manifests (`application/vnd.docker.distribution.manifest.v2+json`).
    The read omits the `--accepted-media-types` the publish template passes, and its behaviour for
    OCI manifests or image indexes has not been measured. A different manifest returned there
    would fail the comparison, not pass it.
  - The check proves which bytes the registry holds. It says nothing about the image's scan
    result or provenance.

### Connect a GitLab project to the CI push identity

| Field | Value |
|---|---|
| Validation status | EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-15) |
| Published form | not executed as written (derived from [`ci-identity.tf`](../../terraform/foundation/ci-identity.tf), the public publish template and the outcomes recorded 2026-08-15; the GitLab-side change was made through the GitLab API and that call was not retained) |
| Evidence basis | [CI push identity](../../terraform/foundation/README.md#ci-push-identity) and [Status](../../terraform/foundation/README.md#status). The provider, role and policy creation, and the trust change from project path to project ID, are recorded as outcomes on 2026-08-15 without retained output. That trust change re-pinned the same project. Later publications through the identity, including retained private evidence of one on 2026-09-17, show indirectly that the trust admits a main-branch job. The GitLab setting is not AWS evidence. |
| Authority | Explicit owner grant (IAM trust change and GitLab project settings) |
| Cost | None (the OIDC provider, role and inline policy carry no direct charge) |

- **Purpose.** Let main-branch pipelines of exactly one GitLab project exchange their ID token for
  short-lived credentials on the push role ([ADR-0009](../decisions/0009-define-the-software-delivery-model.md)).
- **Preconditions.**
  - The foundation root is applied. A first build follows the order the
    [README](../../terraform/foundation/README.md#public-dns) gives, but no plan shape for that
    build is published ([Not yet exercised](#not-yet-exercised)).
  - GitLab API access that can change the project's settings, and access to its CI/CD variables
    ([Hidden prerequisites](#hidden-prerequisites)).
  - A written owner grant.
- **Inputs.** `<project-id>`, read from the project's Settings, General page;
  `<allowed-account-id>`.
- **Procedure.**
  1. In GitLab, set the project attribute `ci_id_token_sub_claim_components` to `project_id`,
     `ref_type`, `ref`, and read it back. The read-back must be `["project_id", "ref_type", "ref"]`.
     GitLab's default subject names the project path, while the trust pins the project ID, so
     without this setting no job can assume the role. On 2026-08-15 the setting was changed
     through the GitLab API with a temporary project access token, which was revoked after the
     read-back. The exact call, the token's role and scope, and whether the GitLab UI exposes the
     setting were not recorded.
  2. Set `gitlab_project_id = <project-id>` in the root's untracked `terraform.tfvars`.
  3. Plan and apply the foundation root ([terraform-operations.md](terraform-operations.md)). For a
     trust change on an existing root, accept only one in-place update of
     `aws_iam_role.ci_checkout`, the shape recorded for the 2026-08-15 change from project path to
     project ID (0 added, 1 changed, 0 destroyed), followed by a plan with no changes. That change
     re-pinned the same project and ran before the hosted zone, the certificate and
     `public_domain` existed. No acceptance shape exists for a first build.
  4. Run [Read back the CI trust](#read-back-the-ci-trust) and
     [Read back the CI push scope](#read-back-the-ci-push-scope).
  5. In the GitLab project, create two masked CI/CD variables:
     - `AWS_ROLE_ARN`: `arn:aws:iam::<allowed-account-id>:role/cloud-platform-reference-shared-ci-checkout`
     - `ECR_REGISTRY`: `<allowed-account-id>.dkr.ecr.us-east-1.amazonaws.com`, the registry host
       only and never a repository path

     Each service whose publish job is wired sets `ECR_REPOSITORY` in its `ci.yml` to its own
     `astroshop/<service>`.
  6. Keep `environment:` off every publish job. It changes the ID token's subject, which the trust
     matches exactly, as the comments in `ci-identity.tf` and `ecr-publish.yml` state; this has not
     been observed in a run.
- **Expected result.** Both read-backs in step 4 match their expected results. The first manual
  publish job on `main` then proves the chain; running it is outside this runbook
  ([GitOps Delivery](../implementation/gitops-delivery.md#1-build-once-gitlab-ci-to-an-immutable-digest)).
- **STOP conditions.**
  - For a trust change, the plan touches anything other than the role's trust.
  - The trust read-back fails its expected result.
- **Recovery / rollback.** Revoking or rotating the trust is not exercised; see
  [Not yet exercised](#not-yet-exercised).
- **Known limitations.**
  - The reference project marks both variables masked. Whether they are also protected was not
    recorded.
  - No trust read-back has ever been retained; the last recorded one is 2026-08-15. See
    [Read back the CI trust](#read-back-the-ci-trust).
  - The trust pins exactly one subject. Setting a different `gitlab_project_id` on an existing
    root replaces the trusted project and disconnects the previous one. That has never been
    executed.
  - No trust change has run against the current root, with the hosted zone, the certificate and
    `public_domain` present.
- **Next gate.** The first publication from the connected project.

### Read back the CI trust

| Field | Value |
|---|---|
| Validation status | EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-15) |
| Published form | not executed as written (derived from the check list in [Status](../../terraform/foundation/README.md#status); step 1's provider URL, client-ID and tag read is derived from [`ci-identity.tf`](../../terraform/foundation/ci-identity.tf) and has no recorded execution; no command was retained) |
| Evidence basis | [Status](../../terraform/foundation/README.md#status). The check list (trust statement, audience, subject, absence of managed policies, single inline policy, six tags) was recorded when the identity was created, against the earlier project-path subject. The 2026-08-15 change to the project ID is recorded as an outcome: the new subject, the unchanged audience and `StringEquals` operator, and no wildcard. Which of the other items were read again after that change is not recorded. No later retained capture verifies the trust: the 2026-09-10 reads listed the provider and the role's name and creation date, and later Terraform refreshes of the role are not trust read-backs. |
| Authority | None (read-only) |
| Cost | None |

- **Purpose.** Confirm that only main-branch jobs of the one pinned GitLab project, presenting the
  pinned audience, can assume the push role.
- **Preconditions.** A signed-in profile for the project account ([operator-access.md](operator-access.md)).
- **Inputs.** `<profile>`, `<allowed-account-id>`, `<project-id>`.
- **Procedure.**
  1. The OIDC provider:
     ```
     aws iam list-open-id-connect-providers --profile <profile> \
       --query "OpenIDConnectProviderList[?ends_with(Arn, ':oidc-provider/gitlab.com')] | length(@)" \
       --output text
     aws iam get-open-id-connect-provider --profile <profile> \
       --open-id-connect-provider-arn arn:aws:iam::<allowed-account-id>:oidc-provider/gitlab.com \
       --query '{url:Url,clientIds:ClientIDList,tags:Tags}' --output json
     ```
  2. The trust statement and its principal:
     ```
     aws iam get-role --role-name cloud-platform-reference-shared-ci-checkout --profile <profile> \
       --query 'Role.AssumeRolePolicyDocument.Statement[].{effect:Effect,action:Action,condition:Condition}' \
       --output json
     aws iam get-role --role-name cloud-platform-reference-shared-ci-checkout --profile <profile> \
       --query "Role.AssumeRolePolicyDocument.Statement[].Principal.Federated | [?ends_with(@, ':oidc-provider/gitlab.com')] | length(@)" \
       --output text
     ```
  3. Attached and inline policies, and tags:
     ```
     aws iam list-attached-role-policies --role-name cloud-platform-reference-shared-ci-checkout \
       --profile <profile> --query 'AttachedPolicies[].PolicyName' --output json
     aws iam list-role-policies --role-name cloud-platform-reference-shared-ci-checkout \
       --profile <profile> --query PolicyNames --output json
     aws iam list-role-tags --role-name cloud-platform-reference-shared-ci-checkout \
       --profile <profile> --query 'Tags[].[Key,Value]' --output text
     ```
- **Expected result.**
  1. `1`. Then `url` `gitlab.com` (IAM returns the provider URL without its scheme;
     `ci-identity.tf` declares `https://gitlab.com`), `clientIds` `["sts.amazonaws.com"]`, and the
     six tags with `Component` `identity`.
  2. Exactly one statement: `Allow`, `sts:AssumeRoleWithWebIdentity`, a `StringEquals` condition
     with `gitlab.com:aud` = `sts.amazonaws.com` and `gitlab.com:sub` =
     `project_id:<project-id>:ref_type:branch:ref:main`; the principal count is `1`.
  3. `[]`; `["cloud-platform-reference-shared-ci-checkout-ecr-push"]`; the six tags with
     `Component` `identity`.
- **Evidence to retain.** The output of each command, captured privately.
- **STOP conditions.** A second statement, a `StringLike` operator, a wildcard in any condition, a
  subject for another project or ref, an attached managed policy, or a second inline policy. Run
  no publish job until the difference is explained.
- **Known limitations.**
  - No trust read-back has ever been retained; the last recorded one is 2026-08-15.
  - Step 1's provider URL, client-ID and tag read has no recorded execution. Its expected values
    come from `ci-identity.tf` and the AWS CLI reference, not from a run.
- **Next gate.** The first run of this form with its output retained.

### Read back the CI push scope

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22) |
| Published form | not executed as written (derived from the `get-role-policy` read in the 2026-09-17 and 2026-09-22 read-backs; the `jq` projection and the profile are added) |
| Evidence basis | [CI push identity](../../terraform/foundation/README.md#ci-push-identity). Retained private evidence of the 2026-09-17 read-back (five repositories in scope, the Collector absent) and of the 2026-09-22 read-back, in which the live document matched the expected nine-repository document exactly. A 2026-09-02 read-back is recorded without retained output. |
| Authority | None (read-only) |
| Cost | None |

- **Purpose.** Confirm that the push role reaches exactly the declared `astroshop/` repositories
  and nothing else.
- **Preconditions.** A signed-in profile for the project account ([operator-access.md](operator-access.md)).
- **Inputs.** `<profile>`.
- **Procedure.**
  ```
  aws iam get-role-policy --profile <profile> \
    --role-name cloud-platform-reference-shared-ci-checkout \
    --policy-name cloud-platform-reference-shared-ci-checkout-ecr-push \
    --output json |
    jq '.PolicyDocument.Statement[] | {Effect, Action, Resource: ([.Resource] | flatten | map(sub("^arn:aws:ecr:us-east-1:[0-9]{12}:"; "")))}'
  ```
- **Expected result.** Exactly two statements:
  - `Allow` for `ecr:BatchCheckLayerAvailability`, `ecr:InitiateLayerUpload`,
    `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`, `ecr:PutImage` and `ecr:BatchGetImage`, on
    `repository/astroshop/<name>` for exactly the names in `local.workload_repositories`;
  - `Allow` for `ecr:GetAuthorizationToken` on `*`, the only unscoped call.
- **Evidence to retain.** The output, captured privately.
- **STOP conditions.** `repository/platform/opentelemetry-collector` in the list, a wildcard
  repository, a missing or extra repository, or an extra action or statement.
- **Known limitations.**
  - The read shows what IAM stores. Whether every listed action is required has been exercised
    only for the push paths that have run
    ([CI push identity](../../terraform/foundation/README.md#ci-push-identity)).
  - Immediately after an apply, IAM may briefly return the previous document. The executed
    2026-09-22 read-back allowed for that with at most four reads 10 seconds apart, tolerating only
    the previous document, and matched on its first read. This single-read form has no such
    allowance.

### Diagnose a failed publication

| Field | Value |
|---|---|
| Validation status | EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-15) |
| Published form | not executed as written (a symptom table built from the outcomes recorded 2026-08-15; it contains no command) |
| Evidence basis | Both cases were observed and corrected on 2026-08-15 and recorded as outcomes without raw output; a successful publication followed the corrections. The first case never reached AWS. |
| Authority | None to diagnose; an explicit owner grant for a correction that changes the trust or GitLab settings |
| Cost | None |

- **Purpose.** Map an observed publication failure to its measured cause. Only failures that have
  actually occurred are listed.
- **Procedure.** Match the failing publish job against the table.

  | Symptom | Observed cause | Correction |
  |---|---|---|
  | GitLab refuses to issue the job's ID token, and the job fails before any AWS call | The project's path had previously belonged to another GitLab project | Switch the sub-claim components to `project_id`, `ref_type`, `ref` and pin the trust to the project ID, as in steps 1 to 3 of [Connect a GitLab project](#connect-a-gitlab-project-to-the-ci-push-identity) |
  | The token exchange, the STS call and the registry login succeed, and then the push fails | `ECR_REGISTRY` held the registry host plus the repository path | Set `ECR_REGISTRY` to the registry host only; the repository path belongs in `ECR_REPOSITORY` |
- **Known limitations.** Failures that have not occurred, such as an audience or subject mismatch
  at the STS call, are not listed.

## Not yet exercised

| Item | Status | Where described |
|---|---|---|
| First build of the evidence store, the registry repositories and the CI identity on the current root. The historical creations ran on older root shapes (the evidence store on 2026-08-08; the checkout repository and the CI identity on 2026-08-15) and are EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE. On a build from nothing the full plan adds them together with the certificate; that combined plan has never run, and no plan shape for it is published. | UNEXERCISED | [Public DNS](../../terraform/foundation/README.md#public-dns) for the order; [public-dns-and-certificate.md](public-dns-and-certificate.md) |
| Adding a registry repository against the current root, with the hosted zone and certificate present and `public_domain` supplied | DESIGNED-NOT-EXECUTED | [Add a registry repository](#add-a-registry-repository-and-widen-the-ci-push-scope) |
| A trust change against the current root, with the hosted zone, the certificate and `public_domain` present | DESIGNED-NOT-EXECUTED | Step 3 of [Connect a GitLab project](#connect-a-gitlab-project-to-the-ci-push-identity) |
| A request over plain HTTP to confirm the evidence bucket denies it | UNEXERCISED | [Read back the evidence-store controls](#read-back-the-evidence-store-controls) |
| Registry retention review before an eleventh tagged image in `astroshop/checkout` | UNEXERCISED | [Artifact registry](../../terraform/foundation/README.md#artifact-registry) |
| Recovering a lost repository or image by rebuilding from source. A rebuilt image carries a new digest, because build reproducibility is not measured, so every pin to the old digest would need a reviewed change. | UNEXERCISED | [ADR-0009](../decisions/0009-define-the-software-delivery-model.md), [Artifact registry](../../terraform/foundation/README.md#artifact-registry) |
| Decommissioning a registry repository | UNEXERCISED | [Artifact registry](../../terraform/foundation/README.md#artifact-registry) |
| Revoking or rotating the CI push trust, including pointing an existing root at a different GitLab project, which replaces the only trusted subject and disconnects the previous project | UNEXERCISED | None |
| Final decommission of the evidence store | UNEXERCISED | [Final decommission](../../terraform/foundation/README.md#final-decommission) |

## Hidden prerequisites

- An AWS account dedicated to the platform, and an operator identity with a signed-in profile for
  it ([operator-access.md](operator-access.md)).
- The foundation root's four execution inputs ([Input](../../terraform/foundation/README.md#input)):
  a globally unique evidence bucket name, the account ID, the GitLab project's numeric ID and a
  registered apex domain; and the state bucket name from the bootstrap root for `backend.hcl`.
- A GitLab.com project that holds the workload source and its pipelines, with GitLab API access
  able to change its project settings and access to its CI/CD variables. The reference change used
  a temporary project access token, revoked after use; the token's role and scope were not
  recorded.
- The project's `ci_id_token_sub_claim_components` attribute, set to `project_id`, `ref_type`,
  `ref`.
- Two masked GitLab CI/CD variables: `AWS_ROLE_ARN`, the push role's ARN, and `ECR_REGISTRY`, the
  registry host.
- `jq` and `shasum` on the operator workstation, in addition to the toolchain in
  [operator-access.md](operator-access.md).
- `crane`, for mirroring a platform image into `platform/`; the reference mirror used it, and this
  suite publishes no mirroring procedure.
- A private, untracked location for saved plans, plan and apply logs and read-back output, because
  plan output carries the evidence bucket name and account identifiers.
- An approver who grants each AWS mutation in writing before it runs, and each refresh-only state
  write separately.
