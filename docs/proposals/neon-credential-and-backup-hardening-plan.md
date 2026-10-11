# Plan: Neon credential and backup hardening

Date: 2026-10-10
Status: investigating
Level: L
Scope: Controlled Neon credential, role, backup/restore, and sensitive-artifact hardening.
Related artifacts: [brief](neon-credential-and-backup-hardening-brief.md) · [recommendation](neon-credential-and-backup-hardening-recommendation.md) · [investigation](../investigations/neon-credential-and-backup-hardening.md)
Approved: 2026-10-11 owner approval recorded in change log
Superseded-by: none

> This plan is not authorization to rotate credentials, change grants, create branches,
> export data, or mutate production.

## 1. Gates

- [x] Investigation and sanitized evidence requirements defined.
- [x] Brief and recommendation prepared.
- [x] Local Neon access evidence collected.
- [x] Project/branch/database context confirmed.
- [x] Role and grant matrix approved.
- [x] Capability roles created.
- [x] Runtime credential split designed and deployment wiring prepared.
- [x] Runtime login roles created and assigned capability roles.
- [x] Service-specific Secret Manager values created and IAM validated.
- [x] Runtime role attributes and memberships verified.
- [x] Consumer compatibility validated in GCP after runtime secret cutover.
- [x] Backup retention/storage/deletion policy approved.
- [x] Restore rehearsal completed.
- [ ] Consumer compatibility validated.
- [ ] Sensitive artifacts deleted at the approved closure point.

## 2. Slices

### Slice 1 — Read-only provider and database inventory

Collect project, branch, database, retention, role, membership, grant, ownership,
default-privilege, RLS, and materialized-view metadata. Do not export business rows
or credentials.

**Exit criteria:** sanitized target context and privilege inventory are available.

### Slice 2 — Credential decision

Determine whether any credential was exposed. If rotation/revocation is required,
define consumers, replacement order, rollback, and owner approval before mutation.

**Exit criteria:** credential decision and consumer impact are approved.

### Slice 3 — Runtime role matrix

The role matrix must reflect the code-backed ownership split: `pf-rates` writes only
`RAT_*`; `pf-payroll` writes only `PAY_*`; `pf-payroll` consumes rates through HTTP,
not direct SQL. Validate sequence `USAGE`/`SELECT`/`UPDATE` against real insert paths;
the current runtime role lacks sequence `USAGE`, so do not copy its grants blindly.

**Exit criteria:** role matrix is approved, service write paths are mapped, and no
role creation or grant mutation has occurred without explicit authorization.

### Slice 4 — Backup and restore rehearsal

Create a restricted backup only after approval. Record metadata and checksum, restore
into an ephemeral compatible database, run schema/invariant assertions, and record the
cleanup deadline. Never place the dump in Git or shared artifacts.

**Exit criteria:** restore passes and retention/deletion ownership is explicit.

### Slice 5 — Controlled mutations

Apply only approved role, credential, retention, or provider changes. Prefer a
transaction, temporary branch, or reversible provider operation. Validate both
services after each change.

**Exit criteria:** mutations are complete, idempotent, and rollback is documented.

### Slice 6 — Close

Update the investigation, register, and index with sanitized results. Set the
lifecycle status to `validated`, `released`, `blocked`, or `closed` according to
evidence. Record any remaining follow-up as a separate register entry.

## 3. Validation checklist

- `neonctl` project/branch metadata validated;
- SQL uses `sslmode=require`, temporary `pgpass`, read-only transaction, and timeout;
- no credentials or raw business data in output;
- role grants and default privileges reviewed;
- restore assertions pass;
- backup checksum and deletion evidence recorded;
- `pf-rates` and `pf-payroll` connection checks pass;
- rollback path is explicit before production mutation.

## 4. Change log

| Date | Status | Change | Evidence |
| --- | --- | --- | --- |
| 2026-10-11 | approved | Owner approved option 2: local-only restricted dump under `pf-db/secrets/`, mode `600`, seven-day retention from dump creation, and manual deletion with evidence. | Dump/restore assertions passed; deletion remains pending until the rollback window expires. |

## 5. Release record

- Commits: pending
- Workflow runs: completed for pf-rates/pf-payroll consumer cutover
- Owner approval: recorded
- Provider evidence: collected
- Role matrix: verified
- Restore rehearsal: passed
- Cleanup/deletion evidence: pending seven-day retention window
