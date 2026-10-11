# Investigation: Neon credential and backup hardening

Date: 2026-10-10
Status: investigating
Level: L
Scope: Neon credential exposure, runtime-role privilege, backup/restore readiness, and sensitive dump handling for the shared PF database.
Owner: `pf-db`
Related artifacts: [ecosystem register](../../../docs/proposals/ECOSYSTEM-IMPROVEMENT-REGISTER.md) · [pf-db secrets guidance](../secrets/README.md)
Superseded-by: none

## 1. Investigation question

What controls are required to ensure that Neon credentials, database runtime roles,
backup/restore artifacts, and retention practices are safe enough for shared PF
service operations and future schema migrations?

This work is independent from the `pf-payroll` → `pf-svc-income` rename. The rename
may depend on backup/restore readiness, but it must not contain the reusable Neon
security and operations design.

## 2. Scope

### In scope

- Neon project/branch/database metadata and provider retention;
- runtime database roles and excessive privileges;
- credential exposure handling and rotation requirements;
- logical backup creation, restricted storage, restore rehearsal, and deletion;
- materialized-view/schema validation after restore;
- local tooling in `pf-db` for dump and restore;
- sanitized evidence and ownership decisions.

### Out of scope

- rotating a credential without explicit operational authorization;
- changing application code or ORM models;
- implementing the `pf-svc-income` schema rename;
- broad IAM cleanup unrelated to Neon/database access;
- copying production data into Git, chat, or shareable artifacts.

## 3. Current source-of-truth files

- `modules/pf-db/AGENTS.md` — schema ownership, migration, and data-safety rules;
- `modules/pf-db/scripts/export-neon-dump.sh` — local logical dump workflow;
- `modules/pf-db/scripts/restore-neon-dump.sh` — local restore workflow;
- `modules/pf-db/secrets/README.md` — local secret and dump handling;
- `modules/pf-db/docs/tables.md` — schema and ownership reference;
- `modules/pf-db/docs/migrations.md` — migration validation rules.

## 4. Evidence required

Collect only sanitized metadata:

- project, branch, database, region, status, and retention metadata;
- runtime role names, memberships, grants, ownership, and default privileges;
- whether RLS policies exist, without exporting business rows;
- backup/PITR/snapshot schedule and retention metadata;
- dump size, checksum, creation time, storage location, and deletion result;
- restore schema revision, object counts, and invariant results;
- provider and operational blockers.

Never collect or commit connection strings, passwords, API keys, raw dumps, RUTs,
salaries, health data, or unmasked production rows.

## 5. Initial known facts

- `pf-db` already provides gitignored Neon dump/restore scripts.
- `secrets/neon.env` and `secrets/neon_dump.sql` are explicitly treated as local-only
  sensitive artifacts.
- The shared PostgreSQL database is consumed by `pf-rates` and `pf-payroll`.
- A previous rename investigation identified possible owner-level runtime access and
  backup/retention gaps; those findings require read-only confirmation before design.
- Direct Neon/SQL access may require local execution outside corporate VPN/VPC
  restrictions.

## 5.1 Read-only evidence received (2026-10-10)

Sanitized metadata confirms:

- Neon project `personal-finances` is in `aws-us-east-1`, PostgreSQL 18, with free-tier
  autoscaling `0.25–2` CU and a zero-second suspend timeout;
- primary/default branch `production` is `ready` but not protected;
- the branch logical size is approximately 37 MB and project history retention is 6 hours;
- project settings allow public connections and do not restrict protected branches;
- the database connection uses role `neondb_owner`;
- `neondb_owner` inherits `neon_superuser`, which has broad read/write and operational
  memberships; `neon_service` also inherits `neon_superuser`;
- all 21 application tables, `alembic_version`, and `PAY_MV_SUMARY` are owned by
  `neondb_owner`;
- the physical inventory is 21 application tables plus `alembic_version` and one
  materialized view, requiring reconciliation with schema documentation;
- no business rows or credential values were collected.

This confirms a high-priority least-privilege and retention gap. It does not authorize
role changes, branch protection changes, credential rotation, backup export, or
production mutation.
## 5.2 Role and security evidence received (2026-10-10)

The second read-only execution confirms:

- `neondb_owner` and `neon_service` can log in and both have `CREATEROLE`,
  `CREATEDB`, and `BYPASSRLS` enabled;
