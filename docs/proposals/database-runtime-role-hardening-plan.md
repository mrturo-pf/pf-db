# Plan: Database runtime role hardening

Date: 2026-10-11
Status: superseded
Level: L
Scope: Implement approved least-privilege runtime roles and explicit grants for `pf-rates` and `pf-payroll`.
Related artifacts: [brief](database-runtime-role-hardening-brief.md) · [recommendation](database-runtime-role-hardening-recommendation.md) · [investigation](../investigations/database-runtime-role-hardening.md)
Approved: Pending explicit owner approval
Superseded-by: `neon-credential-and-backup-hardening` (IMP-002)

## 1. Gates

- [x] IMP-003 promoted to formal Level L artifacts.
- [ ] Code-backed table/sequence/view matrix approved.
- [ ] Migration and backup identity boundaries approved.
- [ ] Isolated upgrade/downgrade privilege assertions pass.
- [ ] Service success/denial tests pass.
- [ ] Production mutation authorized.
- [ ] Consumer cutover validated.
- [ ] Legacy grants/ownership cleanup validated.
- [ ] Closure evidence recorded.

## 2. Slices

### Slice 1 — Access-path inventory

Map current service repositories, models, repositories, insert paths, sequences,
views, migration metadata, and direct/shared reads. Produce a sanitized matrix.

### Slice 2 — Isolated privilege assertions

Create synthetic compatible database assertions for role attributes, grants,
default privileges, ownership, success paths, and denied cross-domain/DDL paths.
Validate upgrade and downgrade boundaries.

### Slice 3 — Role/grant preparation

Create or reconcile domain runtime, migrator, backup, and schema-owner roles
idempotently. Apply exact grants only after approval. Preserve rollback snapshots
without exporting credentials or business rows.

### Slice 4 — Consumer cutover

Switch service credentials/configuration in approved order. Validate both services,
migrations, sequences, materialized-view reads, and denied operations.

### Slice 5 — Legacy cleanup

Remove obsolete runtime grants and ownership only after consumer compatibility is
proven. Treat provider-managed system roles separately and record residual risk.

### Slice 6 — Close

Update investigation, recommendation, plan, register, index, and affected service
AGENTS/docs with sanitized evidence, commits, runs, and remaining follow-ups.

## 3. Expected repositories

| Repository | Responsibility |
| --- | --- |
| `pf-db` | roles, grants, ownership, defaults, migration/backup identity and assertions |
| `pf-rates` | code-backed RAT access paths and consumer validation |
| `pf-payroll` | code-backed PAY access paths and consumer validation |
| `pf-base` | register/index and cross-repository coordination |

## 4. Validation checklist

- [ ] exact sequence mapping reviewed;
- [ ] effective grants and default privileges asserted;
- [ ] denied operations tested;
- [ ] migration/backup paths tested;
- [ ] both consumers pass success and rollback checks;
- [ ] no sensitive values in artifacts;
- [ ] CI/release evidence recorded.

## 5. Change log

| Date | Status | Change | Evidence |
| --- | --- | --- | --- |
| 2026-10-11 | investigating | IMP-003 promoted to formal investigation, brief, recommendation, and plan. No database mutation performed. | Existing IMP-002 evidence and code ownership mapping |

## 6. Closure

IMP-003 is superseded by IMP-002. Its implementation slices are retained as
historical planning context only; no duplicate database mutation is authorized.
