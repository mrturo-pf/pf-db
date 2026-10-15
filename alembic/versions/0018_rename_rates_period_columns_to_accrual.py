"""Rename rates index period columns to the accrual vocabulary.

Revision ID: 0018
Revises: 0017
Create Date: 2026-10-15
"""

from __future__ import annotations

from alembic import op
from sqlalchemy import text

revision: str = "0018"
down_revision: str | None = "0017"
branch_labels: str | None = None
depends_on: str | None = None


def _has_column(column_name: str) -> bool:
    """Return whether the rates table contains a column."""
    return (
        op.get_bind()
        .execute(
            text(
                """
                SELECT 1
                FROM information_schema.columns
                WHERE table_schema = 'public'
                  AND table_name = 'RAT_ECON_INDEX'
                  AND column_name = :column_name
                """
            ),
            {"column_name": column_name},
        )
        .scalar_one_or_none()
        is not None
    )


def upgrade() -> None:
    """Rename rates columns when the applied 0017 baseline still has PAY names."""
    has_period = _has_column("period_year") and _has_column("period_month")
    has_accrual = _has_column("accrual_year") and _has_column("accrual_month")
    if has_accrual and not has_period:
        return
    if not has_period or has_accrual:
        raise RuntimeError("RAT_ECON_INDEX has an inconsistent period/accrual column state")
    op.alter_column("RAT_ECON_INDEX", "period_year", new_column_name="accrual_year")
    op.alter_column("RAT_ECON_INDEX", "period_month", new_column_name="accrual_month")


def downgrade() -> None:
    """Restore rates period names only when accrual columns are present."""
    has_period = _has_column("period_year") and _has_column("period_month")
    has_accrual = _has_column("accrual_year") and _has_column("accrual_month")
    if has_period and not has_accrual:
        return
    if not has_accrual or has_period:
        raise RuntimeError("RAT_ECON_INDEX has an inconsistent period/accrual column state")
    op.alter_column("RAT_ECON_INDEX", "accrual_year", new_column_name="period_year")
    op.alter_column("RAT_ECON_INDEX", "accrual_month", new_column_name="period_month")
