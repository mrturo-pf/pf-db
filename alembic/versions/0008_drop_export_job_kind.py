"""Drop export_kind from the export jobs table.

Reverses migration `0007`. `export_kind` was added to let a single
RAT_EXPORT_JOB lifecycle distinguish between two CSV-export trigger
endpoints (`POST /exchange-rates/export` producing 'exchange_rates' rows,
`POST /exports/financial-data` producing 'combined' rows). The
exchange-rates-only endpoint has since been removed from pf-rates --
`POST /exports/financial-data` is now the only export trigger that
exists, so the discriminator has nothing left to discriminate between.

Table: RAT_EXPORT_JOB.

Revision ID: 0008
Revises: 0007
Create Date: 2026-09-20
"""

from alembic import op

revision: str = "0008"
down_revision: str | None = "0007"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    """Drop export_kind and its CHECK constraint."""
    op.execute(
        'ALTER TABLE "RAT_EXPORT_JOB" DROP CONSTRAINT IF EXISTS chk_rat_export_job_kind'
    )
    op.execute('ALTER TABLE "RAT_EXPORT_JOB" DROP COLUMN IF EXISTS export_kind')


def downgrade() -> None:
    """Re-add export_kind (default 'exchange_rates') with its CHECK constraint.

    Exact mirror of migration 0007's upgrade(): every row gets the same
    default it would have gotten back then, since 'exchange_rates' was
    (and remains) the only kind that ever existed before this column was
    first introduced.
    """
    op.execute("""
        ALTER TABLE "RAT_EXPORT_JOB"
        ADD COLUMN IF NOT EXISTS export_kind VARCHAR(20) NOT NULL DEFAULT 'exchange_rates'
    """)
    op.execute("""
        ALTER TABLE "RAT_EXPORT_JOB"
        ADD CONSTRAINT chk_rat_export_job_kind
        CHECK (export_kind IN ('exchange_rates', 'combined'))
    """)
