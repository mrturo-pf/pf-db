# PostgreSQL connection budget

Status: approved
Date: 2026-10-13
Owner: `pf-db`
Consumers: `pf-rates`, `pf-payroll`

## Decision

The PF ecosystem reserves an approved PostgreSQL connection budget of **80
connections** for the two Cloud Run application services, the migration job,
operators, and operational headroom.

Application services must use explicit pool limits. The approved target is:

| Service | Cloud Run max instances | Pool upper bound per instance | Steady-state upper bound |
|---|---:|---:|---:|
| `pf-rates` | 2 | 5 | 10 |
| `pf-payroll` | 2 | 5 | 10 |

The pool upper bound is `pool_size + max_overflow`; the target configuration is
`pool_size=5` and `max_overflow=0`. Library defaults must not be used as an
implicit connection contract.

## Rollout reservation

Capacity approval must account for two revisions during a rollout:

```text
application connections:
  2 services × 2 revisions × 2 instances × 5 connections = 40

migration job reservation: 5
operator reservation:      5
operational headroom:     20
--------------------------------
approved total:            70 used / 80 budget
remaining margin:          10
```

The overlap factor of `2` is the approved conservative rollout assumption. A
release that needs more than two simultaneously connected revisions requires a
new capacity decision before deployment.

## Runtime requirements

Consuming services must:

- configure `pool_size=5` and `max_overflow=0` explicitly;
- preserve `pool_pre_ping=True`;
- use `pool_recycle=300` unless a later evidence-based decision changes it;
- avoid creating additional unbounded database engines or pools;
- include the calculated upper bound in release evidence.

The migration job must remain on-demand and reserve no more than five concurrent
database connections under its approved configuration. Operator activity must
preserve the five-connection operator reservation.

## Release gate

Before a Cloud Run release, calculate:

```text
fleet_connections =
  services × revisions × max_instances × pool_upper_bound
  + migration_reservation
  + operator_reservation
  + headroom
```

The release is allowed only when:

```text
fleet_connections <= 80
```

If max instances, pool limits, revision overlap, migration concurrency, or
headroom change, this decision must be reviewed by `pf-db` before deployment.

## Provider evidence

A Neon inspection supplied by the `pf-db` owners on 2026-10-13 reported:

```text
max_connections = 901
active_connections = 12
```

The active-session value came from:

```sql
SELECT count(*) AS active_connections FROM pg_stat_activity;
```

This snapshot represents approximately `1.33%` of the configured provider ceiling
and `12` of the approved PF reservation of `80`. It leaves `68` connections of
the PF reservation unused at the observation time. A single snapshot is not a
traffic baseline and must not be used to increase service pool or Cloud Run
limits without trend evidence.


This document approves the connection-budget model; it does not itself change
Cloud Run settings or service code. Consumers must adopt the explicit pool
configuration and provide validation evidence through `IMP-007` before shared
workflow defaults or capacity limits are changed.
