# CI Guide

Continuous Integration pipeline for pf-db: validation, approval gates, and production migration workflow.

## Overview

Every PR to `main` runs against a fresh PostgreSQL 16 container to validate:
- Migrations apply cleanly
- All migration files have corresponding DB versions
- Code style is consistent

**No automatic deployment** - pf-db migrations are applied via **manual Cloud Run Job** before services deploy.

## Pipeline structure

### PR workflow

```
Pull Request → main
  └─> test job
        ├─> Checkout code
        ├─> Setup Python 3.12
        ├─> Install dependencies
        ├─> Start PostgreSQL 16 container
        ├─> Run migrations (alembic upgrade head)
        ├─> Run migration check (alembic check)
        └─> Run lint (ruff)
```

**Duration:** ~2 minutes

### Push to main workflow

```
Push → main
  └─> test job (same as PR)
        └─> Manual approval gate (production environment)
              └─> Notify (optional SMTP notification)
```

**Duration:** 2 minutes + manual approval time

## Test job

The `test` job validates migrations against a fresh PostgreSQL instance.

### Steps

1. **Checkout code**
   - Checks out pf-db repository

2. **Setup Python 3.12**
   - Uses `actions/setup-python@v4`

3. **Install dependencies**
   - Runs `pip install -e .`
   - Installs Alembic and all required packages

4. **Start PostgreSQL 16**
   - Uses `docker run` to start a PostgreSQL container
   - Exposes port 5432
   - Sets credentials: `pf_db` / `pf_db` / `pf_db`

5. **Run migrations**
   - Sets `DATABASE_URL` environment variable
   - Runs `alembic upgrade head`
   - **This is the critical validation step** - if migrations fail, PR is blocked

6. **Run migration check**
   - Runs `alembic check`
   - Ensures all migration files in `alembic/versions/` have corresponding DB versions
   - Catches orphaned or misnamed migration files

7. **Run lint**
   - Runs `ruff check alembic/`
   - Enforces code style on migration files

### Success criteria

All of the following must pass:
- PostgreSQL container starts successfully
- `alembic upgrade head` exits with code 0
- `alembic check` exits with code 0
- `ruff check` exits with code 0

If any step fails, the PR cannot be merged.

## Manual approval gate

On push to `main`, the pipeline pauses for **manual approval** via the `production` GitHub environment.

### Configuring approval

1. Go to **Settings** → **Environments** → **production**
2. Check **Required reviewers**
3. Add reviewers (users or teams who can approve)
4. Save

### Approving a deployment

1. Navigate to the **Actions** tab
2. Find the workflow run for the push to `main`
3. Click **Review deployments**
4. Select **production** environment
5. Click **Approve and deploy**

**Rejecting or cancelling does not send any notification** - it simply stops the pipeline.

## Migration application workflow

Once approved, migrations are applied to production via **Cloud Run Job**.

### Cloud Run Job setup

**Job name:** `pf-db-migrate`

**Configuration:**
```yaml
region: us-central1
image: us-central1-docker.pkg.dev/PROJECT/pf-db/app:latest
command: ["alembic", "upgrade", "head"]
env:
  DATABASE_URL: <secret-from-secret-manager>
```

### Execution

**Manual trigger:**
```bash
gcloud run jobs execute pf-db-migrate \
  --region=us-central1 \
  --wait
```

**From GitHub Actions (conceptual):**
```yaml
- name: Run migrations
  run: |
    gcloud run jobs execute pf-db-migrate \
      --region=us-central1 \
      --wait
```

### Verification

After the job completes:

```bash
# Check job logs
gcloud logging read "resource.type=cloud_run_job AND resource.labels.job_name=pf-db-migrate" \
  --limit=50 \
  --format=json

# Verify migration version
# (connect to production DB)
SELECT * FROM alembic_version;
```

## Common CI failures

### Failure: "relation already exists"

**Cause:** Migration DDL is not idempotent.

**Example:**
```python
def upgrade() -> None:
    op.execute("CREATE TABLE example (...);")  # Fails if table exists
```

**Solution:**
```python
def upgrade() -> None:
    op.execute("CREATE TABLE IF NOT EXISTS example (...);")
```

### Failure: "target database is newer than migration script"

**Cause:** Database has a revision that doesn't exist in the codebase.

**Solution:**
1. Check `alembic_version` table in the test database
2. Ensure all revisions in `alembic/versions/` are sequential
3. Reset the test database: `docker stop <container> && docker rm <container>`

### Failure: "migration check failed"

**Cause:** Migration file exists but has no corresponding DB version.

**Example:**
- `alembic/versions/0003_new_feature.py` exists
- But `down_revision = '0002'` and `revision = '0003'`
- And the database only has revision `0001`

**Solution:**
- Ensure migrations are applied: `alembic upgrade head`
- Or fix the `down_revision` chain

### Failure: "ruff check failed"