- both roles inherit `neon_superuser`;
- `neon_superuser` inherits broad `pg_read_all_data` and `pg_write_all_data`
  capabilities plus operational memberships;
- all inspected tables, sequences, `PAY_MV_SUMARY`, and `alembic_version` are
  owned by `neondb_owner`;
- row-level security is disabled on all 22 inspected relations;
- default privileges from `cloud_admin` grant broad privileges to `neon_superuser`.

This confirms the runtime-role hardening finding as a concrete high-priority control
gap. No grants, roles, RLS policies, ownership, defaults, schema, data, or provider
settings were changed.

## 5.3 Effective privilege evidence received (2026-10-10)

The third read-only execution confirmed the available `information_schema` relations
and measured effective privileges with PostgreSQL `has_*_privilege` functions rather
than assuming portable privilege-view names.

Observed runtime access:

- `neon_service` has `USAGE` on `public` but not `CREATE`;
- `neon_service` can `SELECT`, `INSERT`, `UPDATE`, and `DELETE` across the inspected
  application tables, including both `PAY_*` and `RAT_*`, and `alembic_version`;
- `neon_service` has no `TRUNCATE`, `REFERENCES`, or `TRIGGER` privilege in the
  inspected table results;
- `neon_service` lacks sequence `USAGE` while retaining sequence `SELECT`/`UPDATE`
  in the inspected results;
- `neondb_owner` has full effective table privileges and is the owner role.

This is enough to validate the domain-scoped role matrix. A subsequent authorized
idempotent mutation created the capability roles and applied their grants; existing
broad memberships and ownership were intentionally unchanged. Credential, backup,
and restore decisions remain pending.

## 5.4 Provider retention evidence received (2026-10-11)

The sanitized provider metadata confirms:

- project `personal-finances` (`wild-hat-66882594`) is in `aws-us-east-1`, PostgreSQL 18,
  free-tier `free_v3`, with autoscaling `0.25–2` CU and a zero-second suspend timeout;
- primary/default branch `production` is `ready` but remains unprotected;
- branch logical size is `37,158,912` bytes (approximately 35.4 MiB);
- project history retention is `21,600` seconds (6 hours);
- the project has no IP allowlist, public connections are not blocked, and VPC connections
  are not blocked;
- this metadata does not provide evidence of a separately configured backup schedule,
  snapshot retention, or restore rehearsal;
- no provider or database mutation was performed.

The six-hour history window is not sufficient as the sole rollback control for a planned
schema migration. A restricted logical dump with an explicit storage, checksum, restore,
and deletion procedure is still required unless the owner approves a different provider
backup control with equivalent evidence.

## 5.5 Restricted dump and restore evidence received (2026-10-11)

A plain SQL logical dump was created using the existing `pf-db` workflow and restored
into the local PostgreSQL 16-compatible database. The dump is local-only, gitignored,
and was corrected to mode `600` after export.

Sanitized restore assertions passed:

- Alembic revision: `0016`;
- 22 user tables;
- 1 materialized view: `PAY_MV_SUMARY`;
- 18 public sequences;
- 0 invalid constraints;
- representative seed/object checks completed by the restore script.

The dump checksum and timestamp remain local evidence only. The rollback retention
window and deletion deadline still require owner approval; the dump must not be copied
to Git, chat, or shared artifacts.

## 6. Decisions required

- [x] Confirm Neon project, branch, and database metadata.
- [x] Confirm the current runtime role and ownership pattern.
- [x] Confirm the current role memberships, RLS state, and default-privilege pattern.
- [x] Confirm effective schema, table, and sequence privileges for the current roles.
- [x] Confirm the application credential exposure/rotation decision and create service-specific runtime credentials.
- [x] Define and apply the least-privilege runtime role matrix for `pf-rates` and `pf-payroll`.
- [x] Validate GCP consumer cutover with service-specific runtime credentials.
- [x] Confirm backup/PITR/snapshot retention and whether it covers the required rollback window.
- [x] Approve restricted logical dump storage, restore rehearsal, and deletion process.
- [ ] Decide whether RLS is required for the shared schema or whether service/database isolation is sufficient.
- [x] Define the owner and evidence required for closure.

## 7. Conclusion

Runtime credential separation and GCP consumer cutover are complete. The remaining
work is backup/PITR retention, a restricted restore rehearsal, cleanup ownership, and
an explicit decision on retiring broad legacy runtime memberships. Do not revoke
legacy memberships or change ownership until those gates and the rollback window are
complete.
