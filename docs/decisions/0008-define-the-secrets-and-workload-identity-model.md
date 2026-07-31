# ADR-0008: Define the secrets and workload identity model

## Status

Accepted (2026-07-30)

## Context

ADR-0005 settled human identity: sign-in through IAM Identity Center, no
long-lived human credential anywhere, and a note that workloads would get
their own mechanism once the runtime was chosen. The runtime is now
Amazon EKS with one cluster per active environment (ADR-0006), and the
network keeps those environments apart (ADR-0007). This record answers
exactly two questions: how workloads obtain secrets, and how workloads
obtain AWS permissions without long-lived credentials.

Workloads must authenticate with identities rather than long-lived
static credentials where practical, both to the platform and to
external services, and any that remain need a documented justification
(REQ-006). Secrets must be retrieved at runtime from an external secret
source and never appear in code, images, or repositories (REQ-007).

Validation and Production Validation clusters are ephemeral, so
whatever holds secrets and identity must live outside the cluster and
survive its teardown.

## Decision

Human identity and workload identity remain separate systems. Humans
stay in IAM Identity Center as ADR-0005 defines. Workload
identity is machine-only: no human credential ever enters a workload,
and no workload identity is used interactively.

Workloads obtain AWS permissions through Amazon EKS Pod Identity, whose
per-cluster agent is a managed add-on under the rules of ADR-0006. Each
workload needing AWS access gets its own dedicated IAM role, scoped to
least privilege and its environment. Static AWS credentials in
workloads are rejected. The node IAM role never carries application
permissions, and pod access to the node's credentials through instance
metadata is closed during implementation. Where an external service
still forces a static credential, it lives in the secret store with the
documented justification REQ-006 requires.

Sensitive secrets have one system of record: AWS Secrets Manager.
Secrets reach applications through controlled synchronization into
Kubernetes Secrets, consumed natively. The Kubernetes Secret is
explicitly a delivery mechanism, never the system of record. The exact
synchronization mechanism is deferred.

Non-sensitive configuration lives in AWS Systems Manager Parameter
Store and is kept out of the secret store.

Secrets never cross environment boundaries. Dev, Validation, and
Production Validation each hold their own secrets, and each
environment's roles read only that environment's entries.

Encryption relies on the default AWS-provided keys initially.
Customer-managed KMS keys are deferred.

Rotation capability is mandatory. One validated rotation exercise is
required before implementation is considered complete. Rotation
automation is deferred.

## Considered Options

| Option | Assessment | Outcome |
|---|---|---|
| EKS Pod Identity with a role per workload | Role trust uses one generic service principal, so roles survive ephemeral cluster recreation | Selected |
| IAM Roles for Service Accounts | Works, but binds every role trust policy to a per-cluster identity provider that changes on every rebuild | Rejected |
| Static AWS access keys | Standing credentials that never expire and must be distributed, against REQ-006 | Rejected |
| Node IAM role for application permissions | Every pod on the node inherits the same permissions, so least privilege becomes impossible | Rejected |
| Parameter Store as the secret store | Free tier is attractive, but it has no native rotation capability | Rejected for secrets |
| Kubernetes Secret as system of record | Dies with its ephemeral cluster and is readable through API access alone | Rejected as record |
| Customer-managed KMS keys now | Monthly cost and operational coupling for control no current requirement asks for | Deferred |
| Shared secrets across environments | Breaks what promotion between environments proves, widens the blast radius of any leak | Rejected |

## Rationale

A workload is an identity of its own kind: its credentials must arrive
automatically and must expire. Mixing the classes would put a human
credential inside a pod or a machine role in interactive hands.

Pod Identity is selected for one decisive property. Its role trust
names a single generic EKS service principal, so IAM roles become
durable artifacts and an ephemeral cluster only recreates lightweight
associations and its agent add-on. IAM Roles for Service Accounts would
instead mean rewriting every workload role's trust policy on every
ephemeral rebuild. The rest need less argument: a node role hands one
permission set to every pod, and static keys are exactly the standing
secret this platform exists to avoid.

Secrets Manager earns the system-of-record role because it can do what
a record must: rotate credentials, scope access per secret, and leave
an audit trail of retrieval. Synchronization keeps REQ-007's boundary:
every value is retrieved from the store at runtime, none is embedded in
code, images, or repositories. The trail attributes most retrievals to
the synchronization component rather than to each workload. That is an
accepted trade-off, with the audit revisit trigger below as the escape
path. The store also
sits outside the cluster, so environment teardown never destroys a
secret. A Kubernetes Secret offers none of that, which is why it is
confined to the last hop. Parameter Store keeps configuration because
configuration does not need rotation.

Default encryption is sufficient today: the stores use AWS-managed keys
and cluster state uses an AWS-owned key, all encrypted at rest without
platform effort. Customer-managed keys would add recurring cost and a
key whose loss can take data or a cluster with it, for policy control
nothing currently demands. Rotation automation is deferred
deliberately. Proving the capability once gives honest evidence, and
automating every secret's rotation now would be ceremony ahead of need.

## Consequences

Gained: least privilege per workload, no standing workload credential,
secrets and permissions that stop at their environment boundary, an
ownership split where the platform owns stores and bindings while
applications only declare and consume, and a model that composes with
common Kubernetes synchronization and delivery automation.

Paid for: more IAM roles to define and review, a secret lifecycle to
operate alongside the platform, a recurring per-secret cost in Secrets
Manager, a synchronization component that must exist and stay tightly
scoped, and a rotation exercise that must be demonstrated before
implementation claims completion.

## Deferred Decisions

This record leaves open, for later decision records or approved
implementation planning: the exact synchronization mechanism, whether
an external-secrets controller class or a CSI driver class, IAM
policies and role names, the KMS layout, the rotation schedule,
certificate automation, and database credential generation.

## Revisit Triggers

Revisit this decision if a workload genuinely needs direct in-pod
retrieval instead of synchronization, if secret count or store cost
outgrows expectations, if a requirement demands customer-managed keys,
if the platform adopts compute that Pod Identity
does not support, or if audit needs outgrow the trail the stores
provide.
