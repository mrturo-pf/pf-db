"""Rename rates index period columns to the accrual vocabulary.

Revision ID: 0018
Revises: 0017
Create Date: 2026-10-15
"""

from __future__ import annotations

from alembic import op

revision: str = "0018"
down_revision: str | None = "0017"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    """Rename the historical rates period columns."""
    op.alter_column(
        "RAT_ECON_INDEX", "period_year", new_column_name="accrual_year"
    )
    op.alter_column(
        "RAT_ECON_INDEX", "period_month", new_column_name="accrual_month"
    )


def downgrade() -> None:
    """Restore the historical rates period column names."""
    op.alter_column(
        "RAT_ECON_INDEX", "accrual_year", new_column_name="period_year"
    )
    op.alter_column(
        "RAT_ECON_INDEX", "accrual_month", new_column_name="period_month"
    )
