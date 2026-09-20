"""Add export_kind to the export jobs table.

Backs the new `POST /exports/financial-data` endpoint in pf-rates, which
reuses the exact same RAT_EXPORT_JOB lifecycle (pending/running/succeeded/
failed/cancelled, cooperative cancellation, progress tracking) already
built for `POST /exchange-rates/export {"async": true}` -- the only thing
that differs between the two flows is *what* gets exported, not how the
job is tracked. `export_kind` is the discriminator that lets a single
`GET /exchange-rates/export/jobs/{id}` (kind-agnostic by design: it reads
RAT_EXPORT_JOB by id regardless of what produced the row) tell the two
apart in its response.

Defaults every existing row to 'exchange_rates' -- the only kind that
existed before this migration -- so no backfill step is needed beyond the
column default itself.

Table: RAT_EXPORT_JOB.

Revision ID: 0007
Revises: 0006
Create Date: 2026-09-20
"""

from alembic import op

revision: str = "0007"
down_revision: str | None = "0006"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    """Add export_kind (default 'exchange_rates') with a CHECK constraint."""
    op.execute("""
        ALTER TABLE "RAT_EXPORT_JOB"
        ADD COLUMN IF NOT EXISTS export_kind VARCHAR(20) NOT NULL DEFAULT 'exchange_rates'
    """)
    op.execute("""
        ALTER TABLE "RAT_EXPORT_JOB"
        DROP CONSTRAINT IF EXISTS chk_rat_export_job_kind
    """)
    op.execute("""
        ALTER TABLE "RAT_EXPORT_JOB"
        ADD CONSTRAINT chk_rat_export_job_kind
        CHECK (export_kind IN ('exchange_rates', 'combined'))
    """)


def downgrade() -> None:
    """Drop export_kind and its CHECK constraint."""
    op.execute('ALTER TABLE "RAT_EXPORT_JOB" DROP COLUMN IF EXISTS export_kind')
