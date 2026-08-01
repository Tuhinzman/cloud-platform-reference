# Architecture Baseline

## Purpose

Two platform-wide facts are relied on by several accepted decisions without belonging to any one of them: the region the platform standardizes on, and the set of resources that survive environment teardown. This document is their single home.

It is not the [Requirements Baseline](requirements-baseline.md), which states measurable obligations. It records no new decision. Every statement here is either the rationale for a choice the accepted records already assume, or a consolidation of attributes those records already require. Each entry names the decision record that owns it, and where a record and this document ever disagree, the record wins.

## Regional Standardization

The platform runs in `us-east-1`, and every environment, every persistent foundation, and every cost figure in the project assumes it.

That fact is used more than it is explained. [ADR-0002](decisions/0002-select-aws-as-the-cloud-provider.md) selects AWS and explicitly defers region selection. [ADR-0003](decisions/0003-adopt-terraform-and-remote-state-management.md) then names `us-east-1` as the approved primary region and says the environment and topology decision will record the reasoning. [ADR-0004](decisions/0004-define-the-environment-and-account-topology.md) then lists the region among the things that are already fixed, citing a record for the provider and a record for the definition tool but naming none for the region. So the promise ADR-0003 made was never kept, and the reasoning was never written down anywhere. This section closes that gap without editing any accepted record.

The region was chosen on four grounds:

- **Service availability.** `us-east-1` is AWS's oldest and largest region and is generally the first to receive new services. Whatever later implementation decisions need, regional availability is unlikely to be the constraint that blocks them. That mattered at the time, because almost every technology decision was still open and the region should not have been the thing that narrowed them.
- **Cost.** `us-east-1` is consistently among AWS's lowest-priced regions, and AWS publishes much of its public pricing documentation against it. The cost model in [ADR-0013](decisions/0013-define-operations-and-cost-guardrails.md) is built from published `us-east-1` rates, so a reader can check the arithmetic against the same pages the project used. A region with sparser published pricing would have made that model harder to verify.
- **Availability-zone count.** The two-Availability-Zone baseline of ADR-0004 needs a region that comfortably exceeds it, which rules out the smallest regions and rules in this one.
- **Single-region by design.** The [Project Charter](project-charter.md) places multi-region disaster recovery out of scope and [ADR-0011](decisions/0011-define-the-backup-and-recovery-model.md) records region loss as an accepted, stated limitation. One region is therefore a deliberate boundary rather than a starting point that later grows.

The honest cost of the choice: `us-east-1` is AWS's busiest region and the one whose incidents draw the most public attention. A platform serving real users would weigh that differently. This one carries no production traffic, holds no availability commitment, and has already excluded multi-region recovery, so the exposure is accepted rather than mitigated.

Nothing in the architecture depends on the region beyond this. No accepted decision would have to be reopened to run the platform elsewhere, so a region change would be a rebuild against different published rates rather than a redesign. That is a property of the design, not a migration that has been tested.

## Persistent Foundations

Most of this platform is disposable. Environments are created for approved windows and destroyed afterward, which [ADR-0013](decisions/0013-define-operations-and-cost-guardrails.md) applies to all three environment roles including Dev. A small set of resources deliberately survives that teardown, because each holds something no environment can regenerate.

[ADR-0004](decisions/0004-define-the-environment-and-account-topology.md) requires every persistent resource to carry a documented purpose, cost visibility, a lifecycle owner, a recovery procedure where applicable, and a separate final decommission procedure. Individual records supplied those attributes unevenly. The table below collects them in one place so a reader does not have to reconstruct the set from nine decision records, and so nothing enters the account without them.

Every row is owned by the platform engineer role, which is the only operating role this project has ([ADR-0013](decisions/0013-define-operations-and-cost-guardrails.md)). Every row is excluded from routine environment teardown by definition, so the teardown column records the boundary that actually differs: when the resource itself is finally removed.

Where an owning record already stated an attribute, the cell restates it. Where a record made a resource durable without stating one, which is the gap this closure exists to fill, the cell records the answer that follows from the ADR-0004 rule. Those cells are a consequence of decisions already made rather than new ones, and implementation confirms each against the resource it actually creates.

