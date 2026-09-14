# Runtime Validation

Every capability claim in this repository rests on a bounded Dev runtime window: the
runtime is created from Terraform under a written authorization with a hard teardown
time, exercised against frozen objectives, evidenced, destroyed, and verified clean. Raw
evidence stays private. This page is the sanitized summary, in the vocabulary used
throughout: **PROVEN**, **PARTIALLY PROVEN**, **NOT PROVEN**, **INDETERMINATE**,
**DECLARED LIMITATION**.

## Windows

Six windows have been opened and destroyed. All times are UTC.

| Window | Date | Scope exercised | Result | Teardown | Billable span, cost |
|---|---|---|---|---|---|
| EKS runtime | 2026-08-14 | First creation of the 17-resource Dev runtime from Terraform; cluster reachable; private egress from a pod through the NAT gateway; all six objectives | PASS | 17 destroyed; post-destroy plan converged on the same 17; orphan scan clean | ~1h08m runtime basis; ~1.50 USD planning estimate |
| RW-1 | 2026-08-24 | Argo CD v3.5.1 and the secret-synchronisation controller installed from pinned manifests; repository credential absent before and after install; ExternalSecret synced through Pod Identity | PASS | 17 destroyed; destroy set exact match; every orphan class zero | Per-window actual not measured; frozen ceiling 2.18 USD |
| RW-2 | 2026-08-26 | First Argo CD reconciliation: comparison completed, one manual sync Succeeded, Synced and Healthy; the running container's image read back by digest | PASS | 17 destroyed; post-teardown census all runtime classes zero | Same frozen relationships as RW-1; per-window actual not measured |
| RW-3, first attempt | 2026-09-10 | Opened and aborted at its first gate: Argo CD could not admit the trace-store desired state (a label exceeded 63 bytes). No traffic, fault or restore ran | ABORTED on a measured defect; corrected the same day | 17 destroyed; post-census zero residual | 0.787 h; ≤ 0.27 USD |
| RW-3, second | 2026-09-11 | Six applications Synced and Healthy; retention read back 2h on all three stores; 1,201 baseline requests, 100% HTTP 200; four-signal digest reconciliation; fault applied and restored through Git; evidence exported and read back | PASS with two INDETERMINATE items (below) | 17 destroyed 19:05Z; post-destroy plan 17 to add; census zero | 4.625 h; ≤ 1.53 USD |
| Alerting | 2026-09-13 | Alert rule fired on an induced fault and reached the operator by email through the notification service, published under Pod Identity; workload identity distinctions verified; fault restored | Delivery PASS; one refinement clause NOT PASS (below) | Destroyed 19:35Z, 168 min before the trigger; zero residual; 661 evidence objects read back | 2.161 h; ≤ 0.72 USD |

Cost figures are rate-derived upper bounds from the applied shape and the billable span,
not billing statements; the Cost Explorer actual was not retrieved at window close.

## What has been demonstrated

| Capability | Status | Basis |
|---|---|---|
| EKS runtime provisioned and destroyed from Terraform | PROVEN | Six windows; each opened with exactly 17 additions and closed with exactly 17 deletions; the post-destroy plan converges on rebuilding the same set |
| Private node egress through the NAT gateway | PROVEN | A pod resolved DNS and reached an external HTTPS endpoint from the NAT address (2026-08-14) |
| Argo CD reconciliation of Git desired state | PROVEN | RW-2 first sync; six applications Synced and Healthy in the two most recent windows |
| Image identity: running container digest equals the published digest | PROVEN for shipping, PARTIALLY PROVEN for quote and checkout | Four independent signals agree for shipping in both recent windows; for quote and checkout the container-level signals fail, one from an enrichment gap and one because the service was not on the exercised path. The wrong-digest control fires |
| EKS Pod Identity for a workload | PROVEN for the alerting publisher | Nine distinctions verified, including the role read from the live association API and scope confirmed by an authorization-class error; no credential mounted |
| Secret synchronisation through the controller's Pod Identity | PARTIALLY PROVEN | The controller started with the credential path injected and the secret arrived; attribution of the read to the controller's own role is not claimed |
| Telemetry collection with Kubernetes identity | PROVEN | Identity survives the collection path on metrics, logs and traces |
| Operational views | PARTIALLY PROVEN | Trace-to-logs traversal through the view is NOT PROVEN; correlation evidence came from the store APIs |
| Alert delivery | PROVEN | Rule → contact point → notification service under Pod Identity → operator mailbox, receipt attested |
| Alert cardinality refinement | NOT PASS, withdrawn | A clause added after the criterion was frozen asserted an exact notification count; measurement falsified it |
| Retention, 2 h on all three stores | PROVEN as combined evidence | Running configuration read back and the deletion mechanism measured; object deletion on EKS not directly observed |
| Fault and restore through Git | PROVEN | See below |
| Effect of the memory fault | INDETERMINATE | The 24Mi limit produced no OOMKill under 2,000 requests, so that fault did not exercise its intended effect; the liveness-probe fault in the alerting window did |
| Teardown and zero residual | PROVEN | Every window: targeted destroy of exactly the runtime set, orphan census by resource class returning zero |
| Evidence export and read-back after destruction | PROVEN | 437 objects exported and 440 read back after teardown (RW-3); 661 after the alerting window |

## Recovery pattern

Recovery is a Git operation, not a cluster operation. Before a window opens, the desired
state is frozen at an anchor commit. The fault is one semantic change on a branch from that
anchor, merged through a merge request inside the window; the restore is a commit that
reverses exactly that change, merged the same way. Proof is tree equality: the restore
merge commit's tree hash must equal the anchor's tree hash, which is checked before the
recovery leg is accepted.

Measured in both recent windows: `a19d3e2` (anchor) and `bf019ff` (restore) share tree
`12b6372f…`; `7d11681` (anchor) and `68a9432` (restore) share tree `82224ce7…`. Recovery
verification then checks the faulted objects present-then-absent (8 of 8), and the whole
evidence-to-recovery sequence completed 7m41s after the fault ended against a 30-minute
requirement. The desired-state repository is private, so these hashes are stated rather than
linkable; the pattern is described in the delivery model in
[ADR-0009](../decisions/0009-define-the-software-delivery-model.md) and
[ADR-0011](../decisions/0011-define-the-backup-and-recovery-model.md).

## Declared limitations

- The final trace-store selection ADR-0010 defers to implementation evidence is still open.
- Trace-to-logs traversal through the operational view is NOT PROVEN: the log-store
  datasource plugin unregistered itself at runtime during a background upgrade.
- Telemetry enrichment is not uniform: one service's logs lack container-level identity, and
  one service was not on the exercised request path.
- During one continuous fault the alert transitioned several times and produced six
  notifications in roughly nineteen minutes; the mechanism is not conclusively isolated.
- The full application fleet has not been deployed; rollback and cross-environment
  promotion have not been exercised; the Validation and Production-Validation environments
  have not been built.
- Cost is estimated from rates and spans, not measured from billing.
- Every result above is scoped to Dev, to the three-service workload slice, and to the
  windows named. Nothing here is a production-readiness claim.
