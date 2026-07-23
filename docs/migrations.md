# Migrations Guide

Creating, testing, and managing Alembic migrations for pf-db.

## Overview

pf-db uses **Alembic** for database migrations. Migrations are the authoritative source of truth for production schema changes.

**Key facts:**
- All migrations are **hand-written SQL** (no autogenerate)
- Migrations always run **before traffic** (via Cloud Run Job)
- Every migration must have an `upgrade()` and `downgrade()` function
- All migrations must be **idempotent** (safe to run multiple times)

## Migration file structure

Migration files live in `alembic/versions/`:

```
alembic/
├── env.py                     # async runner; reads DATABASE_URL from .env
└── versions/
    ├── 0001_rates_schema.py   # currencies, exchange_rates, economic_indices, income_tax_brackets
    └── 0002_payroll_schema.py # pension/health/contribution tables + employers + payroll core + mv
```

### File naming convention

```
NNNN_description.py
```

- `NNNN`: Sequential revision number (e.g., `0001`, `0002`, `0003`)
- `description`: Brief description in snake_case (e.g., `add_currencies_table`, `payroll_schema`)

### File template

```python
"""Brief description of the change

Revision ID: NNNN
Revises: NNNN-1
Create Date: YYYY-MM-DD
"""
from alembic import op

# Revision identifiers
revision = 'NNNN'
down_revision = 'NNNN-1'  # or None for first migration

def upgrade() -> None:
    """Apply the migration."""
    op.execute("""
        CREATE TABLE example (
            id SERIAL PRIMARY KEY,
            name VARCHAR(100) NOT NULL
        );
    """)

def downgrade() -> None:
    """Rollback the migration."""
    op.execute("""
        DROP TABLE example;
    """)
```

## Creating a new migration

### Step 1: Determine the revision number

```bash
# List existing migrations
ls alembic/versions/

# Output:
# 0001_rates_schema.py
# 0002_payroll_schema.py

# Next revision: 0003
```

### Step 2: Create the migration file

Create `alembic/versions/0003_description.py`:

```python
"""Add example table

Revision ID: 0003
Revises: 0002
Create Date: 2024-01-15
"""
from alembic import op

revision = '0003'
down_revision = '0002'

def upgrade() -> None:
    op.execute("""
        CREATE TABLE example (
            id SERIAL PRIMARY KEY,
            name VARCHAR(100) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        
        CREATE INDEX idx_example_name ON example(name);
    """)

def downgrade() -> None:
    op.execute("""
        DROP INDEX idx_example_name;
        DROP TABLE example;
    ")
```

### Step 3: Update db/01_schema.sql

Add the corresponding DDL to `db/01_schema.sql` for local development reference:

```sql
-- Example table
CREATE TABLE IF NOT EXISTS example (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_example_name ON example(name);
```

**Important:** Use `CREATE ... IF NOT EXISTS` to make it idempotent.

### Step 4: Test the migration locally

```bash
# Start with migrations
make local-up-real

# Or if database is already running
make migrate

# Verify migration applied
docker exec -it pf-db-postgres psql -U pf_db -d pf_db -c "SELECT * FROM alembic_version;"
# Should show: 0003

# Test rollback
make rollback

# Verify rolled back
docker exec -it pf-db-postgres psql -U pf_db -d pf_db -c "SELECT * FROM alembic_version;"
# Should show: 0002

# Re-apply
make migrate
```

### Step 5: Run quality checks

```bash
make check
```

This runs:
- `make lint` - ensures migration file follows code style
- `make migration-check` - ensures all migration files have corresponding DB versions

### Step 6: Commit

```bash
git add alembic/versions/0003_description.py db/01_schema.sql
git commit -m "feat: add example table for feature X"
```

## Migration patterns

### Adding a table

```python
def upgrade() -> None:
    op.execute("""
        CREATE TABLE new_table (
            id SERIAL PRIMARY KEY,
            name VARCHAR(100) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    """)

def downgrade() -> None:
    op.execute("DROP TABLE new_table;")
```

### Adding a column

