# Investigation: Database runtime role hardening

Date: 2026-10-11
Status: superseded
Level: L
Scope: Replace broad owner-level application database access with service-specific least-privilege runtime roles and explicit grants.
Owner: `pf-db`
Related artifacts: [register](../../../docs/proposals/ecosystem-improvement-register.md) · [index](../../../docs/proposals/index.md) · [IMP-002 investigation](neon-credential-and-backup-hardening.md)
Superseded-by: `neon-credential-and-backup-hardening` (IMP-002)

## 1. Investigation question

What database roles, grants, ownership boundaries, sequence permissions, and default
privileges are required for `pf-rates` and `pf-payroll` to operate without owner,
superuser, migration, or cross-domain runtime access?

## 2. Scope

In scope: code-backed reads/writes, tables, sequences, materialized views, runtime
roles, migration/backup separation, default privileges, effective grants, cutover,
rollback, and consumer validation. Out of scope: application behavior, public API
changes, RLS redesign, and production mutation before approval.

## 3. Current evidence

IMP-002 established that the shared Neon database previously used owner-level and
broad inherited roles. The approved role design created capability roles and
service-specific runtime credentials, but broad legacy memberships/ownership were
intentionally retained during the backup/restore window. The runtime-role policy is
now documented in the root and service `AGENTS.md` files.

The target mapping is:

- `pf-rates` writes only `RAT_*` tables and required sequences;
- `pf-payroll` writes `PAY_*` tables and uses rates through HTTP;
- migration and backup identities are separate from runtime identities;
- runtime identities must not have `CREATEROLE`, `CREATEDB`, `BYPASSRLS`, owner,
  migration, backup, or unrelated-domain privileges.

## 4. Evidence required

Collect sanitized metadata and executable assertions only:

- service write paths mapped to tables and sequences;
- effective table/schema/sequence privileges for each runtime role;
- ownership and default privileges for future objects;
- materialized-view access and migration metadata boundaries;
- successful inserts/updates/reads through each service;
- denied cross-domain, DDL, role-management, and owner operations;
- rollback and compatibility results.

Never record credentials, connection strings, private keys, business rows, or raw
production payloads.

## 5. Open decisions

- [ ] Confirm the final sequence-to-table mapping from current service write paths.
- [ ] Confirm whether `PAY_MV_SUMARY` is read by runtime and which role owns it.
- [ ] Decide whether ownership transfer is part of IMP-003 or a separate migration.
- [ ] Define treatment of `neon_service` residual risk from IMP-002.
- [ ] Approve default privileges for future `RAT_*` and `PAY_*` objects.
- [ ] Name mutation and consumer-validation owners.

## 6. Conclusion

IMP-003 is superseded by IMP-002. The role matrix, capability roles, service-specific
runtime credentials, grants, membership verification, and GCP consumer cutover were
implemented and evidenced in IMP-002. No duplicate role/grant mutation should be
performed from this artifact. Any future sequence/default-privilege or legacy-role
follow-up must be registered as a separate scoped improvement.
