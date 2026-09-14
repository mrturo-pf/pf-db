"""Add progress tracking to the export jobs table.

Backs a "how far along is this job" view for pf-rates:
`GET /exchange-rates/export/jobs/{id}` and `GET /exchange-rates/export/jobs`
now report `processed_items`/`total_items` (and a derived percentage) while
a job is 'running', instead of leaving the caller to guess from status
alone. `total_items` is the number of (currency, date) pairs the export
loop will visit -- known only once the currency list and date window are
resolved at the start of execute(), hence nullable. `processed_items`
starts at 0 and increases monotonically as the loop advances, reusing the
same periodic checkpoint cadence already used for cancellation polling
(EXPORT_CANCELLATION_CHECK_INTERVAL) -- no extra DB round-trips beyond
what migration 0005 already introduced.

Table: RAT_EXPORT_JOB.

Revision ID: 0006
Revises: 0005
Create Date: 2026-09-14
"""

from alembic import op

revision: str = "0006"
down_revision: str | None = "0005"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    """Add total_items (nullable) and processed_items (default 0)."""
    op.execute("""
        ALTER TABLE "RAT_EXPORT_JOB"
        ADD COLUMN IF NOT EXISTS total_items INTEGER NULL
            CHECK (total_items IS NULL OR total_items >= 0)
    """)
    op.execute("""
        ALTER TABLE "RAT_EXPORT_JOB"
        ADD COLUMN IF NOT EXISTS processed_items INTEGER NOT NULL DEFAULT 0
            CHECK (processed_items >= 0)
    """)


def downgrade() -> None:
    """Drop both progress-tracking columns."""
    op.execute('ALTER TABLE "RAT_EXPORT_JOB" DROP COLUMN IF EXISTS processed_items')
    op.execute('ALTER TABLE "RAT_EXPORT_JOB" DROP COLUMN IF EXISTS total_items')