| Foundation | Purpose | Lifecycle | Recovery | Teardown boundary | Owning records |
|---|---|---|---|---|---|
| Terraform state backend | Binds every definition to the real resource it manages. The only control asset with no other source, and the only one whose loss is silent. | Created by the bootstrap configuration before any other resource. Outlives every environment. | Object versioning: rollback answers corruption, version restore answers loss, resource import is the recorded last resort rather than the plan. | Excluded from every environment destroy. Removed only through its own documented decommission procedure, after nothing it manages remains. | ADR-0003, ADR-0011 |
| Artifact registry | Retains built images across environment lifecycles, so the same digest can be promoted rather than rebuilt. | Created before the first pipeline publishes. Storage bounded by lifecycle policies. | Rebuild from source through the delivery pipeline. No backup, because the source is authoritative. | Deleted once no environment references its images. | ADR-0009 |
| Secret store | System of record for sensitive values. Sits outside the cluster so environment teardown never destroys a secret. | Created before the first workload that needs a secret. Per-environment entries are isolated from each other. | The store's recovery window answers accidental deletion. Rotation, which is a mandatory validated capability, answers compromise. | An environment's entries are removed with that environment. The store is decommissioned when no environment holds entries. | ADR-0008, ADR-0011, ADR-0013 |
| Workload IAM roles | Least-privilege AWS access per workload, with no static credential anywhere. Durable because Pod Identity role trust names one generic service principal instead of a per-cluster identity provider. | Created with the environment's identity definitions. Survives cluster recreation, which is the property that made Pod Identity the selected mechanism. | Recreated from Terraform. Nothing to restore. | Destroyed with the environment they are scoped to, not with the cluster they happen to serve. | ADR-0005, ADR-0008 |
| Evidence and backup destination | Holds exported evidence and any backup artifact that must outlive the environment that produced it. Losing it does not impair recovery, but it destroys the project's ability to support its claims. | Created in the AWS foundation phase, before the first ephemeral environment and therefore before the first evidence that has to survive a teardown. | Product and layout are implementation decisions. Its own recovery path is documented when it is created, under the same ADR-0004 rules as every other row. | Retained across all environment windows. Decommissioned only at project end, after its contents are no longer needed to support a public claim. | ADR-0010, ADR-0011, ADR-0013 |
| DNS hosted zone | Authoritative DNS for the project-controlled hostname that the final HTTPS validation reaches. | Created in the domain phase and not before, because a hosted zone bills monthly from creation whether or not any record resolves. | Recreated from Terraform. Delegation is re-pointed at the registrar, which is outside AWS. | Retained across windows once created. Decommissioned with the domain. | ADR-0007, ADR-0013 |
| Durable workload datastore | Holds the workload data that must outlive the instances serving it, which is what gives the data-restore exercise a subject. | The product, its sizing, and its backup configuration are deferred to implementation ([ADR-0012](decisions/0012-formalize-the-reference-workload.md)). What is fixed is that the data lives in a managed service with native backup, never in cluster storage. | Native managed backup and restore, validated against an isolated target rather than over live data. | Retained across windows. Its managed backup enters as a billable foundation in its own right when the product is chosen. | ADR-0011, ADR-0012 |

Two clarifications, because both have caused confusion in this project already.

Non-sensitive configuration lives in Parameter Store and is durable, but it is not in this table. It carries no recurring charge and is declared in Terraform, which makes it a rebuild rather than designated state ([ADR-0008](decisions/0008-define-the-secrets-and-workload-identity-model.md), [ADR-0011](decisions/0011-define-the-backup-and-recovery-model.md)).

Networking is not in this table either. A VPC, its subnets, its route tables, and the internet gateway carry no direct hourly charge, but an uncharged resource is not automatically a retained one. ADR-0013 decides their retention per phase on rebuild time, drift risk, dependency cleanup, CIDR reuse, whether the phase owes a teardown proof, and operational simplicity. Nothing is retained merely because the environment role is named Dev.

## Relationship to REQ-019

Every row above is a resource that keeps existing after an environment is destroyed, which makes each one a documented exception in any zero-resource claim under REQ-019. A teardown proof states which of these remain and why, rather than claiming the account is empty.
