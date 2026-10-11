# Brief: Neon credential and backup hardening

Date: 2026-10-10
Status: designed
Level: L
Scope: Shared Neon credential, runtime-role, backup/restore, and sensitive-artifact hardening.
Related artifacts: [investigation](../investigations/neon-credential-and-backup-hardening.md) · [register](../../../docs/proposals/ECOSYSTEM-IMPROVEMENT-REGISTER.md)
Approved: 2026-10-11 owner approval recorded in IMP-002 change log
Superseded-by: none

## Objective

Establish a secure and repeatable operating model for the shared Neon database:
least-privilege runtime roles, controlled credentials, verified backup/restore
capability, bounded retention, and safe handling of sensitive database artifacts.

## Non-objectives

- Implementing the `pf-svc-income` rename.
- Changing payroll/rates application behavior.
- Performing credential rotation or production mutations before authorization.
- Creating a generic income ledger or changing the schema domain model.
- Storing dumps, connection strings, or production data in Git.

## Affected repositories and ownership

| Responsibility | Owner |
| --- | --- |
| Schema, migrations, restore compatibility | `pf-db` |
| Payroll database consumption | `pf-payroll` |
| Rates database consumption | `pf-rates` |
| Ecosystem coordination and release gates | `pf-base` |

## Required outcomes

- Runtime roles are least-privilege and separated by service where feasible.
- Credential exposure status is known; exposed credentials are rotated or revoked.
- Backup/PITR/snapshot retention is documented and sufficient for approved rollback needs.
- A restricted logical backup can be restored and validated without entering Git.
- Sensitive dumps and temporary credentials are deleted at the approved closure point.
- Schema, row-count, ownership, and materialized-view invariants are validated after restore.

## Constraints

- Financial data and credentials are sensitive.
- Use local execution scripts when Neon access is blocked from the agent environment.
- Read-only evidence is the default; mutations require explicit authorization.
- Cloud cost remains a priority; prefer existing provider retention and on-demand tooling
  before adding paid infrastructure.

## Questions for recommendation

1. Which runtime roles and grants are required by each service?
2. Which Neon retention controls are active, and what gap remains for rollback?
3. What backup format, storage location, encryption, retention, and deletion process is acceptable?
4. Which restore assertions are sufficient to prove consumer compatibility?
5. Is provider-native backup enough, or is a restricted logical dump required for the migration window?
