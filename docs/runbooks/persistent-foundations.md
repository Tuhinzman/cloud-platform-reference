# Persistent Foundation Operations

This runbook covers the recurring operation and verification of three persistent foundations
declared in [`terraform/foundation`](../../terraform/foundation/README.md): the evidence store, the
artifact registry, and the CI push identity. The CI push identity is the GitLab OIDC provider, the
IAM role that main-branch pipelines assume to publish images (the push role), and that role's
inline push policy. What each foundation is, why it exists, its inputs, its protections, its
recovery path and its final decommission order are in that README and are not repeated here. The
decommission order is an order only: no command-level procedure exists, it has never run, and it
needs the owner's explicit approval ([Not yet exercised](#not-yet-exercised)). The
persistent-foundation register is in the
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

> **Warning: the platform image mirroring procedure is not published.** This suite publishes no
> procedure for mirroring a third-party platform image into the `platform/` namespace.
> `platform/opentelemetry-collector` must hold the pinned image by digest before any runtime uses
> it, the push role cannot reach that repository, and an engineer rebuilding the platform has no
> public procedure for populating it. How the reference mirror was made is under
> [Reproducibility gaps](#reproducibility-gaps).

## Normal path

**In a build of the platform**, once the foundation root is applied, follow these in order. The
suite's [task list](README.md#task-list) shows where they sit in the whole build.

1. [Read back the evidence-store controls](#read-back-the-evidence-store-controls): confirm that the
   evidence bucket still has its versioning, encryption, public access block, TLS-only policy and
   tags.
2. [Connect a GitLab project to the CI push identity](#connect-a-gitlab-project-to-the-ci-push-identity).
   It changes GitLab project settings, and the IAM trust in a trust change, so it needs an owner
   grant. Its step 4 runs
   [Read back the CI trust](#read-back-the-ci-trust) and then
   [Read back the CI push scope](#read-back-the-ci-push-scope).

**When a trigger occurs:**

- A service enters the delivery path:
  [Add a registry repository and widen the CI push scope](#add-a-registry-repository-and-widen-the-ci-push-scope).
  This changes AWS and needs an owner grant.
- A pin or a pipeline artifact names an image digest:
  [Verify an image in the registry by digest](#verify-an-image-in-the-registry-by-digest).

**When a publish job fails:** [Diagnose a failed publication](#diagnose-a-failed-publication).

**When a plan of this root is reviewed** (step 7 of the shared
[Normal path](terraform-operations.md#normal-path)): check every address in the reviewed list
against [Read-back coverage](#read-back-coverage).

## Before you start

- [ ] A dedicated AWS account for the platform, and an operator identity with a signed-in profile
      for it. Before the first AWS command, pass the identity check and the account check, which
      confirm that the profile resolves to the project account
      ([Sign in](operator-access.md#sign-in),
      [Verify the resolved identity](operator-access.md#verify-the-resolved-identity),
      [Check the account before AWS commands](operator-access.md#check-the-account-before-aws-commands)).
- [ ] `jq` and `shasum` on the operator workstation, in addition to the toolchain in
      [operator-access.md](operator-access.md#prepare-the-workstation-toolchain).
- [ ] The values behind the placeholders below.
- [ ] A private, untracked location for saved plans, plan and apply logs and read-back output,
      because plan output carries the evidence bucket name and account identifiers. Output kept
      there is the evidence each procedure asks you to retain
      ([evidence-handling.md](evidence-handling.md)). Capture and redaction follow
      evidence-handling.md, whose redaction filter is not published
      ([Reproducibility gaps](evidence-handling.md#reproducibility-gaps)).
- [ ] An approver who grants each AWS mutation in writing before it runs, and each refresh-only
      state write separately. A change to GitLab project settings needs the same written grant. An
      "owner grant" in this runbook is that written approval ([Approvals](README.md#approvals)).

| Placeholder | Value |
|---|---|
| `<profile>` | Your signed-in AWS CLI profile for the project account. For [Add a registry repository](#add-a-registry-repository-and-widen-the-ci-push-scope) and [Connect a GitLab project](#connect-a-gitlab-project-to-the-ci-push-identity), the AdministratorAccess profile, as [terraform-operations.md](terraform-operations.md#before-you-start) defines `<profile>`. For the read-only procedures, see **Permission set** below. |
| `<evidence-bucket>` | The root's `evidence_bucket_name` [input](../../terraform/foundation/README.md#input) |
| `<allowed-account-id>` | The root's `allowed_account_id` input |
| `<project-id>` | The GitLab project's numeric ID, which is the root's `gitlab_project_id` |
| `<service>` | A service name; its repository is `astroshop/<service>` |
| `<repository>` | A registry repository, for example `astroshop/checkout` |
| `<digest>` | An image digest, `sha256:<hex>` |
| `<tag>` | An image tag, as defined in [Verify an image in the registry by digest](#verify-an-image-in-the-registry-by-digest) |

Each command sets its output format, so the expected results do not depend on the profile's
default. Successful output is projected with `--query` or `jq` and contains no ARN and no account
ID.

> **Warning:** Error messages are not projected. ECR's not-found errors can name the registry ID,
> which is the account ID, so redact error output at capture
> ([Redact at capture](evidence-handling.md#redact-at-capture)).

**Permission set.** Inspection is meant for the ReadOnly permission set that
[operator-access.md](operator-access.md) prescribes. Every recorded operator read-only check in
this runbook ran on the administrator permission set. The 2026-09-17 manifest was read by the CI
publish job on the push role. None has run on the ReadOnly permission set.

**Labels.** Each procedure opens with its **Validation** label, defined in the
[runbook index](README.md#validation-labels), and its **Published command form**. *Executed as
written* means this exact command form, placeholders aside, appears as executed in retained private
evidence. *Not executed as written* means the commands on the page are derived from something else;
the procedure's Engineering notes say what.

### Read-back coverage

Before approval, step 7 of the shared [Normal path](terraform-operations.md#normal-path) checks
that every address in the reviewed list, the addresses and actions the change intends, has a
published read-back. This table is that check for the foundation root. The hosted zone and the
certificate are read back in [public-dns-and-certificate.md](public-dns-and-certificate.md).

| Address | Published read-back |
|---|---|
| `aws_s3_bucket.evidence` | [Read back the evidence-store controls](#read-back-the-evidence-store-controls), step 5 (the tags) |
| `aws_s3_bucket_versioning.evidence` | [Read back the evidence-store controls](#read-back-the-evidence-store-controls), step 1 |
| `aws_s3_bucket_server_side_encryption_configuration.evidence` | [Read back the evidence-store controls](#read-back-the-evidence-store-controls), step 2 |
| `aws_s3_bucket_public_access_block.evidence` | [Read back the evidence-store controls](#read-back-the-evidence-store-controls), step 3 |
| `aws_s3_bucket_policy.evidence` | [Read back the evidence-store controls](#read-back-the-evidence-store-controls), step 4 |
| `aws_ecr_repository.workload["<service>"]` and `aws_ecr_lifecycle_policy.workload["<service>"]`, created by the change | [Add a registry repository and widen the CI push scope](#add-a-registry-repository-and-widen-the-ci-push-scope), step 5 |
| The same two addresses for a repository that already exists, changed or destroyed | **None**: step 5 reads only a new repository |
| `aws_ecr_repository.collector` | **None** |
| `aws_iam_openid_connect_provider.gitlab` | [Read back the CI trust](#read-back-the-ci-trust), step 1 |
| `aws_iam_role.ci_checkout` | [Read back the CI trust](#read-back-the-ci-trust), steps 2 and 3 |
| `aws_iam_role_policy.ci_checkout_ecr_push` | [Read back the CI push scope](#read-back-the-ci-push-scope) |
| `aws_route53_zone.public` | [Read back the hosted zone](public-dns-and-certificate.md#read-back-the-hosted-zone), steps 1 to 4 |
| `aws_acm_certificate.public`, `aws_route53_record.certificate_validation` and `aws_acm_certificate_validation.public` | [Read back the certificate](public-dns-and-certificate.md#read-back-the-certificate), steps 1 to 3, and [Read back the hosted zone](public-dns-and-certificate.md#read-back-the-hosted-zone), steps 1 to 4 |

For the last two rows, PASS: one public zone for `<apex>` with four name servers, the six
mandatory tags with `Component` set to `dns`, and only `NS` and `SOA` records, plus, after the
certificate, exactly one `CNAME`, its validation record, with TTL 300; and a certificate `ISSUED`
and `AMAZON_ISSUED` for `<apex>` with SANs exactly `<apex>` and `*.<apex>`, both names `DNS` and
`SUCCESS` with one shared validation record, `Export` `DISABLED`, and the same six tags. Then
return to the step that sent you here.

Count an address as **None** also when:

- the table does not list it, such as a resource the change declares in the root for the first
  time;
- the change destroys it; or
- the change sets a value that its read-back's expected result states differently. Those
  expected results are the values the root declares today; none is published for another value.

No procedure on this page or in public-dns-and-certificate.md checks a foundation address another
way, so an address counted as **None** stops the plan at step 7, before approval. Work resumes
only on a reviewed decision under explicit approval.

## Procedures

### Read back the evidence-store controls

**Validation:** EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-08) · **Published command form:** not executed as written

**What this does.** Five reads confirm that the evidence bucket still carries the controls listed in
[What it creates](../../terraform/foundation/README.md#what-it-creates) and the six mandatory tags:
versioning, default encryption, the public access block, the bucket policy that denies requests
without TLS, and the tags. The evidence bucket is where evidence is exported so that it outlives the
environment it documents ([evidence-handling.md](evidence-handling.md)).

**Before you start.**

- [ ] A signed-in profile for the project account, confirmed by steps 1 and 2 of
      [Check the account before AWS commands](operator-access.md#check-the-account-before-aws-commands)
      (PASS: `ACCOUNT_MATCH=PASS`). Then return to this list.
- [ ] `<evidence-bucket>` and `<profile>`.

**Safety and authority.** Read-only. No approval is needed, and it costs nothing. Step 4 prints the
statement fields only, because the policy's resource field carries the bucket name.

**Steps.**

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

4. Bucket policy, statement fields only:

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

**Expected result.**

1. `Enabled`.
2. `AES256`.
3. `BlockPublicAcls`, `IgnorePublicAcls`, `BlockPublicPolicy` and `RestrictPublicBuckets` are all
   `true`.
4. Exactly one statement: `Sid` `DenyUnencryptedTransport`, `Effect` `Deny`, `Principal` `*`,
   `Action` `s3:*`, and the condition `Bool` `aws:SecureTransport` = `"false"`.
5. Exactly six tags: `Project` `cloud-platform-reference`, `Environment` `shared`, `Component`
   `evidence-store`, `Lifecycle` `persistent`, `Owner` `platform-engineer`, `ManagedBy` `terraform`.

**PASS when.**

- [ ] All five outputs equal the expected result.

A plan of the foundation root that reports no changes
([Confirm convergence](terraform-operations.md#confirm-convergence)) confirms the same five
resources from Terraform's side.

**STOP if.**

- Any value differs from the expected result.

**If it fails.** Treat the difference as drift
([Detect state drift](terraform-operations.md#detect-state-drift)) and resolve it before exporting
more evidence to the bucket.

**Evidence to keep.** The output of the five commands, captured privately
([evidence-handling.md](evidence-handling.md)).

**Next step.** In a build of the platform,
[Connect a GitLab project to the CI push identity](#connect-a-gitlab-project-to-the-ci-push-identity).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-08) |
| Published form | not executed as written (derived from the controls recorded as read back after the 2026-08-08 apply and from [`evidence-store.tf`](../../terraform/foundation/evidence-store.tf); no command was retained) |
| Evidence basis | [README Status](../../terraform/foundation/README.md#status). The full check was recorded as an outcome on 2026-08-08, and versioning alone on 2026-08-14 before the first evidence upload; the output of neither is retained. |
| Authority | None (read-only) |
| Cost | None |

**Known limitations.**

- The TLS-only rule has been verified only by reading the policy text. No request over plain HTTP
  has been sent to confirm that S3 refuses it.
- The last full read-back is the 2026-08-08 record. Later records that restate these values without
  a retained capture are not counted as read-backs.
- The controls say nothing about who may read or write evidence, because the access model is not
  implemented ([What the protections do](../../terraform/foundation/README.md#what-the-protections-do-and-what-they-do-not)),
  and no retention rule exists yet ([Evidence retention](../../terraform/foundation/README.md#evidence-retention-is-not-decided-yet)).

**Validation gate.** The first run of this form with its output retained.

### Add a registry repository and widen the CI push scope

**Validation:** DESIGNED-NOT-EXECUTED (never, against the current root) · **Published command form:** not executed as written

**What this does.** Gives a service that has entered the delivery path its own `astroshop/`
repository, and lets the CI push identity publish to it. Membership follows the delivery path, not
the fleet inventory ([Artifact registry](../../terraform/foundation/README.md#artifact-registry)).

You add one name to one Terraform set. The push policy's resource list derives from that set, so the
same change creates the repository and its lifecycle policy and widens the push role's scope to the
new repository. The procedure then reads everything back, confirms convergence, checks that
Terraform state has caught up with AWS, and seals the campaign's evidence set. It does not wire the
service's publish job: wiring it with `ECR_REPOSITORY: astroshop/<service>` comes after the
repository exists and belongs to the publication path, outside this runbook.

Three Terraform terms matter here. A **reviewed saved plan** is a plan written to a file, checked
against the exact list of changes in step 3, and then applied exactly as reviewed. The
**convergence plan** is an ordinary plan after the apply; it must report no changes. The
**refresh-only drift check** compares Terraform state with AWS and changes nothing; applying a
refresh-only plan writes state. Step 9 exists because an ordinary plan can exit 0 while Terraform's
stored copy of the push policy is stale (see the Engineering notes).

**Before you start.**

- [ ] The service has a build-and-scan pipeline in the workload repository
      ([Artifact registry](../../terraform/foundation/README.md#artifact-registry)).
- [ ] An approver for the written owner grant this change needs. The grant is the owner's written
      approval of the reviewed saved plan, identified by its sha256, after the review in step 3 and
      before the apply in step 4: step 9 of the shared
      [Normal path](terraform-operations.md#normal-path) and the [Approvals](README.md#approvals)
      list. A refresh-only apply in this procedure's step 9 needs its own approval.
- [ ] Step 1 of the shared [Normal path](terraform-operations.md#normal-path) done: the root's
      filled `backend.hcl` and `terraform.tfvars`, with all four inputs including `public_domain`
      ([Input](../../terraform/foundation/README.md#input)), in its private `<inputs-dir>`, and a
      new `<private-dir>` for the saved plan and the logs
      ([placeholders](terraform-operations.md#before-you-start)). Step 3 initializes the root
      against its backend, after the change is committed.
- [ ] The expected address set for state inspection in step 3: the address list that step 2 of
      [Apply the reviewed saved plan](terraform-operations.md#apply-the-reviewed-saved-plan) printed
      after this root's last apply, kept in that campaign's evidence. None is published; without
      it this procedure stops at state inspection ([root table](terraform-operations.md#normal-path)).
- [ ] The campaign's evidence set opened for this change, as the shared Normal path requires before
      its step 1 ([Capture a campaign evidence set](evidence-handling.md#capture-a-campaign-evidence-set)).
      A *campaign* is one bounded operation whose evidence is kept together, here the apply with its
      read-back.
- [ ] `<service>` and `<profile>`.

**Safety and authority.** Mutating, owner-authorized, and billable once the repository holds an
image. The apply changes ECR and IAM and needs an explicit owner grant: the owner approves the
reviewed saved plan in writing, identified by its sha256, after the review and before the apply
([Approvals](README.md#approvals)). A refresh-only apply in step 9 needs its own explicit approval
of that refresh-only plan, because applying it writes state. The new repository costs nothing while
it holds no image; ECR then bills stored image data ([cost-and-residue.md](cost-and-residue.md)).
So the apply bills no rate, and the budget read-back and price re-check that step 10 of the shared
[Normal path](terraform-operations.md#normal-path) requires before a billable change do not apply
to it. Storage billing starts with the first image, published outside this runbook; registry
storage has no rate in the price table, and its re-check is not yet exercised
([Not yet exercised](cost-and-residue.md#not-yet-exercised)).

> **Warning:** This procedure has never run against the current root. The hosted-zone, certificate
> and `public_domain` criteria in step 3, and the order of steps 8 and 9, were never part of an
> executed run.

**Steps.**

1. Record the registry inventory, one line per repository with its image count:

   ```
   for repository in $(aws ecr describe-repositories --profile <profile> \
       --query 'repositories[].repositoryName' --output text); do
     printf '%s %s\n' "${repository}" "$(aws ecr describe-images --repository-name "${repository}" \
       --profile <profile> --query 'length(imageDetails)' --output text)"
   done
   ```

2. Add `"<service>"` to `local.workload_repositories` in
   [`artifact-registry.tf`](../../terraform/foundation/artifact-registry.tf) and change nothing else.
   The push policy's resource list derives from that set. Commit the change. That commit is the
   reviewed commit, `<commit>`, that the static checks, the initialization and the bind check in
   steps 3 and 4 all work from ([terraform-operations.md](terraform-operations.md#before-you-start)).

3. Create a reviewed saved plan from `<commit>` through the shared workflow, steps 2 to 7 of its
   [Normal path](terraform-operations.md#normal-path):
   [Run the static checks](terraform-operations.md#run-the-static-checks),
   [Initialize a root against the state backend](terraform-operations.md#initialize-a-root-against-the-state-backend)
   in a clean working tree at `<commit>`,
   [Inspect state without writing it](terraform-operations.md#inspect-state-without-writing-it),
   [Keep Terraform debug logging off](terraform-operations.md#keep-terraform-debug-logging-off),
   [Plan to a saved file](terraform-operations.md#plan-to-a-saved-file) and
   [Review the saved plan](terraform-operations.md#review-the-saved-plan). Accept the plan only if
   it holds exactly:
   - a create of `aws_ecr_repository.workload["<service>"]` and of
     `aws_ecr_lifecycle_policy.workload["<service>"]` for each added name;
   - one in-place update of `aws_iam_role_policy.ci_checkout_ecr_push`;
   - nothing else: no destroy, no replace, no output change, and no change to
     `aws_iam_role.ci_checkout`, `aws_iam_openid_connect_provider.gitlab`,
     `aws_ecr_repository.collector`, any evidence-store resource, `aws_route53_zone.public`,
     `aws_acm_certificate.public`, `aws_route53_record.certificate_validation` or
     `aws_acm_certificate_validation.public`.

   The planned policy document shows as known after apply, because the new repository's ARN does not
   exist yet (observed 2026-09-17), so step 6 confirms the scope.

   > **Warning:** If the plan reports that `aws_iam_role.ci_checkout` changed outside Terraform,
   > stop. That is drift left by an earlier change, not part of this one. Explain it and reconcile it
   > through [terraform-operations.md](terraform-operations.md#reconcile-explained-state-only-drift)
   > under its own approval, then plan this change again.

4. Apply exactly that saved plan, steps 8 to 10 of the shared
   [Normal path](terraform-operations.md#normal-path):
   [Bind the saved plan to its hash and to state](terraform-operations.md#bind-the-saved-plan-to-its-hash-and-to-state),
   the owner's approval, and
   [Apply the reviewed saved plan](terraform-operations.md#apply-the-reviewed-saved-plan). The
   shared step 10's budget read-back and price re-check do not apply, because this apply bills no
   rate (see **Safety and authority**).

   > **Warning:** This step changes ECR and IAM. Run it only after the owner has approved this
   > reviewed saved plan in writing, identified by its sha256, and the bind check has passed again
   > immediately before the apply ([Approvals](README.md#approvals)).

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

   > **Warning:** This read runs immediately after the apply, when IAM may briefly return the
   > previous document: the push scope without the repositories this change adds. Use step 2 of
   > [Read back the CI push scope](#read-back-the-ci-push-scope): at most four reads 10 seconds
   > apart, tolerating only that previous document. The STOP conditions of this procedure and of
   > that read both apply, so a push scope still without the new repository on the fourth read, or
   > any other difference on any read, is a STOP.

7. Repeat step 1 and compare it with the first run.

8. Run the convergence plan
   ([Confirm convergence](terraform-operations.md#confirm-convergence)).

9. Run the refresh-only drift check
   ([Detect state drift](terraform-operations.md#detect-state-drift)). If it reports no drift,
   continue at step 10. If its only drift is `aws_iam_role.ci_checkout` attribute `inline_policy`,
   and the live policy read in step 6 equals the configured one, it is the known state lag: reconcile
   it through
   [Reconcile explained state-only drift](terraform-operations.md#reconcile-explained-state-only-drift),
   which binds the refresh-only plan and needs its own explicit owner approval before that plan is
   applied, then continue at step 10.

   > **Warning:** Applying the refresh-only plan writes state. The grant for step 4 does not cover
   > it.

10. Close the evidence set: step 13 of the shared
    [Normal path](terraform-operations.md#normal-path). Sweep the set with its planted positive
    control, handle any hit, and seal it: steps 4 to 7 of the
    [Normal path](evidence-handling.md#normal-path) of evidence-handling.md. The procedure ends
    here.

**Expected result.**

- Step 5: `IMMUTABLE`, `AES256`, `scanOnPush` `false`; a lifecycle policy with one rule that
  expires `tagged` images matching `*` once `imageCountMoreThan` 10; and exactly the six tags
  listed for the evidence store, except `Component` `artifact-registry`.
- Step 6: the new repository is in scope and nothing else changed, within at most four reads.
- Step 7: every repository that existed before keeps its image count, and each new one holds 0.
- Step 8: exit 0 and no changes.
- Step 9: no drift, or only the role's `inline_policy` lag; after any reconciliation the drift check
  exits 0.
- Step 10: the set swept with its planted positive control, and sealed.

**PASS when.**

- [ ] The plan held exactly the step 3 list and was applied as reviewed.
- [ ] Steps 5 to 8 match their expected results.
- [ ] The drift check reports no drift, or, after reconciling only the `inline_policy` lag under its
      own approval, exits 0.
- [ ] The campaign's evidence set is sealed (step 10).

**STOP if.**

- The plan holds any address, action or count outside step 3, or reports that
  `aws_iam_role.ci_checkout` changed outside Terraform.
- An existing repository's image count changes.
- The push scope lists `platform/opentelemetry-collector`, a wildcard repository, or any action
  beyond those in [Read back the CI push scope](#read-back-the-ci-push-scope).
- The convergence plan in step 8 exits 1 or 2.
- The drift check in step 9 reports anything other than the role's `inline_policy`, or the live
  policy differs from the configured one.

**If it fails.** Any result that misses PASS comes here.

- An apply that stops partway follows
  [Stop after a failed or interrupted apply](terraform-operations.md#stop-after-a-failed-or-interrupted-apply).
- No procedure in this suite handles a step 5 read-back that differs from its expected result.
- A sweep hit, a planted control the sweep misses, or a manifest entry that fails in step 10:
  [Handle sweep hits before sealing](evidence-handling.md#handle-sweep-hits-before-sealing),
  [Plant a positive control for the sweep](evidence-handling.md#plant-a-positive-control-for-the-sweep)
  or [Seal the set and verify the manifest](evidence-handling.md#seal-the-set-and-verify-the-manifest).
- Recovery or rollback of this change is not exercised; see [Not yet exercised](#not-yet-exercised).

**Evidence to keep.** The saved plan and the plan and apply logs stay in `<private-dir>`; the
campaign's evidence set holds their sha256 digests, the exit codes and the apply's summary line as
verdicts, and the redacted read-back output
([What goes into the evidence set](terraform-operations.md#normal-path)). Plan and apply output
prints the evidence bucket name and account identifiers (observed), so none of it is published
([evidence-handling.md](evidence-handling.md)).

**Next step.** Wiring the service's publish job and its first publication, both outside this
runbook ([GitOps Delivery](../implementation/gitops-delivery.md#1-build-once-gitlab-ci-to-an-immutable-digest)).
Publication is billable, because ECR bills stored image data from the first image, and it needs
its own explicit owner authorization. The cost gate runs first: read the budget back
([Read back the budget and its alert states](cost-and-residue.md#read-back-the-budget-and-its-alert-states))
and [re-check the prices](cost-and-residue.md#re-check-prices-before-billable-work). The price
table has no registry-storage rate, so that re-check stops and gives no complete storage
estimate; the owner approves a re-estimate before the publication. Once a repository holds more
than 10 tagged images, its lifecycle policy can expire the oldest.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | DESIGNED-NOT-EXECUTED (never, against the current root) |
| Published form | not executed as written (derived from the applies executed 2026-09-02, 2026-09-17 and 2026-09-22; the 2026-09-22 apply and read-back ran through a private reviewed tool on exported credentials; the hosted-zone, certificate and `public_domain` criteria below, and the order of steps 8 and 9, were never part of an executed run) |
| Evidence basis | [Artifact registry](../../terraform/foundation/README.md#artifact-registry), [CI push identity](../../terraform/foundation/README.md#ci-push-identity) and [Status](../../terraform/foundation/README.md#status). The 2026-09-17 and 2026-09-22 applies and read-backs are retained as private evidence. The 2026-09-02 apply and read-back are recorded as outcomes only; its reviewed plan is retained. All three predate the hosted zone (2026-09-23) and the certificate, and ran before `public_domain` was a declared input. |
| Authority | Explicit owner grant for the ECR and IAM mutation. A refresh-only apply in step 9 needs its own explicit approval of that refresh-only plan, because applying it writes state. |
| Cost | None while the new repository holds no image; ECR then bills stored image data ([cost-and-residue.md](cost-and-residue.md)) |

**Known limitations.**

- After the 2026-09-17 apply an ordinary plan exited 0 while Terraform's copy of the push policy
  under `aws_iam_role.ci_checkout` was already stale. The lag surfaced only in the next plan, on
  2026-09-21, and step 9 exists for that reason. The same lag after the 2026-09-22 apply was
  reconciled that day by a separately approved refresh-only apply that changed no AWS resource.
- The owner accepted the 2026-09-21 lag note for that one saved plan only; it is not a standing
  exception for later plans.

### Verify an image in the registry by digest

**Validation:** AWS-VALIDATED (2026-09-10) · **Published command form:** not executed as written

**What this does.** Confirms that the registry holds an image under the digest a pin or a pipeline
artifact names, and that the manifest it returns hashes to that digest. A digest is the SHA-256 of
the image's manifest, so the manifest bytes must hash to the `<hex>` part of `<digest>`.

The check proves which bytes the registry holds. It says nothing about the image's scan result or
provenance.

**Before you start.**

- [ ] A signed-in profile for the project account
      ([operator-access.md](operator-access.md#check-the-account-before-aws-commands)).
- [ ] `<repository>`, for example `astroshop/checkout`.
- [ ] `<digest>` as `sha256:<hex>`, taken from the publish job's `digest.txt` artifact or from the
      digest pin in your own GitOps images file
      ([GitOps Delivery](../implementation/gitops-delivery.md#3-pinning-by-digest)).
- [ ] `<tag>`: for an image CI published, the publishing commit's short SHA
      (`CI_COMMIT_SHORT_SHA` in the publish template); for a mirrored image, the upstream version
      tag. Mirroring itself has no published procedure (see the warning at the top of this page).

**Safety and authority.** Read-only. No approval is needed, and it costs nothing. Redact any error
text before you keep it: ECR's not-found errors can name the registry ID, which is the account ID.

**Steps.**

1. Find the image by digest:

   ```
   aws ecr describe-images --repository-name <repository> --image-ids imageDigest=<digest> \
     --profile <profile> \
     --query 'imageDetails[].{digest:imageDigest,tags:imageTags,pushedAt:imagePushedAt,mediaType:imageManifestMediaType}' \
     --output json
   ```

2. Hash the exact manifest bytes. Command substitution drops the newline the CLI appends to text
   output, and `printf '%s'` writes the rest unchanged:

   ```
   manifest=$(aws ecr batch-get-image --repository-name <repository> \
     --image-ids imageDigest=<digest> --profile <profile> \
     --query 'images[0].imageManifest' --output text)
   printf '%s' "${manifest}" | shasum -a 256
   ```

**Expected result.** Step 1 returns one image whose digest equals `<digest>` and whose tags include
`<tag>`. Step 2 prints `<hex>  -`, where `<hex>` is the part of `<digest>` after `sha256:`.

**PASS when.**

- [ ] Step 1 returns one image with digest `<digest>` and `<tag>` among its tags.
- [ ] Step 2 prints the `<hex>` of `<digest>`.

**STOP if.**

- `ImageNotFoundException`.
- A hash that differs from `<digest>`. Do not rely on the digest until the difference is explained.
  A missing image returns no manifest, so its hash cannot match.

**If it fails.** No procedure in this suite explains a missing image or a hash mismatch; do not rely
on the digest until the difference is explained. Two known limits of this form can only produce a
false failure, never a false pass: a manifest that ends in a newline, and a manifest type other than
the Docker schema-2 manifests it was exercised on. Both are described in the Engineering notes.

**Evidence to keep.** Both outputs, captured privately, with any error text redacted
([Redact at capture](evidence-handling.md#redact-at-capture)).

**Next step.** Return to the task that named the digest, such as the digest pin in your GitOps
images file ([GitOps Delivery](../implementation/gitops-delivery.md#3-pinning-by-digest)).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-10) |
| Published form | not executed as written (the `describe-images` and `batch-get-image` reads are the forms executed 2026-09-10, with a `--query` projection, an output format and a profile added; like that run, `batch-get-image` omits the `--accepted-media-types` that the public [`ecr-publish.yml`](https://gitlab.com/tuinzaman/cloud-platform-workload/-/blob/main/ci/templates/ecr-publish.yml) passes; only the hash step's byte handling, `printf '%s'` of the command-substituted manifest, follows that template) |
| Evidence basis | Retained private evidence of the 2026-09-10 read-only registry check, in which four pinned digests were found by digest and one manifest's SHA-256 was compared with its digest. The same comparison is retained for the mirrored Collector image on 2026-09-07, and for an image published by CI on 2026-09-17 whose manifest bytes the publish job itself fetched on the push role. |
| Authority | None (read-only) |
| Cost | None |

**Known limitations.**

- A manifest that ends in a newline would lose it in step 2 and fail the comparison. That gives a
  false failure, never a false pass, and has not been observed.
- Exercised only on Docker schema-2 manifests (`application/vnd.docker.distribution.manifest.v2+json`).
  The read omits the `--accepted-media-types` the publish template passes, and its behaviour for OCI
  manifests or image indexes has not been measured. A different manifest returned there would fail
  the comparison, not pass it.
- The check proves which bytes the registry holds. It says nothing about the image's scan result or
  provenance.

### Read back the CI trust

**Validation:** EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-15) in part; DESIGNED-NOT-EXECUTED (never) for step 1's detail read and step 2's principal count · **Published command form:** not executed as written

**What this does.** Confirms that only main-branch jobs of the one pinned GitLab project, presenting
the pinned audience, can assume the push role. The trust is the role's trust policy: it decides
which GitLab ID tokens may be exchanged for credentials on the role. Three reads cover the GitLab
OIDC provider, the role's trust statement and its principal, and the role's policies and tags.

**Before you start.**

- [ ] A signed-in profile for the project account
      ([operator-access.md](operator-access.md#check-the-account-before-aws-commands)).
- [ ] `<profile>`, `<allowed-account-id>` and `<project-id>`.

**Safety and authority.** Read-only. No approval is needed, and it costs nothing.

**Steps.**

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

**Expected result.**

1. `1`. Then `url` `gitlab.com` (IAM returns the provider URL without its scheme; `ci-identity.tf`
   declares `https://gitlab.com`), `clientIds` `["sts.amazonaws.com"]`, and the six tags with
   `Component` `identity`. This provider URL, client-ID and tag read has no recorded execution; its
   expected values come from `ci-identity.tf` and the AWS CLI reference, not from a run.
2. Exactly one statement: `Allow`, `sts:AssumeRoleWithWebIdentity`, a `StringEquals` condition with
   `gitlab.com:aud` = `sts.amazonaws.com` and `gitlab.com:sub` =
   `project_id:<project-id>:ref_type:branch:ref:main`; the principal count is `1`. The principal
   count has no recorded execution; its expected value comes from `ci-identity.tf`.
3. `[]`; `["cloud-platform-reference-shared-ci-checkout-ecr-push"]`; the six tags with `Component`
   `identity`.

**PASS when.**

- [ ] Every read matches its expected result.

**STOP if.**

- A second statement, a `StringLike` operator, a wildcard in any condition, a subject for another
  project or ref, an attached managed policy, or a second inline policy. Run no publish job until
  the difference is explained.
- Any other read that differs from its expected result. Run no publish job until the difference
  is explained.

**If it fails.** Any read that misses PASS comes here. No procedure in this suite corrects a trust
that differs. Run no publish job until the difference is explained. Revoking or rotating the trust
is not exercised; see [Not yet exercised](#not-yet-exercised).

**Evidence to keep.** The output of each command, captured privately.

**Next step.** [Read back the CI push scope](#read-back-the-ci-push-scope).

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-15) for step 1's provider count, step 2's trust-statement read and step 3; DESIGNED-NOT-EXECUTED (never) for step 1's provider URL, client-ID and tag read and for step 2's federated-principal count |
| Published form | not executed as written (derived from the check list in [Status](../../terraform/foundation/README.md#status); step 1's provider URL, client-ID and tag read and step 2's principal count are derived from [`ci-identity.tf`](../../terraform/foundation/ci-identity.tf) and have no recorded execution; no command was retained) |
| Evidence basis | [Status](../../terraform/foundation/README.md#status). The check list (trust statement, audience, subject, absence of managed policies, single inline policy, six tags) was recorded when the identity was created, against the earlier project-path subject. The 2026-08-15 change to the project ID is recorded as an outcome: the new subject, the unchanged audience and `StringEquals` operator, and no wildcard. Which of the other items were read again after that change is not recorded. No later retained capture verifies the trust: the 2026-09-10 reads listed the provider and the role's name and creation date, and later Terraform refreshes of the role are not trust read-backs. |
| Authority | None (read-only) |
| Cost | None |

**Known limitations.**

- No trust read-back has ever been retained; the last recorded one is 2026-08-15.
- Step 1's provider URL, client-ID and tag read has no recorded execution. Its expected values come
  from `ci-identity.tf` and the AWS CLI reference, not from a run.
- Step 2's federated-principal count has no recorded execution. Its expected value comes from
  `ci-identity.tf`, not from a run.

**Validation gate.** The first run of this form with its output retained.

### Read back the CI push scope

**Validation:** AWS-VALIDATED (2026-09-22) · **Published command form:** not executed as written

**What this does.** Confirms that the push role reaches exactly the declared `astroshop/`
repositories and nothing else. The push scope is the role's inline push policy. The `jq` filter
removes the Region and account prefix from each resource ARN, so the output carries no account ID.

**Before you start.**

- [ ] A signed-in profile for the project account
      ([operator-access.md](operator-access.md#check-the-account-before-aws-commands)).
- [ ] `<profile>`, and `jq` on the workstation.

**Safety and authority.** Read-only. No approval is needed, and it costs nothing.

**Steps.**

1. Read the push policy:

   ```
   aws iam get-role-policy --profile <profile> \
     --role-name cloud-platform-reference-shared-ci-checkout \
     --policy-name cloud-platform-reference-shared-ci-checkout-ecr-push \
     --output json |
     jq '.PolicyDocument.Statement[] | {Effect, Action, Resource: ([.Resource] | flatten | map(sub("^arn:aws:ecr:us-east-1:[0-9]{12}:"; "")))}'
   ```

2. Only when this read runs immediately after an apply that changed the push policy, as in step 6 of
   [Add a registry repository and widen the CI push scope](#add-a-registry-repository-and-widen-the-ci-push-scope):
   IAM may briefly return the previous document, the push scope as it stood before that apply. If
   step 1 shows exactly that previous document, wait 10 seconds and run step 1 again, for at most
   four reads in total.

   > **Warning:** Only the previous document may be read again. Any other difference from the
   > expected result, on any read, is a STOP at once, and so is the previous document on the fourth
   > read. At any other time a single read decides.

**Expected result.** Exactly two statements:

- `Allow` for `ecr:BatchCheckLayerAvailability`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`,
  `ecr:CompleteLayerUpload`, `ecr:PutImage` and `ecr:BatchGetImage`, on `repository/astroshop/<name>`
  for exactly the names in `local.workload_repositories`;
- `Allow` for `ecr:GetAuthorizationToken` on `*`, the only unscoped call.

**PASS when.**

- [ ] Exactly those two statements, and the repository list equals `local.workload_repositories`,
      on the first read, or after an apply that changed the push policy, within the four reads of
      step 2.

**STOP if.**

- `repository/platform/opentelemetry-collector` in the list, a wildcard repository, a missing or
  extra repository, or an extra action or statement. The only exception is the previous document
  during the repeat reads of step 2.
- After an apply that changed the push policy, the fourth read still shows the previous document.

**If it fails.** No procedure in this suite corrects a push scope that differs. When this read runs
as step 6 of
[Add a registry repository and widen the CI push scope](#add-a-registry-repository-and-widen-the-ci-push-scope),
that procedure's STOP conditions apply as well.

**Evidence to keep.** The output, captured privately.

**Next step.** When this read runs as step 6 of
[Add a registry repository and widen the CI push scope](#add-a-registry-repository-and-widen-the-ci-push-scope),
continue with its step 7. When it runs as step 4 of
[Connect a GitLab project to the CI push identity](#connect-a-gitlab-project-to-the-ci-push-identity),
continue with its step 5.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | AWS-VALIDATED (2026-09-22) |
| Published form | not executed as written (derived from the `get-role-policy` read in the 2026-09-17 and 2026-09-22 read-backs; the `jq` projection and the profile are added) |
| Evidence basis | [CI push identity](../../terraform/foundation/README.md#ci-push-identity). Retained private evidence of the 2026-09-17 read-back (five repositories in scope, the Collector absent) and of the 2026-09-22 read-back, in which the live document matched the expected nine-repository document exactly. A 2026-09-02 read-back is recorded without retained output. |
| Authority | None (read-only) |
| Cost | None |

**Known limitations.**

- The read shows what IAM stores. Whether every listed action is required has been exercised only
  for the push paths that have run
  ([CI push identity](../../terraform/foundation/README.md#ci-push-identity)).
- Immediately after an apply, IAM may briefly return the previous document. The executed 2026-09-22
  read-back allowed for that with at most four reads 10 seconds apart, tolerating only the previous
  document, and matched on its first read. Step 2 publishes the same bounds as a manual repeat of
  step 1, which is not the executed form. That read-back needed no repeat, so it did not exercise
  the repeat.

### Connect a GitLab project to the CI push identity

**Validation:** EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-15) for the recorded connection by a trust change on the root of that date; DESIGNED-NOT-EXECUTED (never) for a trust change against the current root and for the first-build branch; UNEXERCISED (never) for the first build that branch presumes · **Published command form:** not executed as written

**What this does.** Lets main-branch pipelines of exactly one GitLab project exchange their ID token
for short-lived credentials on the push role
([ADR-0009](../decisions/0009-define-the-software-delivery-model.md)). It has a GitLab side, a
project setting that shapes the token's subject and two CI/CD variables, and an AWS side, the trust
that pins the project ID through the foundation root's `gitlab_project_id` input.

Use it to connect the project, or for a trust change on an existing root such as the recorded
change from project path to project ID, which re-pinned the same project.

**Before you start.**

- [ ] The foundation root is applied. A first build follows the order the
      [README](../../terraform/foundation/README.md#public-dns) gives, but no plan shape for that
      build is published ([Not yet exercised](#not-yet-exercised)).
- [ ] GitLab API access that can change the project's settings, and access to its CI/CD variables
      ([Background prerequisites](#background-prerequisites)).
- [ ] A written owner grant.
- [ ] `<project-id>`, read from the project's Settings, General page, and `<allowed-account-id>`.
- [ ] For a trust change on an existing root (step 3): the expected address set for state
      inspection, the address list that step 2 of
      [Apply the reviewed saved plan](terraform-operations.md#apply-the-reviewed-saved-plan) printed
      after this root's last apply. None is published; without it step 3 stops at state inspection
      ([root table](terraform-operations.md#normal-path)).

**Safety and authority.** Mutating and owner-authorized: an explicit owner grant covers the IAM
trust change and the GitLab project settings. The apply in step 3 also needs the owner's written
approval of the reviewed saved plan, identified by its sha256, after the review and before the
apply ([Approvals](README.md#approvals)). The OIDC provider, role and inline policy carry no
direct charge.

> **Warning:** No trust change has run against the current root, with the hosted zone, the
> certificate and `public_domain` present. No acceptance shape exists for a first build.

**Steps.**

1. In GitLab, set the project attribute `ci_id_token_sub_claim_components` to `project_id`,
   `ref_type`, `ref`, and read it back. The read-back must be `["project_id", "ref_type", "ref"]`.
   GitLab's default subject names the project path, while the trust pins the project ID, so without
   this setting no job can assume the role.

   This step has no published command: the call that made the change was not recorded (see the
   Engineering notes).

2. Set `gitlab_project_id = <project-id>` in the root's untracked `terraform.tfvars`. Which case
   applies decides whether step 3 runs:

   - **The root was first built with this project's ID.** `gitlab_project_id` is one of the root's
     four required [inputs](../../terraform/foundation/README.md#input), and the trust pins the
     project ID through it, so that build already pinned the trust to this project. Skip step 3
     and continue at step 4, which reads the pinned subject back. No acceptance shape exists for a
     first build ([Not yet exercised](#not-yet-exercised)).
   - **A trust change on an existing root**, such as the recorded change from project path to
     project ID: continue at step 3.

   > **Warning:** The trust pins exactly one subject. Setting a different `gitlab_project_id` on an
   > existing root replaces the trusted project and disconnects the previous one. That has never
   > been executed, and no procedure covers it: it is outside this procedure. See the row
   > "Revoking or rotating the CI push trust" in [Not yet exercised](#not-yet-exercised).

3. Only for a trust change on an existing root: plan and apply the foundation root through the
   shared workflow in [terraform-operations.md](terraform-operations.md#normal-path):
   [Run the static checks](terraform-operations.md#run-the-static-checks),
   [Initialize a root against the state backend](terraform-operations.md#initialize-a-root-against-the-state-backend),
   [Inspect state without writing it](terraform-operations.md#inspect-state-without-writing-it),
   [Keep Terraform debug logging off](terraform-operations.md#keep-terraform-debug-logging-off),
   [Plan to a saved file](terraform-operations.md#plan-to-a-saved-file),
   [Review the saved plan](terraform-operations.md#review-the-saved-plan),
   [Bind the saved plan to its hash and to state](terraform-operations.md#bind-the-saved-plan-to-its-hash-and-to-state),
   [Apply the reviewed saved plan](terraform-operations.md#apply-the-reviewed-saved-plan) and
   [Confirm convergence](terraform-operations.md#confirm-convergence). Accept only one in-place
   update of `aws_iam_role.ci_checkout` (0 added, 1 changed, 0 destroyed), followed by a plan with
   no changes. That shape was recorded for a change that re-pinned the same project (see Step
   history in the Engineering notes). It is not an acceptance shape for pointing the root at a
   different project, which the warning at step 2 places outside this procedure.

   > **Warning:** The apply changes the IAM trust. Run it only after the owner has approved this
   > reviewed saved plan in writing, identified by its sha256, and the bind check has passed again
   > immediately before the apply ([Approvals](README.md#approvals)).

4. Run [Read back the CI trust](#read-back-the-ci-trust) and
   [Read back the CI push scope](#read-back-the-ci-push-scope).

5. In the GitLab project, create two masked CI/CD variables:
   - `AWS_ROLE_ARN`: `arn:aws:iam::<allowed-account-id>:role/cloud-platform-reference-shared-ci-checkout`
   - `ECR_REGISTRY`: `<allowed-account-id>.dkr.ecr.us-east-1.amazonaws.com`, the registry host only
     and never a repository path

   Each service whose publish job is wired sets `ECR_REPOSITORY` in its `ci.yml` to its own
   `astroshop/<service>`.

6. Keep `environment:` off every publish job.

   > **Warning:** `environment:` changes the ID token's subject, which the trust matches exactly, as
   > the comments in `ci-identity.tf` and `ecr-publish.yml` state. This has not been observed in a
   > run.

**Expected result.** The step 1 read-back is `["project_id", "ref_type", "ref"]`. For a trust
change, the step 3 plan is 0 added, 1 changed, 0 destroyed, and the plan after it has no changes.
Both read-backs in step 4 match their expected results. The first manual publish job on `main` then
proves the chain; running it is outside this runbook
([GitOps Delivery](../implementation/gitops-delivery.md#1-build-once-gitlab-ci-to-an-immutable-digest)).

**PASS when.**

- [ ] The sub-claim read-back is `["project_id", "ref_type", "ref"]`.
- [ ] For a trust change, the plan held only the one in-place update of the role, and the next plan
      had no changes.
- [ ] [Read back the CI trust](#read-back-the-ci-trust) and
      [Read back the CI push scope](#read-back-the-ci-push-scope) both pass.
- [ ] Both masked variables exist, and no publish job declares `environment:`.

**STOP if.**

- For a trust change, the plan touches anything other than the role's trust.
- The trust read-back fails its expected result.

**If it fails.**

- An apply that stops partway follows
  [Stop after a failed or interrupted apply](terraform-operations.md#stop-after-a-failed-or-interrupted-apply).
- A publish job that fails after the connection: [Diagnose a failed publication](#diagnose-a-failed-publication).
- Revoking or rotating the trust is not exercised; see [Not yet exercised](#not-yet-exercised).

**Evidence to keep.** The outputs that the two read-backs in step 4 ask you to keep, captured
privately. The saved plan and the plan and apply logs from step 3 stay private
([terraform-operations.md](terraform-operations.md)).

**Next step.** The first publication from the connected project, outside this runbook
([GitOps Delivery](../implementation/gitops-delivery.md#1-build-once-gitlab-ci-to-an-immutable-digest)).
Publication is billable, because ECR bills stored image data from the first image, and it needs
its own explicit owner authorization. The cost gate runs first: read the budget back
([Read back the budget and its alert states](cost-and-residue.md#read-back-the-budget-and-its-alert-states))
and [re-check the prices](cost-and-residue.md#re-check-prices-before-billable-work). The price
table has no registry-storage rate, so that re-check stops and gives no complete storage
estimate; the owner approves a re-estimate before the publication. Once a repository holds more
than 10 tagged images, its lifecycle policy can expire the oldest.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-15) for the recorded connection of the reference project by a trust change on the root as it was on that date, which re-pinned the same project: steps 1, 2, 3, 5 and 6; DESIGNED-NOT-EXECUTED (never) for a step 3 trust change against the current root, with the hosted zone, the certificate and `public_domain` present, and for the first-build branch of step 2, which skips step 3; UNEXERCISED (never) for the first build of the root on the current configuration that this branch presumes, for which no plan shape is published. Step 4 runs [Read back the CI trust](#read-back-the-ci-trust) and [Read back the CI push scope](#read-back-the-ci-push-scope), which keep their own labels; no push-scope read-back is recorded for 2026-08-15 |
| Published form | not executed as written (derived from [`ci-identity.tf`](../../terraform/foundation/ci-identity.tf), the public publish template and the outcomes recorded 2026-08-15; the GitLab-side change was made through the GitLab API and that call was not retained) |
| Evidence basis | [CI push identity](../../terraform/foundation/README.md#ci-push-identity) and [Status](../../terraform/foundation/README.md#status). The provider, role and policy creation, and the trust change from project path to project ID, are recorded as outcomes on 2026-08-15 without retained output. That trust change re-pinned the same project. Later publications through the identity, including retained private evidence of one on 2026-09-17, show indirectly that the trust admits a main-branch job. The GitLab setting is not AWS evidence. |
| Authority | Explicit owner grant (IAM trust change and GitLab project settings) |
| Cost | None (the OIDC provider, role and inline policy carry no direct charge) |

**Step history.**

- Step 1: on 2026-08-15 the setting was changed through the GitLab API with a temporary project
  access token, which was revoked after the read-back. The exact call, the token's role and scope,
  and whether the GitLab UI exposes the setting were not recorded.
- Step 3: the accepted shape is the one recorded for the 2026-08-15 change from project path to
  project ID (0 added, 1 changed, 0 destroyed), followed by a plan with no changes. That change
  re-pinned the same project and ran before the hosted zone, the certificate and `public_domain`
  existed.

**Known limitations.**

- The reference project marks both variables masked. Whether they are also protected was not
  recorded.
- No trust read-back has ever been retained; the last recorded one is 2026-08-15. See
  [Read back the CI trust](#read-back-the-ci-trust).
- The trust pins exactly one subject. Setting a different `gitlab_project_id` on an existing root
  replaces the trusted project and disconnects the previous one. That has never been executed.
- No trust change has run against the current root, with the hosted zone, the certificate and
  `public_domain` present.

### Diagnose a failed publication

**Validation:** EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-15) · **Published command form:** not executed as written

**What this does.** Maps an observed publication failure to its measured cause and its correction.
Only failures that have actually occurred are listed. Failures that have not occurred, such as an
audience or subject mismatch at the STS call, are not listed. This is a symptom table; it contains
no command.

**Before you start.**

- [ ] The failing publish job, open in GitLab, so you can see where it failed.

**Safety and authority.** Read-only to diagnose, with no approval needed. A correction that changes
the trust or GitLab settings is mutating and needs an explicit owner grant.

**Steps.**

1. Match the failing publish job against the table.

   | Symptom | Observed cause | Correction |
   |---|---|---|
   | GitLab refuses to issue the job's ID token, and the job fails before any AWS call | The project's path had previously belonged to another GitLab project | Switch the sub-claim components to `project_id`, `ref_type`, `ref` and pin the trust to the project ID, as in steps 1 to 3 of [Connect a GitLab project](#connect-a-gitlab-project-to-the-ci-push-identity) |
   | The token exchange, the STS call and the registry login succeed, and then the push fails | `ECR_REGISTRY` held the registry host plus the repository path | Set `ECR_REGISTRY` to the registry host only; the repository path belongs in `ECR_REPOSITORY` |

2. Apply the correction in the matching row, under an explicit owner grant when it changes the trust
   or GitLab settings.

**Expected result.** The symptom matches one row, and that row names the cause and the correction.

**PASS when.**

- [ ] The symptom matches one row of the table.
- [ ] Any correction that changes the trust or GitLab settings ran under an explicit owner grant.

**STOP if.**

- A correction would change the trust or GitLab settings, and no explicit owner grant covers it.

**If it fails.** A symptom that matches no row has no written diagnosis in this suite.

**Evidence to keep.** None is prescribed by this procedure.

**Next step.** The next publication from the project, outside this runbook
([GitOps Delivery](../implementation/gitops-delivery.md#1-build-once-gitlab-ci-to-an-immutable-digest)).
Publication is billable, because ECR bills stored image data from the first image, and it needs
its own explicit owner authorization. The cost gate runs first: read the budget back
([Read back the budget and its alert states](cost-and-residue.md#read-back-the-budget-and-its-alert-states))
and [re-check the prices](cost-and-residue.md#re-check-prices-before-billable-work). The price
table has no registry-storage rate, so that re-check stops and gives no complete storage
estimate; the owner approves a re-estimate before the publication. Once a repository holds more
than 10 tagged images, its lifecycle policy can expire the oldest.

#### Engineering notes

| Field | Value |
|---|---|
| Validation status | EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE (2026-08-15) |
| Published form | not executed as written (a symptom table built from the outcomes recorded 2026-08-15; it contains no command) |
| Evidence basis | Both cases were observed and corrected on 2026-08-15 and recorded as outcomes without raw output; a successful publication followed the corrections. The first case never reached AWS. |
| Authority | None to diagnose; an explicit owner grant for a correction that changes the trust or GitLab settings |
| Cost | None |

**Known limitations.** Failures that have not occurred, such as an audience or subject mismatch at
the STS call, are not listed.

## Not yet exercised

| Item | Status | Where described |
|---|---|---|
| First build of the evidence store, the registry repositories and the CI identity on the current root. The historical creations ran on older root shapes (the evidence store on 2026-08-08; the checkout repository and the CI identity on 2026-08-15) and are EXECUTED — RECORDED ONLY; RETAINED EXECUTION EVIDENCE NOT AVAILABLE. On a build from nothing the full plan adds them together with the certificate; that combined plan has never run, and no plan shape for it is published. | UNEXERCISED | [Public DNS](../../terraform/foundation/README.md#public-dns) for the order; [public-dns-and-certificate.md](public-dns-and-certificate.md) |
| Adding a registry repository against the current root, with the hosted zone and certificate present and `public_domain` supplied | DESIGNED-NOT-EXECUTED | [Add a registry repository](#add-a-registry-repository-and-widen-the-ci-push-scope) |
| A trust change against the current root, with the hosted zone, the certificate and `public_domain` present | DESIGNED-NOT-EXECUTED | Step 3 of [Connect a GitLab project](#connect-a-gitlab-project-to-the-ci-push-identity) |
| Connecting a GitLab project to a root first built with that project's ID: the step 2 branch that skips step 3 and relies on step 4 to read the pinned subject back. The recorded connection used a trust change, because the historical first build pinned the project path. | DESIGNED-NOT-EXECUTED | Step 2 of [Connect a GitLab project](#connect-a-gitlab-project-to-the-ci-push-identity); the first build it presumes is the first row of this table |
| Step 1's provider URL, client-ID and tag read, and step 2's federated-principal count | DESIGNED-NOT-EXECUTED | Steps 1 and 2 of [Read back the CI trust](#read-back-the-ci-trust); no record shows either read |
| A request over plain HTTP to confirm the evidence bucket denies it | UNEXERCISED | [Read back the evidence-store controls](#read-back-the-evidence-store-controls) |
| Registry retention review before an eleventh tagged image in `astroshop/checkout` | UNEXERCISED | [Artifact registry](../../terraform/foundation/README.md#artifact-registry) |
| Recovering a lost repository or image by rebuilding from source. A rebuilt image carries a new digest, because build reproducibility is not measured, so every pin to the old digest would need a reviewed change. | UNEXERCISED | [ADR-0009](../decisions/0009-define-the-software-delivery-model.md), [Artifact registry](../../terraform/foundation/README.md#artifact-registry) |
| Decommissioning a registry repository | UNEXERCISED | [Artifact registry](../../terraform/foundation/README.md#artifact-registry) |
| Revoking or rotating the CI push trust, including pointing an existing root at a different GitLab project, which replaces the only trusted subject and disconnects the previous project | UNEXERCISED | None |
| Final decommission of the evidence store | UNEXERCISED | [Final decommission](../../terraform/foundation/README.md#final-decommission), an order only: no command-level procedure and no reviewed saved-plan form exist |

## Reproducibility gaps

What a new engineer cannot reproduce from the public repositories today, from the facts this runbook
records.

1. **Mirroring a platform image into `platform/`.**
   - *Cannot be reproduced:* populating `platform/opentelemetry-collector`. This suite publishes no
     procedure for mirroring a third-party platform image into the `platform/` namespace. The
     Collector image there was mirrored on 2026-09-07: copied by its single-platform digest, not the
     multi-platform index, from the administrator session outside CI, because the push role cannot
     reach that repository
     ([CI push identity](../../terraform/foundation/README.md#ci-push-identity)), and then checked
     by manifest hash. The reference mirror used `crane`. The repository must hold the pinned image
     by digest before any runtime uses it.
   - *Public contract:* the repository is declared in the foundation root and is outside the push
     scope ([Artifact registry](../../terraform/foundation/README.md#artifact-registry),
     [Read back the CI push scope](#read-back-the-ci-push-scope)). A mirrored image's bytes can be
     checked with [Verify an image in the registry by digest](#verify-an-image-in-the-registry-by-digest).
     Its admission belongs to
     [ADR-0015](../decisions/0015-define-security-admission-and-exception-governance-for-platform-managed-runtime-components.md)
     and the pin-and-mirror rule of
     [ADR-0017](../decisions/0017-adopt-a-full-fleet-end-to-end-platform-validation-program.md),
     which this suite does not cover yet.
   - *Needed later:* yes, a public mirroring procedure, including its admission.
2. **The GitLab side of the CI identity.**
   - *Cannot be reproduced:* the exact GitLab API call that set `ci_id_token_sub_claim_components`,
     the role and scope of the temporary token that made it, and whether the GitLab UI exposes the
     setting, were not recorded. Whether the two CI/CD variables are also protected was not
     recorded.
   - *Public contract:* the required read-back `["project_id", "ref_type", "ref"]`, the trusted
     subject in [`ci-identity.tf`](../../terraform/foundation/ci-identity.tf), and the two masked
     variables and their value shapes in
     [Connect a GitLab project to the CI push identity](#connect-a-gitlab-project-to-the-ci-push-identity).
   - *Needed later:* yes, a recorded, published form of the GitLab change, with the token's role and
     scope.
3. **A first build of this root on the current configuration.**
   - *Cannot be reproduced:* on a build from nothing, the full plan adds the evidence store, the
     registry repositories and the CI identity together with the certificate. That combined plan
     has never run, and no plan shape for it is published. The historical creations ran on older
     root shapes.
   - *Public contract:* the build order in [Public DNS](../../terraform/foundation/README.md#public-dns)
     and [public-dns-and-certificate.md](public-dns-and-certificate.md). The acceptance shapes on
     this page cover only adding a repository and a trust change on an existing root.
   - *Needed later:* yes, an acceptance plan shape for the first build.
4. **Revoking or rotating the CI push trust.**
   - *Cannot be reproduced:* no procedure exists for revoking or rotating the trust, including
     pointing an existing root at a different GitLab project, which replaces the only trusted
     subject and disconnects the previous project.
   - *Public contract:* the trust pins exactly one subject, built from `gitlab_project_id`
     ([CI push identity](../../terraform/foundation/README.md#ci-push-identity)).
   - *Needed later:* yes, a procedure; [Not yet exercised](#not-yet-exercised) names no
     description for it today.
5. **Rebuilding a lost repository or image from source.**
   - *Cannot be reproduced:* the same image digests. A rebuilt image carries a new digest, because
     build reproducibility is not measured, so every pin to the old digest would need a reviewed
     change. The rebuild has never been exercised.
   - *Public contract:* rebuild from source under
     [ADR-0009](../decisions/0009-define-the-software-delivery-model.md) and the registry's recovery
     path in [Artifact registry](../../terraform/foundation/README.md#artifact-registry).
   - *Needed later:* yes, an exercised recovery procedure.
6. **The executed forms behind the published commands.**
   - *Cannot be reproduced:* no procedure on this page is published in the form that ran. The
     2026-09-22 registry apply and read-back ran through a private reviewed tool on exported
     credentials. The executed 2026-09-22 push-scope read-back allowed for IAM briefly returning the
     previous document; the published read repeats those bounds by hand, and that read-back matched
     on its first read, so it did not exercise the repeat. The evidence-store, CI
     trust, GitLab-side and diagnosis records are outcomes without retained output.
   - *Public contract:* the published commands, expected results and STOP conditions on this page,
     each with a note on what it is derived from.
   - *Needed later:* no new tool is named. A published form counts as executed as written only
     after a run of that exact form with its output retained
     ([Validation labels](README.md#validation-labels)).

<a id="hidden-prerequisites"></a>

## Background prerequisites

- The foundation root's four execution inputs ([Input](../../terraform/foundation/README.md#input)):
  a globally unique evidence bucket name, the account ID, the GitLab project's numeric ID and a
  registered apex domain; and the state bucket name from the bootstrap root for `backend.hcl`.
- A GitLab.com project that holds the workload source and its pipelines, with GitLab API access
  able to change its project settings and access to its CI/CD variables. The reference change used a
  temporary project access token, revoked after use; the token's role and scope were not recorded.
- The project's `ci_id_token_sub_claim_components` attribute, set to `project_id`, `ref_type`,
  `ref`. It is produced by step 1 of
  [Connect a GitLab project to the CI push identity](#connect-a-gitlab-project-to-the-ci-push-identity),
  not needed before it.
- Two masked GitLab CI/CD variables: `AWS_ROLE_ARN`, the push role's ARN, and `ECR_REGISTRY`, the
  registry host. They are produced by step 5 of the same procedure, not needed before it.
- `crane`, for mirroring a platform image into `platform/`; the reference mirror used it, and this
  suite publishes no mirroring procedure.
