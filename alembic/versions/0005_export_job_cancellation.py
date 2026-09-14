"""Add cancellation support to the export jobs table.

Backs the "stop a job" flow in pf-rates:
`POST /exchange-rates/export/jobs/{id}/stop` and the bulk
`POST /exchange-rates/export/jobs/stop`. Cancellation is cooperative --
this migration only adds the flag the running export loop polls
(`cancel_requested_at`) and the terminal status it lands on
(`cancelled`). There is no message queue in front of pf-rates (Cloud Run
+ BackgroundTasks only, by deliberate cost choice -- see AGENTS.md
"Cloud cost optimization"), so a real cross-instance force-kill would
require new paid infra (Pub/Sub, Cloud Tasks). Cooperative cancellation
achieves the same practical outcome at zero extra cost.

Also adds an index on (status, created_at): backs
`GET /exchange-rates/export/jobs` (list + filter by status/date range)
and the bulk-stop lookup of active jobs, both of which would otherwise
scan the whole table as job history grows.

Table: RAT_EXPORT_JOB.

Revision ID: 0005
Revises: 0004
Create Date: 2026-09-14
"""

from alembic import op

revision: str = "0005"
down_revision: str | None = "0004"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    """Add 'cancelled' status, cancel_requested_at column, and a filter index."""
    op.execute(
        'ALTER TABLE "RAT_EXPORT_JOB" '
        "DROP CONSTRAINT IF EXISTS chk_rat_export_job_status"
    )
    op.execute("""
        ALTER TABLE "RAT_EXPORT_JOB"
        ADD CONSTRAINT chk_rat_export_job_status
        CHECK (status IN ('pending', 'running', 'succeeded', 'failed', 'cancelled'))
    """)
    op.execute("""
        ALTER TABLE "RAT_EXPORT_JOB"
        ADD COLUMN IF NOT EXISTS cancel_requested_at TIMESTAMPTZ NULL
    """)
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_rat_export_job_status_created
        ON "RAT_EXPORT_JOB" (status, created_at)
    """)


def downgrade() -> None:
    """Drop the index/column and restore the original 4-value status check.

    Only safe to run if no row currently has status = 'cancelled' -- the
    restored constraint does not allow that value. Convert or delete such
    rows first if you actually need to roll back in an environment where
    the cancellation flow has been used.
    """
    op.execute('DROP INDEX IF EXISTS idx_rat_export_job_status_created')
    op.execute(
        'ALTER TABLE "RAT_EXPORT_JOB" DROP COLUMN IF EXISTS cancel_requested_at'
    )
    op.execute(
        'ALTER TABLE "RAT_EXPORT_JOB" '
        "DROP CONSTRAINT IF EXISTS chk_rat_export_job_status"
    )
    op.execute("""
        ALTER TABLE "RAT_EXPORT_JOB"
        ADD CONSTRAINT chk_rat_export_job_status
        CHECK (status IN ('pending', 'running', 'succeeded', 'failed'))
    """)
