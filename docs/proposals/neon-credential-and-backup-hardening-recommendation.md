# Recommendation: Neon credential and backup hardening

Date: 2026-10-10
Status: designed
Level: L
Scope: Shared Neon credential, runtime-role, backup/restore, and sensitive-artifact hardening.
Related artifacts: [brief](neon-credential-and-backup-hardening-brief.md) · [investigation](../investigations/neon-credential-and-backup-hardening.md) · [register](../../../docs/proposals/ECOSYSTEM-IMPROVEMENT-REGISTER.md)
Approved: 2026-10-11 owner approval recorded in IMP-002 change log
Superseded-by: none

## 1. Executive recommendation

Adopt a four-part hardening sequence:

1. collect sanitized Neon/provider and database privilege evidence;
2. rotate/revoke credentials only when exposure is confirmed or an owner authorizes it;
3. define per-service least-privilege roles and remove owner-level runtime access;
4. establish a restricted backup/restore process with tested deletion and retention.

Do not begin with a destructive migration or broad grant rewrite. Evidence must first
show the exact current state, and every mutation must have a rollback and validation
path.

## 2. Rejected alternatives

### Continue using owner-level runtime credentials

Rejected. Owner-level access can create, alter, or bypass controls beyond application
needs and makes a compromise materially worse.

### Rely only on local dumps with no restore rehearsal

Rejected. A dump that has never been restored is not reliable rollback evidence.

### Put a dump in Git or a shared artifact store without retention controls

Rejected. Payroll data and credentials require restricted storage, explicit retention,
access control, and deletion evidence.

### Rotate credentials before identifying consumers and dependencies

Rejected as an uncontrolled outage risk. Containment is urgent, but the replacement
must be configured atomically and validated.

## 3. Target control model

### Credentials

- use provider-supported secret storage or approved environment injection;
- never commit connection strings, passwords, API keys, or dumps;
- rotate exposed credentials and record only metadata and timestamps;
- use separate credentials/roles for `pf-rates`, `pf-payroll`, migrations, and operators
  when the provider and migration model support it.

### Runtime roles

- application roles receive only required schema/table/sequence privileges;
- runtime roles do not receive `CREATEROLE`, `CREATEDB`, `BYPASSRLS`, or owner-level
  privileges;
- migration/operator roles are separate from runtime identities;
- default privileges are reviewed so future objects do not silently broaden access.

### Backup and restore

- confirm provider-native retention/PITR/snapshots;
- create a restricted logical dump only when required by the migration or rollback plan;
- store it outside Git with encryption/access control and an explicit deletion deadline;
- restore into an ephemeral PostgreSQL-compatible environment;
- validate Alembic revision, object counts, constraints, ownership, materialized views,
  and representative schema invariants;
- delete the dump after the approved retention window and record the result.

### RLS decision

For the current service-isolation model, defer RLS and document it as not required
unless a future multi-tenant or row-owner access pattern appears. Roles and domain
ownership remain the active isolation controls. Reopen RLS as a separate design if
multiple tenants/users share rows or PostgreSQL is exposed directly to untrusted
consumers.

## 4.1 Evidence-based target role matrix

The current `neon_service` role can write across both `RAT_*` and `PAY_*` objects,
while the application domains have separate owners. The target design should split
runtime access by domain:

| Role | Intended consumer | Access target | Explicit exclusions |
| --- | --- | --- | --- |
| `pf_rates_runtime` | `pf-rates` | `public` USAGE; read/write only on `RAT_CURRENCY`, `RAT_EXCH_RATE`, `RAT_ECON_INDEX`, `RAT_TAX_BRCKT`, `RAT_EXPORT_JOB`; sequence privileges for `exchange_rates_id_seq`, `economic_indices_id_seq`, `income_tax_brackets_id_seq`, and `RAT_EXPORT_JOB_id_seq` where insert paths require them | All `PAY_*` objects; `alembic_version`; `CREATEROLE`; `CREATEDB`; `BYPASSRLS`; ownership |
| `pf_payroll_runtime` | `pf-payroll` | `public` USAGE; read/write only on the 15 `PAY_*` tables; sequence privileges for payroll/employer/reference/template sequences required by insert paths | All `RAT_*` objects; `alembic_version`; `CREATEROLE`; `CREATEDB`; `BYPASSRLS`; ownership |
| `pf_db_migrator` | Migration job/operator | Explicit DDL and migration privileges required by Alembic | Runtime use; permanent application secret injection |
| `pf_db_backup` | Backup/restore operator | Approved read/backup privileges and catalog access | Application writes; owner-level privileges unless a restore procedure requires them |

