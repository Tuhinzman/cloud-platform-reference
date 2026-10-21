# ADR-0011: Backup and recovery

Status: Accepted (2026-08-01); revised 2026-10-21, decision unchanged.

## What we will recover

Rebuild from authoritative sources wherever possible. Use Terraform
for infrastructure and account configuration, GitOps for cluster
contents and source code for rebuilding images.

EKS recovery means recreating the cluster and reconciling its contents.
Operator-managed control-plane snapshots are not part of this model.
Recovery depends on available source repositories and documented
prerequisites.

Protect four kinds of state:

- Terraform state: recover a valid version from the remote backend.
  Resource import is the last resort.
- Persistent workload data: use a managed service with native backup
  and recovery when data must survive environment teardown.
- Secret-store contents: recover accidental deletion through the
  store's recovery window and respond to compromise through rotation.
- Exported evidence: retain it in recoverable, durable storage outside
  the environment.

Use in-cluster storage only for disposable or regenerable data,
unless a later Accepted ADR defines another recovery obligation.
Keep seed and migration steps repeatable.

Declare non-sensitive configuration in Terraform. Never export secret
values into Git or backup artifacts. Keep required decryption material
and recovery configuration separate from data backups and verify
their integrity.

Application rollback follows ADR-0009: revert the GitOps digest
reference. This changes code and configuration without restoring data.
If the previous version cannot use the current schema, document the
required data-recovery procedure.

## How we prove recovery and control cost

A backup is unproven until a restore succeeds.

Before declaring this implementation complete:

- Validate one Terraform-state recovery exercise.
- Validate workload-data restore once its data model is defined.
- Verify secret retrieval after recovering a simulated accidental deletion.
- Read exported evidence back after the environment is destroyed.

Use isolated restore targets and never overwrite live data.
Validate recovered data and application behaviour. Record the failure,
recovery steps, result and anything the exercise did not test.

Measure recovery time with a clear basis and data-loss exposure where
backups exist. Label timing bounds clearly. These are observations,
without guaranteed RTO or RPO targets.

Keep the state backend and approved durable destinations outside normal
environment teardown. Each retained destination needs a purpose, owner,
bounded cost, recovery path and final removal procedure. Declare these
resources in teardown reports and obtain separate approval for new
persistent costs.

Remove temporary exercise resources afterward. Verify teardown and
the absence of orphaned billable resources separately from recovery.

Region-level disaster recovery is outside scope. Cluster backup tooling
remains deferred.

Revisit if durable data, failed recovery exercises, evidence growth,
or unavailable source repositories make this model insufficient.
