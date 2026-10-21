# ADR-0008: Secrets and workload identity

Status: Accepted (2026-07-30); revised 2026-10-21, decision unchanged.

## What we will use

Use Amazon EKS Pod Identity for short-lived AWS credentials.
Each workload needing AWS access gets its own IAM role with only
the permissions required for its environment.

Manage the Pod Identity Agent as an EKS managed add-on under ADR-0006.

Pod Identity was selected over IAM Roles for Service Accounts because its
role trust names one generic EKS service principal, so IAM roles survive
cluster recreation. IRSA would bind every role's trust policy to a
per-cluster identity provider that changes on each rebuild.

Store sensitive values in AWS Secrets Manager. Synchronize them at
runtime into Kubernetes Secrets for applications to consume.
Secrets Manager remains the source of truth; Kubernetes Secrets
are the delivery mechanism.

Store non-sensitive configuration in AWS Systems Manager Parameter Store.

Keep IAM roles and source secrets outside the cluster so they survive
cluster recreation. Recreate Pod Identity associations with each cluster.

## Access and lifecycle rules

Keep human and workload identities separate. Never put human credentials
in workloads or use workload identities for interactive human access.

Do not use static AWS credentials in workloads. If an external service
requires a static credential, store it in Secrets Manager and document
why it is necessary.

Do not give the node IAM role application permissions. Block pod access
to node-role credentials through instance metadata.

Keep secrets separate for Dev, Validation and Production Validation.
Each environment's roles may read only its own secrets.

Never place secret values in source code, container images or repositories.
Keep the synchronization component's permissions narrowly scoped.

Start with default AWS-provided encryption keys. Customer-managed KMS
keys remain deferred.

Support secret rotation and validate at least one rotation exercise
before marking this implementation complete. Rotation automation
remains deferred.

Secret-store retrieval logs generally identify the synchronization
component. They do not establish which application consumed a secret.

This model adds secret-storage costs and a synchronization component
to maintain. Exact synchronization tooling and IAM policies are
implementation details.

Revisit if direct application retrieval, stronger audit requirements,
cost, encryption requirements or runtime compatibility require a change.
