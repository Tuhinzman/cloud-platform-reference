# Dev datastore

The persistent root for the Dev workload's durable datastore, which ADR-0011 and ADR-0012 place
in a managed service with native backup. It is its own root because its lifecycle is not the
Dev runtime's: a window's teardown never reaches this state.

## What it creates

| File | Resources |
|---|---|
| `network.tf` | DB subnet group over the two Dev private subnets, looked up by `Name` tag; a security group admitting TCP 5432 from those two subnet ranges, with no egress rule |
| `secrets.tf` | Secrets Manager containers for the master password and the application role password, created without a value; values are placed out of band and never written by Terraform |
| `database.tf` | A PostgreSQL 17.11 instance on `db.t4g.micro` with 20 GiB of encrypted gp3 storage, single-AZ and not publicly accessible, in the subnet group and behind the security group above, with seven-day automated backups, deletion protection and a final snapshot on deletion; and a Standard Parameter Store entry holding the instance address |

The master password is read from the master container at plan and apply time and sent to RDS
as a write-only argument, so it is stored in neither the state nor a plan file.

Inputs: `backend.hcl` and `terraform.tfvars` (`allowed_account_id`), both untracked.
The dev root's network must already exist. The master container must hold its value before
`database.tf` is planned, because planning reads it, and this root creates that container. The
root was therefore built in order: the network boundary and the two containers were applied
before `database.tf` existed, the master value was then placed out of band, and the instance
was applied last. A build from nothing in one checkout has not been exercised; it needs the
same order, for example by applying the network and container resources with `-target` before
the first full plan.

## What this root does not create

Any secret value. Only the master value is required, because only the instance reads it. The
application role's value is deferred, and its container stays empty until the path that
consumes it is designed and reviewed. The root creates no database role besides the master
user.

## Boundary

The security group admits every address in the two private subnets, so while a runtime
window is open every node and every pod in them can connect on TCP 5432. That is a
network-position boundary, not least privilege, and Kubernetes NetworkPolicy is not
enforced on the cluster.

## Debug logging

Never plan or apply this root with any `TF_LOG` variable set (`TF_LOG`, `TF_LOG_CORE`,
`TF_LOG_PROVIDER` and their provider- and SDK-specific forms; `TF_LOG=JSON` also logs at
`TRACE`), or with `TF_LOG_SDK_PROTO_DATA_DIR` set. The master value passes through the provider
on every plan and apply, and at `DEBUG` or `TRACE` it can be written to logs or protocol dumps.
Write-only handling keeps it out of state and plan files, not out of debug output.

## Decommission

Decommission has not been exercised. The instance is protected twice: deletion protection is
on in AWS, and `prevent_destroy` makes Terraform refuse any plan that would destroy it. Removing
it is therefore a reviewed change in three steps: remove `prevent_destroy` and set
`deletion_protection = false`, apply that change, then destroy. Deletion takes the final
snapshot `cloud-platform-reference-dev-datastore-final`. AWS refuses the deletion if a snapshot
with that name already exists, so a later decommission names its final snapshot `-final-2`,
`-final-3` and so on, in the same reviewed change.

The final snapshot is kept for 30 days after the evidence of the ADR-0017 validation programme
is closed, and is then deleted, or kept longer, only on an explicit owner review. Restoring from
a snapshot or from the automated backups has not been exercised, so a retained snapshot is not
proof that the data can be recovered.

Destroy this root before the dev network, whose VPC and private subnets it references. A
deleted secret stays recoverable for 7 days, and its name stays reserved until the deletion
completes.

Estimated cost, while the instance exists and whether or not anything uses it: about 0.0192 USD
an hour (about 14 USD a month) for the instance and its storage, and about 0.80 USD a month for
the two secrets. The instance runs in unlimited CPU-credit mode: CPU sustained above its baseline,
beyond the credits it earns, bills extra, up to about 0.15 USD an hour with both vCPUs at full
load, and nothing limits the total. Automated backup storage up to the allocated size carries
no charge; a final snapshot bills for its storage while it is kept. The subnet group, the
security group and the Standard parameter carry no charge.

## Status

The network boundary, the two secret containers, the instance and its endpoint parameter are
applied. The first apply added the subnet group, the security group, its two ingress rules and
the two containers, and nothing else, and AWS read-back verified each of them with the six
mandatory tags. The master container then received one value, placed out of band; the
application container holds none.

The second apply added the instance and the parameter and nothing else. AWS read-back verified
an available PostgreSQL 17.11 instance on `db.t4g.micro` with 20 GiB of gp3 storage encrypted
under an AWS-managed key, single-AZ, not publicly accessible, in the subnet group and behind the
security group above, with seven-day backups, deletion protection on, extended support disabled,
no RDS-managed master secret and the six mandatory tags, and a parameter holding the instance
address. The plan after apply reported no changes. A search of the state, the saved plan and
every log of that plan, apply and read-back found no copy of the master value. No workload uses
the instance yet.
