# Investigation: Database identifier length policy

Date: 2026-10-11
Status: closed
Level: M
Scope: Establish the `pf-db` policy for table and materialized-view identifier lengths and distinguish it from PostgreSQL's technical identifier limit.
Owner: `pf-db`
Related artifacts: [register](../../../docs/proposals/ecosystem-improvement-register.md) · [index](../../../docs/proposals/index.md) · [pf-svc-income recommendation](../../pf-payroll/docs/proposals/pf-svc-income-renaming-recommendation.md)
Superseded-by: none

## 1. Investigation question

Should `pf-db` retain its current 14-character convention, adopt the proposed
30-character table/materialized-view convention, or define a different policy
while preserving PostgreSQL's 63-byte technical ceiling?

## 2. Current evidence

- `pf-db/AGENTS.md` documents uppercase service-prefixed table names with a
  maximum of 14 characters.
- `db/01_schema.sql` repeats the 14-character convention and explains the quoted
  uppercase identifiers.
- The `pf-svc-income` recommendation proposes up to 30 ASCII characters for
  table/materialized-view names and separately requires explicit index/constraint
  names below PostgreSQL's 63-byte limit.
- PostgreSQL's identifier limit is 63 bytes, not characters; multibyte names can
  consume the limit sooner.
- Existing objects and migration names must remain compatible; this work should
  define policy before a physical rename migration relies on it.

## 3. Questions to resolve

- Is 30 an active ecosystem convention or only a rename proposal assumption?
- Does the limit apply only to tables/materialized views, or also sequences,
  indexes, constraints, schemas, enums, and migration identifiers?
- Must identifiers be ASCII uppercase with service prefixes?
- What validator should reject names before migration review?
- How should byte length be validated for non-ASCII identifiers?
- Which existing names violate the proposed policy, if any?

## 4. Evidence required

- inventory of current `pf-db` identifiers and byte lengths;
- migration/DDL references that depend on exact quoted names;
- consumer model/table mappings for renamed objects;
- validator and CI integration points;
- compatibility assertions for upgrade/downgrade and fresh bootstrap.

No production mutation or rename is authorized by this investigation.

## 6. Conclusion

IMP-008 is closed. The identifier policy, validator, documentation, current DDL/
Alembic inventory, and proposed `INC_*` names were completed and validated. The
physical `PAY_*` to `INC_*` migration, upgrade/downgrade execution, bootstrap, and
consumer compatibility remain part of `pf-svc-income-renaming`, not this policy
improvement. No schema or production mutation was performed by IMP-008.
