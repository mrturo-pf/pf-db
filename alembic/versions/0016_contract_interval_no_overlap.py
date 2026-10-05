"""Prevent overlapping employment-contract intervals globally.

Revision ID: 0016
Revises: 0015
Create Date: 2026-10-04
"""

from alembic import op

revision: str = "0016"
down_revision: str | None = "0015"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    """Add a global exclusion constraint for contract date ranges."""
    op.execute(
        'ALTER TABLE "PAY_EMP_CONT" '
        "DROP CONSTRAINT IF EXISTS ex_pay_emp_cont_no_overlap"
    )
    op.execute(
        """
        ALTER TABLE "PAY_EMP_CONT"
        ADD CONSTRAINT ex_pay_emp_cont_no_overlap
        EXCLUDE USING gist (
            daterange(
                started_at,
                COALESCE(ended_at, 'infinity'::date),
                '[]'
            ) WITH &&
        )
        """
    )


def downgrade() -> None:
    """Remove the global contract interval exclusion constraint."""
    op.execute(
        'ALTER TABLE "PAY_EMP_CONT" '
        "DROP CONSTRAINT IF EXISTS ex_pay_emp_cont_no_overlap"
    )
