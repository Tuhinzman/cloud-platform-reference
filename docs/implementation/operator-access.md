# Operator Access Runbook

## Purpose

Human access to the project AWS account runs through AWS IAM Identity Center.
Console and CLI sessions both use short-lived credentials issued at sign-in.
Long-lived IAM user access keys are not the approved operating model for this
platform, and that includes bootstrap work.

The reasoning, the alternatives, and the boundaries are recorded in
[ADR-0005](../decisions/0005-adopt-centralized-identity-and-least-privilege-access.md).
This document is the procedure only.

## One-time setup

Done once per operator, in the project account.

1. Create the operator's user in IAM Identity Center.
2. Register an MFA device for that user and require MFA at sign-in.
3. Create or select two permission sets. `ReadOnlyAccess` covers inspection,
   review, and evidence checking. `AdministratorAccess` covers approved
   implementation and administrative work.
4. Assign the user, or a group containing the user, to the project AWS account
   with both permission sets.
5. Configure one local CLI profile per permission set:

```
aws configure sso --profile cloud-platform-readonly
aws configure sso --profile cloud-platform-admin
```

Keeping the profiles separate is what makes elevation explicit. Reaching for
`cloud-platform-admin` is a deliberate choice that stays visible in the command
that used it, rather than a permission level already held by default.

The CLI may first ask for an SSO session name, then for the Identity Center
start URL, its region, and the registration scope. It opens a browser for
authorization, then lists the AWS accounts and roles available to the user, so
the account and the permission set are each selected deliberately. Prompt order
and wording differ between AWS CLI versions. Set the default region to
`us-east-1`. The real start URL, account ID, and role names belong in local
configuration, not in this repository.

## Normal login

Log in with the profile the work needs. Inspection and review run on the
ReadOnly profile.

```
aws sso login --profile cloud-platform-readonly
aws sso login --profile cloud-platform-admin
```

## Verification

Confirm which identity the CLI actually resolved before running anything
against AWS, using the profile you intend to work with:

```
aws sts get-caller-identity --profile cloud-platform-readonly
```

The `Arn` field should be an STS assumed role whose role name carries the
permission set that was deliberately selected:

```
arn:aws:sts::<account-id>:assumed-role/AWSReservedSSO_ReadOnlyAccess_<suffix>/<user>
arn:aws:sts::<account-id>:assumed-role/AWSReservedSSO_AdministratorAccess_<suffix>/<user>
```

Read the permission set out of that ARN rather than trusting the profile name,
and read the account ID on the same line. A profile can be pointed at the wrong
account or resolve a wider role than intended, and the returned ARN is what
shows which one is actually in force.

An `arn:aws:iam::<account-id>:user/<name>` result means the CLI resolved a
different credential source. Stop and fix the profile before continuing.

## Session expiry

Sessions expire on their own. When a command fails with an expired or missing
token, run `aws sso login --profile <profile>` again for the profile in use.
Nothing else needs to be reissued.

## Security notes

- No SSO token, authorization code, access key, or other credential value goes
  into documentation, evidence files, commit messages, or issue text.
- If IAM Identity Center access is unavailable, recovery goes through the
  account root user, which ADR-0005 designates as the break-glass path. Root is
  not used for routine administration.
- A working Identity Center session shows that short-lived operator access is
  available. It does not show that every long-lived IAM access key in the
  account has been removed. That is separate work and needs its own evidence.

## Retire old IAM access keys

This covers a human IAM user access key, meaning the Access Key ID and Secret
Access Key pair an operator holds. It does not cover workload identities, CI
federation, or the temporary credentials Identity Center issues. The operating
model leaves no room for a long-lived human key, bootstrap work included, so an
existing one is retired rather than kept as a fallback.

Deactivate before you delete. Deactivation is reversible, so if something still
depends on that key you can re-enable it while you find out what. The sequence
below is what turns an accidental fall back to the old default credential path
into an authentication failure instead of a silent success.

1. Complete the setup and login above, so Identity Center access is working.
2. Run `aws sts get-caller-identity --profile cloud-platform-admin`.
3. Confirm the result is an STS assumed role carrying
   `AWSReservedSSO_AdministratorAccess_`, not an IAM user.
4. From that same Administrator session, deactivate the old access key. The key
   being retired must never be the credential that performs its own
   deactivation. Do not delete it yet.
5. In a fresh shell with no profile set, run `aws sts get-caller-identity`. It
   should now fail to authenticate.
6. In that same shell, `aws sts get-caller-identity --profile cloud-platform-admin` should still return the assumed role.
7. Delete the key only after steps 5 and 6 pass, and only as a separately
   approved cleanup step.

A key counts as removed once its deletion has been verified. Until then it is
deactivated, and deactivated is what the evidence supports.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `AWS accounts (0)` during `aws configure sso` | The user or group has no assignment to the project account. |
| The expected permission set is missing from the role list | The permission set was never created, or it is not assigned to this user in this account. |
| The assumed-role ARN carries a permission set other than the one intended | The profile was configured against a different role, and it may also be pointed at a different account. Reconfigure it before running anything further. |
| `get-caller-identity` returns an IAM user ARN | The wrong profile was used, or a long-lived key is taking precedence through environment variables or the shared AWS credentials file. |
