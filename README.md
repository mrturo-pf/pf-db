# pf-db

PostgreSQL schema and Alembic migrations for the PF (Personal Finances) ecosystem microservices.

## Overview

`pf-db` is the single source of truth for all PostgreSQL database objects shared across
the PF ecosystem microservices. It manages DDL, migrations, and seeds, with no application code.

```
pf-service-a ──┐
pf-service-b ──┼── PostgreSQL (pf-db) ◄── Alembic migrations (this repo)
pf-service-n ──┘
```

## Contribution workflow

Create a dedicated branch, run the documented validation, and open a pull request
targeting `main`. The protected `main` branch blocks direct pushes, force-pushes,
and deletion. A merge to `main` is followed by the repository's controlled
production migration process.


See [`docs/getting-started.md`](docs/getting-started.md) for installation, setup, and first run.

## Documentation

| Document | Purpose |
| --- | --- |
| [`docs/getting-started.md`](docs/getting-started.md) | Installation, setup, basic validation |
| [`docs/development.md`](docs/development.md) | Make commands, database workflows, troubleshooting |
| [`docs/migrations.md`](docs/migrations.md) | Creating migrations, patterns, invariants, best practices |
| [`docs/tables.md`](docs/tables.md) | 20 tables and one materialized view reference, ownership, relationships, ERD |
| [`docs/ci.md`](docs/ci.md) | CI pipeline, approval gates, production workflow |
| [`AGENTS.md`](AGENTS.md) | AI agent reference: language policy, code style, design principles |