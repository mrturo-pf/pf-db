# Plan: Neon credential and backup hardening

Date: 2026-10-10
Status: closed
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
- [x] Consumer compatibility validated.
- [x] Sensitive artifacts deleted at the approved closure point; `neon.env` remains under separate credential review.
- [x] Role/ownership cleanup executed and consumer compatibility revalidated.
- [x] Administrative `neon_service` cleanup assessed; provider-managed system role is unmodifiable and recorded as accepted residual risk.

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
| 2026-10-11 | in progress | Owner removed the restricted dump immediately, overriding the prior seven-day retention window. Deletion was verified; `neon.env` remains under separate credential review. | Filesystem absence check; no dump contents recorded |
| 2026-10-11 | validated | Owner removed the restricted dump immediately, overriding the prior seven-day retention window. Deletion was verified; `neon.env` remains under separate credential review. | Filesystem absence check; no dump contents recorded |
| 2026-10-11 | in progress | Prepared an interactive Neon role/ownership cleanup entry point: revoke `neon_service` superuser membership, set `NOLOGIN`, create `pf_schema_owner`, and reassign ownership without touching data/RLS. | Local syntax and ignore checks passed; mutation pending |
| 2026-10-11 | in progress | Ownership cleanup completed: `pf_schema_owner` created, 83 objects reassigned, temporary membership revoked before commit. `neon_service` administrative cleanup remains blocked by missing ADMIN OPTION. | Neon execution results for ownership cleanup |
| 2026-10-11 | blocked | Administrative cleanup cannot proceed with `neondb_owner`: no superuser or role with ADMIN OPTION over `neon_superuser`/`neon_service` is available. | Preflight result: `current_user=neondb_owner`, `is_superuser=false`, admin options false |

| 2026-10-11 | blocked | Administrative cleanup cannot proceed with `neondb_owner`: no superuser or role with ADMIN OPTION over `neon_superuser`/`neon_service` is available. | Preflight result: `current_user=neondb_owner`, `is_superuser=false`, admin options false |
| 2026-10-11 | validated | Neon confirmed `neon_service` is a provider-managed system role unmodifiable by the available user. Failed cleanup was rolled back and accepted as residual risk; it does not block closure. | Neon Console error evidence; no role state change |

## 5. Release record

- Commits: pending documentation closure
- Workflow runs: completed for pf-rates/pf-payroll consumer cutover
- Owner approval: recorded
- Provider evidence: collected
- Role matrix: verified
- Restore rehearsal: passed
- Cleanup/deletion evidence: restricted dump and neon.env removed; role residual risk accepted
- Closure: IMP-002 closed with provider-managed neon_service residual risk
