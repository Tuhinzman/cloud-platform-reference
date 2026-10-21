# ADR-0005: AWS access and permissions

Status: Accepted (2026-07-30); revised 2026-10-21, decision unchanged.

## What we will use

Use AWS IAM Identity Center with its built-in identity store and MFA
for human access. Console and CLI sessions use short-lived credentials.

Use its organization instance, which requires AWS Organizations.
The platform still uses one dedicated account. Multi-account governance
is outside this decision.

The owner uses two permission sets:

- ReadOnly: inspect resources, review changes and check evidence.
- Administrator: perform approved implementation and administration.

Selecting Administrator is the explicit, logged elevation step.
Add another permission set only when a specific task needs it.

This avoids managing permanent human access keys. Identity Center
becomes the normal sign-in dependency, with root recovery as the fallback.

## Access rules

Keep human, workload and automation identities separate. Grant access
through verified identity and permissions; network location alone
does not grant access.

Protect root with MFA and no access keys. Use it only for tasks that
require root or emergency recovery. Record and review every root session.
Do not create a separate standing emergency user.

Long-lived human access keys must not exist, including for bootstrap
work. Never share credentials or place them in Git, images, evidence or
configuration files. Expiring local session caches are allowed.

Workloads use dedicated identities with only the permissions needed
for their environment. Do not embed AWS credentials. Use short-lived
credentials where the runtime supports them.

Automation uses a separate identity with short-lived federated
credentials. Start with plan-only access. Separate plan and apply
permissions where practical. Automatic apply remains unapproved.

Manage human access grants, changes and revocation through Identity Center.
Review access at material milestones and after privileged or emergency
use. Evidence must identify who signed in, their permission set and
what changed.

The exact permission-set contents and IAM policies, the workload identity
mechanism, automation federation tooling, audit service selection and any
external identity provider are deferred to implementation or later decisions.

Revisit when access requirements change or emergency access becomes routine.
