# Dev datastore

The persistent root for the Dev workload's durable datastore, which ADR-0011 and ADR-0012 place
in a managed service with native backup. It is its own root because its lifecycle is not the
Dev runtime's: a window's teardown never reaches this state.

## What it creates

| File | Resources |
|---|---|
| `network.tf` | DB subnet group over the two Dev private subnets, looked up by `Name` tag; a security group admitting TCP 5432 from those two subnet ranges, with no egress rule |
| `secrets.tf` | Secrets Manager containers for the master password and the application role password, created without a value; values are placed out of band and never written by Terraform |

Inputs: `backend.hcl` and `terraform.tfvars` (`allowed_account_id`), both untracked.
The dev root's network must already exist.

## What this root does not create

The database instance. It is added separately, once both secret values are in place.

## Boundary

The security group admits every address in the two private subnets, so while a runtime
window is open every node and every pod in them can connect on TCP 5432. That is a
network-position boundary, not least privilege, and Kubernetes NetworkPolicy is not
enforced on the cluster.

## Decommission

Destroy this root before the dev network, whose VPC and private subnets it references. A
deleted secret stays recoverable for 7 days, and its name stays reserved until the deletion
completes.

Estimated cost is about 0.80 USD a month for the two secrets; the subnet group and the
security group carry no charge.

## Status

Not applied. Nothing in this root has been validated against AWS.
