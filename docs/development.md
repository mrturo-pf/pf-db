# Development Guide

Local development workflow, commands, and contribution guidelines for pf-db.

## Prerequisites

1. **Python 3.12+** with `uv` or `pip`
2. **Docker Desktop** (for PostgreSQL container)
3. **Virtual environment** - created by `make install`

## Development commands

All commands assume you're in an activated virtualenv:

```bash
source .venv/bin/activate
```

Or prefix with the virtualenv path:

```bash
PATH=.venv/bin:$PATH make <target>
```

## Database commands

### Starting the database

| Command | Description |
|---|---|
| `make local-up` | **Full bootstrap:** start DB + apply schema + load base seed |
| `make local-up-test` | Same as above + test fixtures |
| `make local-up-real` | Bootstrap using Alembic migrations (CI-equivalent) |
| `make db-up` | Start postgres container (no schema or seed) |

**Recommendation:** Use `make local-up-test` for most development work.

### Managing the database

| Command | Description |
|---|---|
| `make local-down` | Tear down the full local stack (DB + Adminer) |
| `make local-restart` | Restart local stack with base seed |
| `make local-restart-test` | Restart local stack with test fixtures |
| `make local-restart-real` | Restart local stack using Alembic migrations |
| `make db-down` | Stop postgres container |
| `make db-reset` | **Destroy volume and restart** (destroys data) |

### Applying schema and seeds

| Command | Description |
|---|---|
| `make schema-apply` | Apply idempotent DDL via `docker exec` (local only) |
| `make seed-base` | Load base seed data |
| `make seed-test` | Load base + test fixtures |
| `make seed-real` | Load production-realistic data (runs seed-base first) |

**Note:** `schema-apply` is local-only. Production uses Alembic migrations.

### Adminer (web UI)

| Command | Description |
|---|---|
| `make adminer-up` | Start Adminer UI (starts DB first) |
| `make adminer-down` | Stop and remove the Adminer container |
| `make adminer-restart` | Restart Adminer without touching the DB |

Access Adminer at `http://localhost:8081`.

## Migration commands

| Command | Description |
|---|---|
| `make migrate` | `alembic upgrade head` (CI / Cloud Run) |
| `make rollback` | `alembic downgrade -1` |
| `make stamp` | Stamp existing DB at head without re-running migrations |
| `make migration-check` | Fail if there are pending unapplied migrations (CI gate) |

See [Migrations Guide](migrations.md) for detailed migration workflows.

## Quality checks

| Command | Description |
|---|---|
| `make lint` | Run ruff linter over `alembic/` |
| `make check` | Lint + migration-check |

## Project management

| Command | Description |
|---|---|
| `make  | Install Python dependencies into the active virtualenv |
| `make reinstall` | Wipe caches and reinstall all dependencies |
| `make env-write` | Write `.env` from `.env.example` (does not overwrite existing) |
| `make clean` | Remove build artifacts and caches |

## Git hooks

Installed automatically by `make install` via `git config core.hooksPath .githooks`:

| Hook | Runs | Bypass |
|---|---|---|
| `pre-commit` | lint | `git commit --no-verify` |

**Never bypass hooks without justification.** They enforce the same checks that run in CI.

## Common workflows

### Workflow 1: Local development with schema.sql

This is the fastest workflow for local development:

```bash
# 1. Start database with test fixtures
make local-up-test

# 2. Make changes to db/01_schema.sql or db/02_seed_base.sql

# 3. Restart to apply changes
make local-restart-test

# 4. Verify changes
make adminer-up
# Browse to http://localhost:8081
```

**Pros:**
- Fast: no need to create migrations during development
- Easy: just edit SQL files directly

**Cons:**
- Does not validate migrations
- Not representative of production (which uses Alembic)

### Workflow 2: Local development with Alembic migrations

This workflow mirrors CI/production:

```bash
# 1. Start database using migrations
make local-up-real

# 2. Create a new migration (see Migrations Guide)
# Edit alembic/versions/NNNN_description.py

# 3. Apply the new migration
make migrate

# 4. Test rollback
make rollback

# 5. Re-apply
make migrate