The capability roles and domain grants have now been applied idempotently and verified
read-only. Separate login roles and Secret Manager values were cut over successfully
to both GCP consumers. Existing broad runtime memberships and ownership remain
unchanged until backup/restore and rollback gates are complete.

## 4.2 Code-backed access mapping

The current service documentation and source models confirm:

- `pf-rates` owns and writes `RAT_CURRENCY`, `RAT_EXCH_RATE`, `RAT_ECON_INDEX`,
  `RAT_TAX_BRCKT`, and `RAT_EXPORT_JOB`;
- `pf-payroll` owns and writes the 15 `PAY_*` tables and uses `PAY_MV_SUMARY`;
- `pf-payroll` consumes rates through the `pf-rates` HTTP API and should not receive
  direct `RAT_*` database permissions;
- both runtime roles will need sequence privileges for insert paths, but exact
  sequence-to-table mapping must be tested against each repository's writes;
- migration and backup roles must remain separate from runtime application roles.

The target grants must be derived from this mapping and verified against integration
flows before any production grant change.

## 4.3 Current backup decision gate

Provider evidence shows only 6 hours of project history retention and no separate
snapshot/PITR/restore evidence in the collected metadata. Before the migration/cutover,
the owner must choose and approve one of these controls:

1. provider-native backup/PITR with documented retention and a successful restore
   assertion; or
2. a restricted logical dump created immediately before the change, stored locally in
   the ignored `pf-db/secrets/` path with mode `600`, checksum recorded separately,
   restored into an ephemeral compatible PostgreSQL instance, and deleted after the
   approved rollback window.

The owner initially approved option 2: store the restricted dump only under the
local ignored `pf-db/secrets/` path with mode `600`, retain it for seven days from
creation, and remove it manually with deletion evidence. After the restore
rehearsal, the owner explicitly removed that retention window and the dump was
deleted immediately with filesystem evidence. The local `neon.env` credential is a
separate artifact and remains subject to its own rotation/cleanup decision.


| ---: | --- | --- | --- |
| 1 | `pf-db` | Collect Neon and database privilege evidence | Sanitized evidence available |
| 2 | `pf-db` + service owners | Define runtime/migration/operator role matrix | Explicit approval |
| 3 | `pf-db` | Rehearse restricted backup and restore | Assertions pass |
| 4 | Credential owner | Rotate/revoke exposed credentials if required | Consumers validated |
| 5 | `pf-db` | Apply approved grant/retention changes | Rollback recorded |
| 6 | `pf-payroll`/`pf-rates` | Validate application connections and migrations | Service checks pass |

## 5. Validation matrix

| Area | Validation | Acceptance |
| --- | --- | --- |
| Provider | Project, branch, database, retention metadata | Target context is confirmed |
| Roles | Membership, grants, ownership, default privileges | Runtime access is least-privilege |
| Credentials | Exposure and rotation metadata | No known active compromised credential |
| Backup | Restricted dump metadata and checksum | Artifact is controlled and retrievable |
| Restore | Fresh compatible database and schema assertions | Alembic/schema invariants pass |
| Cleanup | Artifact and temporary credential review | Sensitive temporary material deleted |
| Consumers | `pf-rates` and `pf-payroll` connection checks | No unexpected service outage |

## 6. Cost and operational impact

- Prefer existing Neon retention/PITR and on-demand local tooling before adding services.
- A restricted logical dump adds temporary storage and operator work; retain only for
  the approved rollback window.
- Dedicated roles add IAM/database administration work but reduce incident blast radius.
- No always-on infrastructure is required by this recommendation.

## 7. Decision gate

Implementation requires explicit approval of the role matrix, credential strategy,
backup retention/storage, restore assertions, cleanup deadline, and owner for each
mutation. The recommendation does not authorize production changes by itself.