```python
def upgrade() -> None:
    op.execute("""
        ALTER TABLE existing_table 
        ADD COLUMN new_column VARCHAR(50);
    """)

def downgrade() -> None:
    op.execute("""
        ALTER TABLE existing_table 
        DROP COLUMN new_column;
    """)
```

### Adding an index

```python
def upgrade() -> None:
    op.execute("""
        CREATE INDEX idx_table_column ON table_name(column_name);
    """)

def downgrade() -> None:
    op.execute("DROP INDEX idx_table_column;")
```

### Adding a foreign key

```python
def upgrade() -> None:
    op.execute("""
        ALTER TABLE child_table 
        ADD CONSTRAINT fk_parent 
        FOREIGN KEY (parent_id) REFERENCES parent_table(id);
    """)

def downgrade() -> None:
    op.execute("""
        ALTER TABLE child_table 
        DROP CONSTRAINT fk_parent;
    """)
```

### Renaming a column

```python
def upgrade() -> None:
    op.execute("""
        ALTER TABLE table_name 
        RENAME COLUMN old_name TO new_name;
    """)

def downgrade() -> None:
    op.execute("""
        ALTER TABLE table_name 
        RENAME COLUMN new_name TO old_name;
    """)
```

### Data migration

```python
def upgrade() -> None:
    # 1. Add new column
    op.execute("""
        ALTER TABLE users ADD COLUMN status VARCHAR(20);
    """)
    
    # 2. Migrate data
    op.execute("""
        UPDATE users SET status = 'active' WHERE is_active = true;
    """)
    op.execute("""
        UPDATE users SET status = 'inactive' WHERE is_active = false;
    """)
    
    # 3. Drop old column (optional, or in a separate migration)
    op.execute("""
        ALTER TABLE users DROP COLUMN is_active;
    """)

def downgrade() -> None:
    # Reverse: add old column, migrate data, drop new column
    op.execute("""
        ALTER TABLE users ADD COLUMN is_active BOOLEAN;
    """)
    op.execute("""
        UPDATE users SET is_active = true WHERE status = 'active';
    """)
    op.execute("""
        UPDATE users SET is_active = false WHERE status = 'inactive';
    """)
    op.execute("""
        ALTER TABLE users DROP COLUMN status;
    """)
```

## Invariants (never violate)

### 1. Migrations before traffic

Any Cloud Run deployment that consumes this DB must run `alembic upgrade head` before serving traffic. The Cloud Run Job pattern is the reference.

**Production workflow:**
```
1. pf-db Cloud Run Job: alembic upgrade head
2. pf-rates Cloud Run Service: starts receiving traffic
3. pf-payroll Cloud Run Service: starts receiving traffic
```

### 2. No application code

This repo has no `src/`, no FastAPI routes, no business logic. ORM models live in the consuming microservices (pf-rates, pf-payroll).

### 3. No autogenerate

`target_metadata = None` in `alembic/env.py`. Migrations are hand-written raw SQL. Never use `alembic revision --autogenerate`.

### 4. Idempotent seeds

All `INSERT` statements in `db/02_seed_base.sql` use `ON CONFLICT DO UPDATE` or `ON CONFLICT DO NOTHING`. Running seeds multiple times must be safe.

Example:

```sql
-- Idempotent insert
INSERT INTO currencies (code, name) 
VALUES ('USD', 'United States Dollar')
ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name;
```

### 5. No float columns

All monetary/rate columns use `NUMERIC`. Never `FLOAT`.

```sql
-- Correct
exchange_rate NUMERIC(12, 4)

-- Wrong
exchange_rate FLOAT
```

**Reason:** `FLOAT` has precision issues. Financial calculations require exact decimal arithmetic.

### 6. Schema-apply is local only

`db/01_schema.sql` is never applied in CI or production. Alembic is the production path.

**Local:** `make schema-apply` (fast, for development)  
**CI/Prod:** `alembic upgrade head` (authoritative)

### 7. Always provide downgrade()

Never leave `downgrade()` as `pass`. Every migration must be reversible.

```python
# Wrong
def downgrade() -> None:
    pass

# Correct
def downgrade() -> None:
    op.execute("DROP TABLE new_table;")
```

**Why:** Enables rollback in case of issues. Even if you "never" rollback, having the option is critical for production safety.