# 6. Verify
make migration-check
make check
```

**Pros:**
- Validates migrations work correctly
- Tests upgrade and downgrade paths
- Matches production behavior

**Cons:**
- Slower: requires creating migration files

### Workflow 3: Adding a new table

1. **Update `db/01_schema.sql`** (idempotent DDL for reference):
   ```sql
   CREATE TABLE IF NOT EXISTS new_table (
       id SERIAL PRIMARY KEY,
       name VARCHAR(100) NOT NULL
   );
   ```

2. **Create Alembic migration** in `alembic/versions/`:
   ```bash
   # Create file: alembic/versions/0003_add_new_table.py
   ```

   ```python
   """Add new_table
   
   Revision ID: 0003
   Revises: 0002
   Create Date: 2024-01-15
   """
   from alembic import op
   
   revision = '0003'
   down_revision = '0002'
   
   def upgrade() -> None:
       op.execute("""
           CREATE TABLE new_table (
               id SERIAL PRIMARY KEY,
               name VARCHAR(100) NOT NULL
           );
       """)
   
   def downgrade() -> None:
       op.execute("DROP TABLE new_table;")
   ```

3. **Test locally:**
   ```bash
   make local-up-real  # or make migrate if already running
   make migration-check
   ```

4. **Add seed data** (if needed) in `db/02_seed_base.sql`:
   ```sql
   INSERT INTO new_table (name) VALUES ('Example')
   ON CONFLICT DO NOTHING;
   ```

5. **Run quality checks:**
   ```bash
   make check
   ```

6. **Commit:**
   ```bash
   git add alembic/versions/0003_add_new_table.py db/01_schema.sql db/02_seed_base.sql
   git commit -m "feat: add new_table for feature X"
   ```

See [Migrations Guide](migrations.md) for more details.

## Database connection

### Connection string

Default (from `.env`):

```
postgresql+asyncpg://pf_db:pf_db@localhost:5432/pf_db
```

**Components:**
- Protocol: `postgresql+asyncpg`
- Username: `pf_db`
- Password: `pf_db`
- Host: `localhost`
- Port: `5432` (configurable via `PF_DB_PORT` in `.env`)
- Database: `pf_db`

### Connecting with psql

```bash
# Via docker exec (recommended)
docker exec -it pf-db-postgres psql -U pf_db -d pf_db

# Via psql client (if installed locally)
psql -h localhost -p 5432 -U pf_db -d pf_db
```

### Connecting with Python

```python
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

DATABASE_URL = "postgresql+asyncpg://pf_db:pf_db@localhost:5432/pf_db"

engine = create_async_engine(DATABASE_URL)
SessionLocal = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

async def example():
    async with SessionLocal() as session:
        result = await session.execute("SELECT COUNT(*) FROM currencies")
        print(result.scalar())
```

## Troubleshooting

### `make schema-apply` fails: "permission denied"

**Cause:** Docker container does not have permission to execute SQL.

**Solution:**

```bash
# Ensure container is running
docker ps | grep pf-db-postgres

# If not running
make db-up

# Retry
make schema-apply
```

### `make migrate` fails: "target database is newer than current revision"

**Cause:** Database is at a newer revision than the codebase.

**Solution:**

```bash
# Check current revision
docker exec -it pf-db-postgres psql -U pf_db -d pf_db -c "SELECT * FROM alembic_version;"

# Option 1: Stamp the database at the correct revision
make stamp

# Option 2: Reset database
make db-reset
make local-up-real
```

### Seed data fails to load: "duplicate key value violates unique constraint"

**Cause:** Seed SQL is not idempotent (missing `ON CONFLICT` clause).

**Solution:**

All `INSERT` statements in seed files must use:
- `ON CONFLICT DO UPDATE` for upserts
- `ON CONFLICT DO NOTHING` for inserts-only

Example:

```sql
-- Before (not idempotent)
INSERT INTO currencies (code, name) VALUES ('USD', 'United States Dollar');

-- After (idempotent)
INSERT INTO currencies (code, name) VALUES ('USD', 'United States Dollar')
ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name;
```

### `make adminer-up` fails: "port 8081 already in use"

**Cause:** Another service is using port 8081.

**Solution:**

```bash
# Find process using port 8081
lsof -i :8081

# Kill it
kill -9 <PID>

# Or edit docker-compose.yml to use a different port
# Change "8081:8080" to "8082:8080"
```

## Continuous Integration

All PRs run `make check` in CI. See [CI Guide](ci.md) for the full pipeline.

## See also

- [Getting Started](getting-started.md) - Installation and setup
- [Migrations Guide](migrations.md) - Creating and managing migrations
- [Tables Reference](tables.md) - Schema documentation
- [CI Guide](ci.md) - Pipeline validation