**Cause:** Migration file violates code style.

**Common issues:**
- Missing docstring
- Lines too long (> 120 chars)
- Trailing whitespace

**Solution:**
```bash
# Run ruff locally
ruff check alembic/

# Auto-fix
ruff check --fix alembic/
```

## Rollback strategy

If a migration fails in production:

### Option 1: Rollback via Alembic

```bash
# Trigger rollback job (if configured)
gcloud run jobs execute pf-db-rollback \
  --region=us-central1 \
  --wait

# Or connect directly and rollback
alembic downgrade -1
```

**Risks:**
- May cause data loss (if `downgrade()` drops columns/tables)
- Not all migrations are reversible

### Option 2: Fix-forward migration

Create a new migration that fixes the issue:

```python
# alembic/versions/0004_fix_issue.py
"""Fix issue introduced in 0003

Revision ID: 0004
Revises: 0003
"""
from alembic import op

revision = '0004'
down_revision = '0003'

def upgrade() -> None:
    # Undo the problematic change from 0003
    op.execute("ALTER TABLE example DROP COLUMN problematic_field;")

def downgrade() -> None:
    # Re-add the field (mirrors 0003 upgrade)
    op.execute("ALTER TABLE example ADD COLUMN problematic_field VARCHAR(50);")
```

**Best practice:** Prefer fix-forward in production.

## Notifications

The pipeline can send SMTP notifications on push to `main`.

### Configuring notifications

Set the following GitHub Secrets:

| Secret | Example |
|---|---|
| `MAIL_SERVER` | `smtp.gmail.com` |
| `MAIL_PORT` | `587` |
| `MAIL_USERNAME` | `ci@example.com` |
| `MAIL_PASSWORD` | `<app-password>` |
| `MAIL_FROM` | `pf-db CI <ci@example.com>` |
| `MAIL_TO` | `team@example.com` |

### Notification triggers

**Failure:**
- Sent if `test` job fails on push to `main`
- Does not fire on PR failures
- Does not fire on gate rejection

**Success:**
- Sent after migrations are successfully applied (if configured)

## Deployment coordination

pf-db migrations must complete **before** pf-rates and pf-payroll deploy.

### Correct order

```
1. pf-db: Run Cloud Run Job (alembic upgrade head)
   └─> wait for completion

2. pf-rates: Deploy Cloud Run Service
   └─> can now serve traffic

3. pf-payroll: Deploy Cloud Run Service
   └─> can now serve traffic
```

### GitHub Actions orchestration (conceptual)

```yaml
jobs:
  migrate:
    runs-on: ubuntu-latest
    steps:
      - name: Run pf-db migrations
        run: |
          gcloud run jobs execute pf-db-migrate --region=us-central1 --wait
  
  deploy-rates:
    needs: migrate
    runs-on: ubuntu-latest
    steps:
      - name: Deploy pf-rates
        run: |
          gcloud run deploy pf-rates ...
  
  deploy-payroll:
    needs: migrate
    runs-on: ubuntu-latest
    steps:
      - name: Deploy pf-payroll
        run: |
          gcloud run deploy pf-payroll ...
```

## Invariants (never violate)

### 1. Migrations before traffic

The `pf-db` Cloud Run Job must complete before pf-rates or pf-payroll receive traffic.

**Why:** Ensures schema is up-to-date before application code runs.

### 2. Manual approval required

Never bypass the manual approval gate for production migrations.

**Why:** Database changes are high-risk. Human review is critical.

### 3. CI must pass

Never merge a PR if CI fails.

**Why:** Indicates the migration will fail in production.

### 4. No autogenerate

Never use `alembic revision --autogenerate`.

**Why:** pf-db has no ORM models (`target_metadata = None`). Autogenerate would fail or produce incorrect migrations.

## Troubleshooting CI

### CI is slow

**Expected duration:** ~2 minutes

**If slower:**
1. Check if PostgreSQL container is starting slowly
2. Check if migrations are taking a long time (complex DDL)
3. Check GitHub Actions runner queue

### CI fails intermittently

**Possible causes:**
- Network issues (Docker pull)
- PostgreSQL startup timeout
- Flaky migration (race condition)

**Solution:**
- Retry the workflow
- If persists, investigate migration code

### CI passes locally but fails in CI

**Possible causes:**
- Different PostgreSQL version (local vs CI)
- Different environment variables
- Migration assumes existing data (CI starts from scratch)

**Solution:**
- Run `make local-up-real` to test migrations from scratch
- Ensure migrations are idempotent

## See also

- [Getting Started](getting-started.md) - Installation and setup
- [Development Guide](development.md) - Make commands and workflows
- [Migrations Guide](migrations.md) - Creating and managing migrations
- [pf-rates Deployment Guide](../pf-rates/docs/deployment.md) - Service deployment
- [pf-payroll Deployment Guide](../pf-payroll/docs/deployment.md) - Service deployment