## Testing migrations

### Test upgrade

```bash
make local-up-real  # starts with all migrations applied
```

### Test upgrade + downgrade cycle

```bash
# Start with migrations
make local-up-real

# Get current revision
docker exec -it pf-db-postgres psql -U pf_db -d pf_db -c "SELECT * FROM alembic_version;"

# Rollback one migration
make rollback

# Verify data still consistent
docker exec -it pf-db-postgres psql -U pf_db -d pf_db -c "\dt"

# Re-apply
make migrate

# Verify migration check passes
make migration-check
```

### Test from scratch

```bash
# Destroy database
make db-reset

# Start with migrations
make local-up-real

# All migrations should apply cleanly
make migration-check
```

## Common mistakes

### Mistake 1: Non-idempotent DDL

```python
# Wrong (fails if run twice)
def upgrade() -> None:
    op.execute("CREATE TABLE example (...);")

# Correct (idempotent)
def upgrade() -> None:
    op.execute("CREATE TABLE IF NOT EXISTS example (...);")
```

### Mistake 2: Using application logic

```python
# Wrong (imports from pf-payroll)
from payroll.domain.payroll_period import PayrollPeriod

def upgrade() -> None:
    # Don't do this - migrations should be pure SQL
    pass
```

Migrations should contain **only SQL**. No imports from application code.

### Mistake 3: Forgetting to update schema.sql

```python
# alembic/versions/0003_add_column.py
def upgrade() -> None:
    op.execute("ALTER TABLE users ADD COLUMN status VARCHAR(20);")
```

**Don't forget:**
```sql
-- db/01_schema.sql
ALTER TABLE users ADD COLUMN IF NOT EXISTS status VARCHAR(20);
```

Both files must stay in sync.

### Mistake 4: Breaking changes without coordination

```python
# Wrong (breaks pf-payroll immediately)
def upgrade() -> None:
    op.execute("DROP COLUMN critical_field;")
```

**Correct approach (multi-step migration):**

**Migration 1:** Add new column, keep old one
```python
def upgrade() -> None:
    op.execute("ALTER TABLE users ADD COLUMN new_field VARCHAR(50);")
    op.execute("UPDATE users SET new_field = old_field;")
```

**Application change:** Update pf-payroll to use `new_field`

**Migration 2:** Drop old column (after application deployed)
```python
def upgrade() -> None:
    op.execute("ALTER TABLE users DROP COLUMN old_field;")
```

## CI pipeline

See [CI Guide](ci.md) for details on how migrations are validated in CI.

**Quick summary:**
1. PR runs `make check` (lint + migration-check)
2. Manual approval gate before migrations execute
3. Migrations apply via `alembic upgrade head`
4. `alembic check` verifies all migration files have corresponding DB versions

## Production deployment

Migrations are applied via **Cloud Run Job** before services start:

```yaml
# .github/workflows/deploy.yml (conceptual)
jobs:
  migrate:
    runs-on: ubuntu-latest
    steps:
      - name: Run migrations
        run: |
          gcloud run jobs execute pf-db-migrate \n            --region=us-central1 \n            --wait
  
  deploy-services:
    needs: migrate
    # ... deploy pf-rates and pf-payroll
```

The Cloud Run Job:
1. Pulls the pf-db image
2. Runs `alembic upgrade head`
3. Exits (job completes)
4. Services start receiving traffic

## Rollback strategy

If a migration causes issues in production:

**Option 1: Rollback via Alembic**
```bash
# SSH into Cloud Run Job container (or run locally against prod DB)
alembic downgrade -1
```

**Option 2: Deploy a new "fix-forward" migration**
```python
# alembic/versions/0004_fix_issue.py
def upgrade() -> None:
    # Fix the issue introduced by 0003
    op.execute("ALTER TABLE example DROP COLUMN problematic_field;")
```

**Best practice:** Prefer Option 2 (fix-forward) in production. Rollbacks can cause data loss.

## See also

- [Development Guide](development.md) - Make commands and workflows
- [Tables Reference](tables.md) - Schema documentation
- [CI Guide](ci.md) - Pipeline validation
- [Getting Started](getting-started.md) - Installation and setup