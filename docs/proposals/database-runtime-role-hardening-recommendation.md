# Recommendation: Database runtime role hardening

Date: 2026-10-11
Status: superseded
Level: L
Scope: Least-privilege runtime roles for `pf-rates` and `pf-payroll` on the shared PostgreSQL database.
Related artifacts: [brief](database-runtime-role-hardening-brief.md) · [investigation](../investigations/database-runtime-role-hardening.md) · [register](../../../docs/proposals/ecosystem-improvement-register.md)
Approved: Pending explicit owner approval
Superseded-by: `neon-credential-and-backup-hardening` (IMP-002)

## 1. Executive recommendation

Adopt separate domain-scoped runtime roles:

- `pf_rates_runtime`: read/write only on approved `RAT_*` objects and required
  sequences;
- `pf_payroll_runtime`: read/write only on approved `PAY_*` objects and required
  sequences;
- `pf_db_migrator`: DDL and migration metadata access only for migration jobs;
- `pf_db_backup`: approved backup/catalog access only;
- `pf_schema_owner`: `NOLOGIN` owner for service-domain objects.

Runtime roles must not own objects or inherit provider superuser roles. Apply grants
idempotently, validate effective privileges, then cut over consumers before removing
legacy access.

## 2. Rejected alternatives

### Keep owner-level runtime credentials

Rejected because compromise permits DDL, ownership changes, role administration, and
cross-domain writes.

### One shared writable service role

Rejected because it violates domain ownership and increases blast radius.

### Grant all sequences or all public tables

Rejected because sequence and table permissions must follow actual insert/read paths.

### Introduce RLS as the primary fix

Rejected for this work. Current isolation is service/domain based; RLS is deferred
unless a future multi-tenant or row-owner requirement appears.

## 3. Target permission model

| Role | Allowed | Denied |
| --- | --- | --- |
| `pf_rates_runtime` | `public` USAGE; RAT tables; exact RAT sequences; approved views | PAY tables; `alembic_version`; DDL; ownership; role admin; backup |
| `pf_payroll_runtime` | `public` USAGE; PAY tables; exact PAY sequences; approved `PAY_MV_SUMARY` read | RAT tables; `alembic_version`; DDL; ownership; role admin; backup |
| `pf_db_migrator` | Alembic DDL/data migration operations through controlled job | Runtime use; service API secrets |
| `pf_db_backup` | Approved read/catalog/backup operations | Application writes; runtime use; deployment |
| `pf_schema_owner` | Object ownership; `NOLOGIN` | Login; runtime use; role administration |

The exact sequence list must be generated from current repository write paths and
validated in an isolated database. Do not copy grants from `neon_service`.

## 4. Default privileges and ownership

Create domain objects under `pf_schema_owner` or transfer ownership immediately
after creation. Default privileges must grant runtime access only to the matching
domain role. Future `RAT_*` objects must not grant PAY access, and future `PAY_*`
objects must not grant RAT access. `alembic_version` remains migration-owned.

## 5. Rollout and rollback

1. Freeze the code-backed matrix and identify owners.
2. Validate grants and denials in an isolated compatible database.
3. Create/reconcile runtime and migrator roles idempotently.
4. Grant exact table/sequence/view/default privileges.
5. Validate service connections, writes, reads, and denied operations.
6. Cut over consumers through approved secrets/configuration.
7. Observe both services and migration jobs.
8. Remove legacy runtime grants/ownership only after compatibility evidence.
9. Roll back by restoring previous secret bindings and grants if a consumer fails.

## 6. Validation matrix

- successful RAT writes and required sequence operations;
- successful PAY writes and required sequence operations;
- approved PAY materialized-view read;
- denied cross-domain SELECT/INSERT/UPDATE/DELETE;
- denied DDL, `CREATEROLE`, `CREATEDB`, `BYPASSRLS`, and ownership operations;
- migration upgrade/downgrade with `pf_db_migrator`;
- backup rehearsal with `pf_db_backup`;
- default-privilege assertion for newly created objects;
- consumer smoke and rollback checks.

## 7. Cost and operational impact

No new always-on infrastructure is required. Cost is limited to database
administration, validation, secret cutover, and ongoing grant review. The cheaper
alternative is to retain broad access, but it is rejected because of security and
incident blast-radius risk.

## 8. Decision

This recommendation is superseded by the implemented and evidenced role hardening
in IMP-002. Do not execute this recommendation independently. Future gaps in
sequence/default privileges, migration/backup identities, or denied-operation tests
must be split into separate scoped work.
