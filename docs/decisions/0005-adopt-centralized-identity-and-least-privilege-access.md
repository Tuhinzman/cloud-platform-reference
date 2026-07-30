# ADR-0005: Adopt centralized identity and least-privilege access

## Status

Accepted (2026-07-30)

## Context

Identity is this platform's first security boundary. Trust is granted to
verified identities, never to network location. The requirements baseline
makes that concrete: human access must authenticate through a central
federated identity source and leave security-relevant actions attributable
(REQ-005), long-lived static credentials are avoided where practical
(REQ-006), and privileged access must be explicitly granted and controlled
(REQ-007).

The provider, the definition tool, and the topology are already fixed: AWS
(ADR-0002), Terraform with remote state (ADR-0003), and one dedicated
account in us-east-1 with three environment roles (ADR-0004). Daily work on
this platform is Terraform through the CLI, which makes the human access
model the decision that determines whether any standing cloud credential
exists at all. This record settles how humans, workloads, and automation are
identified, what powers each identity class carries, and what evidence
access leaves behind.

## Decision

Identities are separated by class, and no identity serves more than one
purpose: the account root user, the human owner, future human operators,
workload identities, automation identities, and the break-glass path each
have their own boundary.

Human sign-in goes through AWS IAM Identity Center, using its organization
instance with the built-in identity store and multi-factor authentication.
Console and CLI sessions both use short-lived credentials issued at sign-in.
Enabling the organization instance requires AWS Organizations, so an
organization exists around the single dedicated account as a technical
prerequisite of the selected identity solution. The one-account topology of
ADR-0004 is unchanged. Organizational units, service control policies,
account vending, delegated administration, and multi-account governance are
all out of scope of this record.

The root user is never used for daily administration. It keeps
multi-factor authentication, holds no access keys, and is reserved for the
few account-level tasks that require root and for emergency recovery. Every
root session is recorded and reviewed afterward.

The owner works through two permission sets. ReadOnly serves inspection,
review, and evidence checking. Administrator serves approved implementation
and administrative work. Choosing Administrator at sign-in is the explicit,
logged elevation step. No further permission sets are created until a real
job needs one.

No long-lived human access keys exist, including for bootstrap work. The
state-backend bootstrap runs on the same short-lived Identity Center
credentials as everything else. No credential is shared, and none appears
in the repository, images, evidence, or local configuration files.
Short-lived cached session tokens are acceptable because they expire on
their own.

Workloads will use identity-based access with no embedded cloud
credentials, scoped to their environment and to least privilege, short-lived
where the runtime supports it. The concrete mechanism is selected with the
runtime decision. Future automation uses a dedicated non-human identity
with short-lived federated credentials, begins plan-only, and keeps plan
and apply permissions separate where practical. Automatic apply remains
unapproved.

The break-glass path is the account root recovery path. No standing
break-glass user is created. Break-glass use is exceptional, recorded,
reviewed, and followed by recovery actions where needed. Access grants,
changes, and revocation all happen in Identity Center, and the owner
reviews access at material milestones and after any privileged or
break-glass use. Access evidence must show who authenticated, under which
permission set, and what changed. The audit service itself is selected in a
later record.

## Considered Options

| Option | Assessment | Outcome |
|---|---|---|
| Root user for daily administration | No scoping, full-account blast radius on every mistake, erodes the recovery path | Rejected |
| IAM user with long-lived access keys | CLI work would rest on standing keys with rotation burden, against the intent of REQ-006 | Rejected |
| AWS IAM Identity Center | Central sign-in, short-lived console and CLI credentials, permission sets, MFA, no additional charge | Selected |
| External identity provider federation | An external dependency a one-person project does not need yet | Deferred |
| Local static credentials with role assumption | The base credential remains long-lived | Rejected |

## Rationale

The decisive fact is the shape of daily work. This platform is built
through Terraform, so the CLI needs credentials constantly. On the IAM-user
path those credentials are long-lived access keys, which is exactly the
standing secret the requirements push against. On the Identity Center path
they are short-lived sessions that expire on their own. The most exposed
credential in the project simply stops existing.

Centralization does the rest. REQ-005 asks for a federated identity source
where access is granted and revoked in one place, and Identity Center is
that place for console and CLI alike. Splitting the owner's access into
ReadOnly and Administrator makes elevation a deliberate, logged choice
rather than a permanent state. Keeping root out of daily use preserves it
as a clean recovery path instead of a worn master key.

For one person, a single MFA-protected IAM user looks simpler, and that
option was weighed seriously. It loses on the credential question above and
on growth: Identity Center is native to additional users and additional
accounts, so this model survives the expansion triggers recorded in
ADR-0004 without redesign. The Organizations prerequisite is the honest
cost of the selection. It is accepted deliberately, as plumbing for the
identity solution, not as an architectural objective.

## Consequences

Gained: no standing human cloud credential anywhere in the project, one
place to grant and revoke access, elevation that is explicit and logged,
attribution for every security-relevant action, and an identity model that
extends to more people or more accounts without being rebuilt.

Paid for: an AWS Organizations instance now exists as a prerequisite and
must not quietly grow into governance scope, which stays explicitly out of
bounds. Identity Center becomes the sign-in dependency, with the root
recovery path as the documented fallback. During implementation,
administrative sessions may remain common, so the value of the two-set
split depends on the review habit that surrounds it. Sign-in requires an
explicit permission-set selection.

## Deferred Decisions

This record leaves open, for later decision records or approved
implementation planning: the exact contents of the permission sets and any
IAM policies, the workload identity mechanism, the automation federation
and its delivery tooling, the audit and logging service selection, external
identity provider integration, and any organizational units, service
control policies, or multi-account governance.

## Revisit Triggers

Revisit this decision if additional human operators join, if multiple teams
form, if a multi-account topology is adopted, if separation-of-duties or
compliance requirements appear, if automation apply is ever approved, if an
external identity provider becomes necessary, if break-glass use stops
being exceptional, or if Identity Center's capabilities or terms change in
a way that alters this analysis.
