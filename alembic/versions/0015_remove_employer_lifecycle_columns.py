"""Remove legacy PAY_EMPLOYER lifecycle dates.

Employment lifecycle dates are now owned by PAY_EMP_CONT. The application
resolves employer bounds from MIN/MAX contract intervals.

Revision ID: 0015
Revises: 0014
Create Date: 2026-10-03
"""

from alembic import op

revision: str = "0015"
down_revision: str | None = "0014"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    """Drop the duplicated employer lifecycle columns."""
    op.execute('ALTER TABLE "PAY_EMPLOYER" DROP COLUMN IF EXISTS started_at')
    op.execute('ALTER TABLE "PAY_EMPLOYER" DROP COLUMN IF EXISTS ended_at')


def downgrade() -> None:
    """Restore lifecycle columns from contract bounds."""
    op.execute(
        'ALTER TABLE "PAY_EMPLOYER" ADD COLUMN IF NOT EXISTS started_at DATE'
    )
    op.execute('ALTER TABLE "PAY_EMPLOYER" ADD COLUMN IF NOT EXISTS ended_at DATE')
    op.execute("""
        UPDATE "PAY_EMPLOYER" e
        SET started_at = bounds.started_at,
            ended_at = bounds.ended_at
        FROM (
            SELECT employer_id,
                   MIN(started_at) AS started_at,
                   CASE WHEN bool_or(ended_at IS NULL)
                        THEN NULL ELSE MAX(ended_at) END AS ended_at
            FROM "PAY_EMP_CONT"
            GROUP BY employer_id
        ) bounds
        WHERE bounds.employer_id = e.id
    """)
    op.execute(
        'ALTER TABLE "PAY_EMPLOYER" ALTER COLUMN started_at SET NOT NULL'
    )
