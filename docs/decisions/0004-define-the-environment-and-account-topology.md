# ADR-0004: AWS account and environments

Status: Accepted (2026-07-30); revised 2026-10-21, decision unchanged.

## What we will use

One dedicated AWS account in us-east-1, with three environment roles:

- Dev: build and test platform changes.
- Validation: run QA and staging checks.
- Production Validation: run the final production-like tests.

This is a reference project with no real users. Permanent production
hosting is outside its scope.

Changes move through Dev → Validation → Production Validation.
Record owner approval before the final stage.

Each environment has its own Terraform root and state. No root manages
more than one environment.

Use two Availability Zones where the selected services require or
justify them. A third AZ needs a documented service or runtime reason.

## How we keep it manageable

Create runtime only for approved work windows. Capture evidence,
destroy runtime when the window ends and verify cleanup. ADR-0013
replaces the original decision to keep Dev runtime continuously running.

Retain only approved resources, such as the Terraform state backend
and foundations approved by later ADRs. Each needs a purpose, owner,
visible cost, recovery procedure where applicable and final removal
procedure. Follow ADR-0013 for retention and cost controls.

One account keeps setup manageable. Combining QA and staging in
Validation avoids duplicate environments.

Separate state, naming, tags and access controls reduce interference
within the account. They do not provide account-level isolation.

Revisit this model if real users, multiple teams, stronger isolation,
quota limits or separate billing require a different setup.
