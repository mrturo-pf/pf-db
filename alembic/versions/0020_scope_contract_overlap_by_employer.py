"""Scope contract interval exclusion to each employer.

Revision ID: 0020
Revises: 0019
Create Date: 2026-10-25

Revision 0016 excluded overlapping contract intervals globally, which incorrectly
prevented two different employers from having contracts covering the same dates.
The exclusion must compare employer_id equality as well as date-range overlap.
"""

from __future__ import annotations

from alembic import op

revision: str = "0020"
down_revision: str | None = "0019"
branch_labels: str | None = None
depends_on: str | None = None

_CONSTRAINT = "ex_pay_emp_cont_no_overlap"
_TABLE = "INC_EMP_CONT"


def upgrade() -> None:
    """Allow overlapping dates across employers but not within one employer."""
    op.execute(f'ALTER TABLE "{_TABLE}" DROP CONSTRAINT IF EXISTS {_CONSTRAINT}')
    op.execute(
        f'''
        ALTER TABLE "{_TABLE}"
        ADD CONSTRAINT {_CONSTRAINT}
        EXCLUDE USING gist (
            employer_id WITH =,
            daterange(
                started_at,
                COALESCE(ended_at, 'infinity'::date),
                '[]'
            ) WITH &&
        )
        '''
    )


def downgrade() -> None:
    """Restore the legacy global interval exclusion."""
    op.execute(f'ALTER TABLE "{_TABLE}" DROP CONSTRAINT IF EXISTS {_CONSTRAINT}')
    op.execute(
        f'''
        ALTER TABLE "{_TABLE}"
        ADD CONSTRAINT {_CONSTRAINT}
        EXCLUDE USING gist (
            daterange(
                started_at,
                COALESCE(ended_at, 'infinity'::date),
                '[]'
            ) WITH &&
        )
        '''
    )
