# Recommendation: Database identifier length policy

Date: 2026-10-11
Status: approved
Level: M
Scope: Policy for PostgreSQL identifier lengths and naming conventions owned by `pf-db`.
Related artifacts: [brief](database-identifier-length-policy-brief.md) · [investigation](../investigations/database-identifier-length-policy.md) · [register](../../../docs/proposals/ecosystem-improvement-register.md)
Approved: 2026-10-11 by owner (conversation)
Superseded-by: none

## 1. Recommendation

Adopt this policy for new and renamed `pf-db` objects:

- PostgreSQL's technical ceiling is **63 bytes** for every identifier;
- table and materialized-view business names use at most **30 ASCII characters**;
- names are uppercase, quoted when required by the existing schema convention, and
  use an explicit service/domain prefix;
- sequences derived from tables follow the table name and remain within 63 bytes;
- indexes, constraints, schemas, enums, and other auxiliary objects must remain
  below 63 bytes and use deterministic explicit names; migrations must not rely on
  automatic truncation;
- non-ASCII identifiers are rejected for new schema objects because byte length and
  tooling portability are less predictable;
- existing objects outside the policy require an explicit documented exception,
  not an opportunistic rename.

The proposed `INC_*` table/materialized-view names fit the 30-character convention.
This recommendation does not authorize the rename migration.

## 2. Rejected alternatives

- **Keep 14 characters forever:** rejected because it unnecessarily constrains the
  approved `INC_*` vocabulary and does not reflect the technical PostgreSQL limit.
- **Use the full 63 bytes for business names:** rejected because readability,
  generated names, and cross-tool compatibility degrade.
- **Rely on automatic truncation:** rejected because collisions and migration drift
  become implicit and difficult to audit.
- **Use JSON/ORM naming as the source of truth:** rejected; `pf-db` owns DDL and
  migrations, while consumers validate compatibility against it.

## 3. Validation and implementation

Add a small deterministic validator in `pf-db` development checks that:

1. rejects non-ASCII new identifiers;
2. checks UTF-8 byte length against the applicable limit;
3. enforces prefixes/case for table and materialized-view names;
4. rejects duplicate explicit auxiliary names within a schema;
5. runs against migration DDL/reference fixtures without connecting to production.

Document exceptions in `docs/tables.md` and migration files. Add upgrade,
downgrade, fresh-bootstrap, and consumer compatibility assertions for any migration
that introduces or renames identifiers.

## 4. Cost and operational impact

No infrastructure cost is expected. The change adds a small recurring maintenance
and CI validation cost and reduces future migration/debugging risk. This is cheaper
than discovering truncation collisions during a production schema rename.

## 5. Decision gate

Approval is required for the 30-character business-name convention, ASCII rule,
auxiliary-name policy, validator location, and exception process. No schema or
migration mutation is authorized by this recommendation alone.
