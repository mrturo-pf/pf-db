# Plan: Database identifier length policy

Date: 2026-10-11
Status: validated
Level: M
Scope: Define and activate the `pf-db` identifier length and naming policy.
Related artifacts: [brief](database-identifier-length-policy-brief.md) · [recommendation](database-identifier-length-policy-recommendation.md) · [investigation](../investigations/database-identifier-length-policy.md)
Approved: 2026-10-11 by owner (conversation)
Superseded-by: none

## 1. Gates

- [x] Investigation and source evidence recorded.
- [x] Brief and recommendation prepared.
- [x] Owner approves the policy.
- [x] Existing identifiers inventoried and classified.
- [x] Validator location and CI gate approved.
- [x] Current DDL and Alembic identifier inventory validated.
- [x] `pf-svc-income` proposed names checked against the policy.
- [x] Documentation and validator implementation completed.
- [x] Migration compatibility scope clarified: physical `PAY_*` → `INC_*` migration and consumer compatibility belong to `pf-svc-income-renaming`, not IMP-008.
- [ ] Index/register release evidence recorded.

## 2. Slices

### Slice 1 — Inventory

Inventory current table, materialized-view, sequence, index, constraint, schema,
and migration identifiers. Calculate UTF-8 byte lengths and record exceptions.

### Slice 2 — Policy approval

Resolve 14 versus 30 characters, ASCII/case rules, auxiliary-object limits,
exception process, and validator location.

### Slice 3 — Validator and documentation

Implement the smallest deterministic validator and update `AGENTS.md`,
`docs/tables.md`, and migration guidance. Do not rename existing objects in this
slice.

### Slice 4 — Compatibility

Validate proposed names against the physical schema migration, Alembic upgrade/
downgrade, fresh bootstrap, and consuming service mappings.

### Slice 5 — Close

Set lifecycle status, record evidence, update register/index, and create a separate
migration proposal if physical renames remain necessary.

## 3. Validation checklist

- [x] PostgreSQL 63-byte ceiling documented;
- [x] business-name convention approved;
- [x] non-ASCII behavior tested;
- [x] auxiliary names checked for collisions/truncation;
- [x] current inventory classified;
- [x] proposed `INC_*` names validated;
- [x] no production mutation performed by policy work.

## 4. Change log

| Date | Status | Change | Evidence |
| --- | --- | --- | --- |
| 2026-10-11 | in progress | Implemented the initial DDL identifier validator and added `make identifier-check`/`make check` integration. Existing base schema validates with 36 identifiers. | `make identifier-check` passed |
| 2026-10-11 | in progress | Validated versioned `db/*.sql` and `alembic/versions/*.py` inventory, proposed `INC_*` names, and auxiliary names. `make check` passed. Migration upgrade/downgrade compatibility remains pending. | Validator output and `make check` |
| 2026-10-11 | validated | Policy and validator implementation validated locally; release evidence remains pending commit/push and CI. Physical rename migration remains delegated to `pf-svc-income-renaming`. | Local validator, inventory, proposed-name checks, and lint |

## 5. Release record

- Commits: pending
- Workflow runs: pending
- Owner approval: recorded
- Validator/CI evidence: local validator and lint passed; full local check had one external/network-dependent test failure
- Physical rename migration: delegated to `pf-svc-income-renaming`
