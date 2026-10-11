# Brief: Database runtime role hardening

Date: 2026-10-11
Status: superseded
Level: L
Scope: Least-privilege runtime roles for `pf-rates` and `pf-payroll` on the shared PostgreSQL database.
Related artifacts: [investigation](../investigations/database-runtime-role-hardening.md) · [register](../../../docs/proposals/ecosystem-improvement-register.md) · [index](../../../docs/proposals/index.md)
Approved: Pending explicit owner approval
Superseded-by: `neon-credential-and-backup-hardening` (IMP-002)

## Objective

Establish a repeatable database access contract in which each service uses a
dedicated runtime role with only its approved domain permissions, while migration,
backup, ownership, and operator identities remain separate.

## Non-objectives

- Changing HTTP/API behavior;
- introducing RLS in this work;
- changing application ORM models without a reviewed schema contract;
- revoking provider-managed system-role memberships that Neon does not expose;
- applying production grants before the recommendation and plan are approved.

## Required outcomes

- `pf-rates` can perform all approved `RAT_*` operations and required sequence use.
- `pf-payroll` can perform all approved `PAY_*` operations and required sequence use.
- Cross-domain writes, DDL, role administration, owner operations, and migration
  metadata access are denied to runtime roles.
- Materialized-view reads and sequence grants are explicitly tested.
- Default privileges prevent future objects from silently broadening runtime access.
- Migration and backup identities are separate and validated.
- Rollback and consumer compatibility evidence are recorded.

## Constraints

Use PostgreSQL `NUMERIC` and preserve schema ownership in `pf-db`. Use synthetic
fixtures and sanitized metadata. Runtime roles must not receive `CREATEROLE`,
`CREATEDB`, `BYPASSRLS`, owner, migration, or backup privileges. Provider-managed
role limitations discovered in IMP-002 remain documented residual risk.

## Acceptance criteria

1. A code-backed table/sequence access matrix is approved.
2. Effective grants and default privileges are asserted in an isolated compatible
   database before production mutation.
3. Both consumers pass success and denial tests with their dedicated runtime roles.
4. Migration and backup operations continue through separate identities.
5. Production rollout is reversible and ordered after schema/migration validation.
6. Legacy broad grants and ownership treatment have an explicit decision and owner.
7. No credentials, connection strings, or business rows enter Git or artifacts.

## Questions for recommendation

- Which exact sequences are required by each insert path?
- Should ownership transfer be included or tracked separately?
- Which role should own future service-domain objects?
- What is the minimum privilege required for `PAY_MV_SUMARY`?
- Which legacy grants can be removed without affecting migration/backup workflows?

## Requested recommendation format

Provide identity topology, table/sequence/view matrix, default-privilege policy,
transaction/rollback strategy, executable validation plan, rollout order, cost and
operational impact, rejected alternatives, and remaining approvals.
