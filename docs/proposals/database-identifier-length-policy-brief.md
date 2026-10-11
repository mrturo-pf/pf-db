# Brief: Database identifier length policy

Date: 2026-10-11
Status: approved
Level: M
Scope: Policy for PostgreSQL identifier lengths and naming conventions owned by `pf-db`.
Related artifacts: [investigation](../investigations/database-identifier-length-policy.md) · [register](../../../docs/proposals/ecosystem-improvement-register.md) · [index](../../../docs/proposals/index.md)
Approved: 2026-10-11 by owner (conversation)
Superseded-by: none

## Objective

Define one enforceable identifier policy for `pf-db` before future schema migrations
rely on names longer than the current 14-character convention.

## Non-objectives

- Renaming existing tables or views;
- changing the `pf-svc-income` migration;
- changing application APIs or ORM models;
- relying on PostgreSQL's automatic identifier truncation;
- changing PostgreSQL's technical 63-byte limit.

## Required outcomes

- Table and materialized-view limits are explicit and measurable in bytes.
- Rules for sequences, indexes, constraints, schemas, and other objects are explicit.
- Case, quoting, service prefixes, separators, and ASCII requirements are clear.
- A validator and CI/check integration point are identified.
- Existing names and proposed `INC_*` names are classified as compliant or requiring
  an explicit exception.
- Migration upgrade/downgrade and consumer compatibility remain mandatory.

## Constraints

PostgreSQL identifiers are limited to 63 bytes. Financial/schema ownership remains
with `pf-db`. Names must be readable, deterministic, migration-safe, and compatible
with quoted uppercase conventions already used by the schema.

## Acceptance criteria

1. The approved policy states table/materialized-view and general identifier limits.
2. A machine-checkable validation rule exists or its implementation location is named.
3. The proposed `pf-svc-income` physical names are evaluated against the policy.
4. No migration proceeds based on an unapproved naming assumption.

## Questions for recommendation

- Adopt 14, 30, or another application convention?
- Should the policy use ASCII characters only?
- Should index/constraint names have a shorter readability limit?
- Which existing violations need exceptions or future cleanup?
- Where should validation run: SQL checks, migration tests, CI, or all three?
