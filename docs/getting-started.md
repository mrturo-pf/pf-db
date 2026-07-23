# Getting Started

Quick installation and setup guide for pf-db local development.

## Overview

pf-db manages PostgreSQL schema and migrations for the PF (Personal Finances) ecosystem. It contains:
- DDL (Data Definition Language) for 17 tables
- Alembic migrations (version control for schema changes)
- Seed data (base, test, and production-realistic fixtures)

**This repository has no application code** - it is infrastructure-only.

## Prerequisites

- **Python 3.12+** with `uv` or `pip`
- **Docker Desktop** (for PostgreSQL container)
- **Git** (for cloning the repository)

## Step 1: Clone the repository

```bash
git clone <repository-url> pf-db
cd pf-db
```

## Step 2: Install dependencies

```bash
make install
```

This will:
- Create a virtual environment in `.venv/`
- Install Alembic and other dependencies from `pyproject.toml`
- Configure git hooks (pre-commit)

## Step 3: Configure environment

Generate `.env` with default local values:

```bash
make env-write
```

This creates `.env` from `.env.example`:

```bash
DATABASE_URL=postgresql+asyncpg://pf_db:pf_db@localhost:5432/pf_db
PF_DB_PORT=5432
```

You can edit `.env` to change the port or credentials if needed.

## Step 4: Start the database

Full bootstrap (start postgres + apply schema + load base seed):

```bash
make local-up
```

This will:
1. Start a PostgreSQL 16 container on `localhost:5432`
2. Apply the schema from `db/01_schema.sql` (idempotent DDL)
3. Load base seed data from `db/02_seed_base.sql` (currencies, institutions, caps, brackets, concepts)

**Alternative commands:**

```bash
# Include test fixtures (plans, insurance providers)
make local-up-test

# Use Alembic migrations instead of schema.sql (CI-equivalent)
make local-up-real
```

## Step 5: Verify installation

### Option A: psql (Terminal)

Connect to the database:

```bash
docker exec -it pf-db-postgres psql -U pf_db -d pf_db
```

Run queries:

```sql
-- List all tables
\dt

-- Count rows in currencies
SELECT COUNT(*) FROM currencies;

-- Show sample exchange rates
SELECT * FROM exchange_rates ORDER BY rate_date DESC LIMIT 5;
```

Type `\q` to exit.

### Option B: Adminer (Browser)

Start the Adminer web UI:

```bash
make adminer-up
```

Open your browser and navigate to:

```
http://localhost:8081
```

Login:
- System: `PostgreSQL`
- Server: `pf-db-postgres`
- Username: `pf_db`
- Password: `pf_db`
- Database: `pf_db`

Browse tables, run queries, and inspect data.

## Step 6: Run migrations

If you started with `make local-up` (uses `schema.sql`), you can apply migrations:

```bash
make migrate
```

This runs `alembic upgrade head`, applying all pending migrations.

**Check migration status:**

```bash
make migration-check
```

This verifies that all migration files have corresponding DB versions.

## Next steps

- [Development Guide](development.md) - Make commands, adding migrations
- [Migrations Guide](migrations.md) - Creating migrations, invariants, best practices
- [Tables Reference](tables.md) - 17 tables, ownership, connection string
- [CI Guide](ci.md) - Pipeline validation

## Common workflows

### Start database with test fixtures

```bash
make local-up-test
```

This loads base seed + test fixtures (pension/health plans, insurance providers/plans).

### Reset database (destroy all data)

```bash
make db-reset
```

**Warning:** This destroys the Docker volume. All data will be lost.

### Stop database

```bash
make local-down
```

This stops and removes the postgres and adminer containers.

### Restart database

```bash
# Restart with base seed
make local-restart

# Restart with test fixtures
make local-restart-test

# Restart using Alembic migrations
make local-restart-real
```

## Troubleshooting

### `make local-up` fails: "port 5432 already in use"

**Cause:** Another PostgreSQL instance is running on port 5432.

**Solution:**

```bash
# Option 1: Stop the other instance
# (if it's another Docker container)
docker ps
docker stop <container-id>

# Option 2: Change the port in .env
echo "PF_DB_PORT=5433" >> .env
make local-down
make local-up
```

### `make install` fails

**Error:** `uv not found` or `pip install fails`

**Solution:**

```bash
# Option 1: Install uv
curl -LsSf https://astral.sh/uv/install.sh | sh

# Option 2: Use pip directly
python -m venv .venv
source .venv/bin/activate
pip install -e .
```

### `make migrate` fails: "could not connect to server"

**Cause:** PostgreSQL container is not running.

**Solution:**

```bash
# Check if container is running
docker ps | grep pf-db-postgres

# If not running, start it
make db-up

# Then retry migration
make migrate
```

### Adminer shows "Invalid credentials"

**Cause:** Incorrect username/password or database name.

**Solution:**

Check the credentials in `.env`:

```bash
cat .env | grep DATABASE_URL
```

Default credentials:
- Username: `pf_db`
- Password: `pf_db`
- Database: `pf_db`

## Consuming microservices

Once pf-db is running, you can start the consuming microservices:

**pf-rates:**
```bash
cd ../pf-rates
make local-up
```

**pf-payroll:**
```bash
cd ../pf-payroll
make local-up
```

Both services verify that pf-db is running before starting.

## See also

- [pf-rates README](../pf-rates/README.md) - Financial rates microservice
- [pf-payroll README](../pf-payroll/README.md) - Payroll microservice
- [Development Guide](development.md) - Complete development workflow
- [Tables Reference](tables.md) - Schema documentation
