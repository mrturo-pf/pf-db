"""Rename payroll-owned schema objects to the INC vocabulary.

Revision ID: 0017
Revises: 0016
Create Date: 2026-10-15

This migration is intentionally reversible. It is designed for a short
maintenance boundary: the old application must not write while the object and
semantic-column names change.
"""

from __future__ import annotations

from sqlalchemy import text
from alembic import op

revision: str = "0017"
down_revision: str | None = "0016"
branch_labels: str | None = None
depends_on: str | None = None

_TABLE_RENAMES = (
    ("PAY_PENS_INST", "INC_PENS_INST"),
    ("PAY_HLTH_INST", "INC_HLTH_INST"),
    ("PAY_PENS_PLAN", "INC_PENS_PLAN"),
    ("PAY_HLTH_PLAN", "INC_HLTH_PLAN"),
    ("PAY_CNTRB_CAP", "INC_CNTRB_CAP"),
    ("PAY_COMP_PROV", "INC_COMP_PROV"),
    ("PAY_COMP_PLAN", "INC_COMP_PLAN"),
    ("PAY_EMPLOYER", "INC_EMPLOYER"),
    ("PAY_EMP_CONT", "INC_EMP_CONT"),
    ("PAY_PERIOD", "INC_PAYROLL"),
    ("PAY_PRD_HLTH", "INC_PAY_PRD_HLTH"),
    ("PAY_PRD_COMP", "INC_PAY_PRD_COMP"),
    ("PAY_CONCEPT", "INC_PAY_CONCEPT"),
    ("PAY_ITEM", "INC_PAY_ITEM"),
    ("PAY_PDF_TEMPLATE", "INC_PAY_PDF_TEMPLATE"),
    ("PAY_PDF_TEMPLATE_FIELD", "INC_PAY_PDF_TEMPLATE_FIELD"),
)

_COLUMN_RENAMES = (
    ("PAY_PRD_HLTH", "period_id", "payroll_id"),
    ("PAY_PRD_COMP", "period_id", "payroll_id"),
    ("PAY_ITEM", "period_id", "payroll_id"),
    ("PAY_PERIOD", "period_year", "accrual_year"),
    ("PAY_PERIOD", "period_month", "accrual_month"),
)


def _assert_objects_exist(names: tuple[str, ...]) -> None:
    """Fail before mutation when the migration baseline is unexpected."""
    bind = op.get_bind()
    missing = [
        name
        for name in names
        if bind.execute(
            text("SELECT to_regclass(format('%I.%I', 'public', CAST(:object_name AS text)))"),
            {"object_name": name},
        ).scalar_one_or_none()
        is None
    ]
    if missing:
        raise RuntimeError(f"Migration baseline is missing objects: {', '.join(missing)}")


def _rename_summary_view(
    view_name: str,
    payroll_table: str,
    item_table: str,
    concept_table: str,
    period_id: str,
    year: str,
    month: str,
) -> None:
    """Create the summary view using the current schema vocabulary."""
    op.execute(f'DROP MATERIALIZED VIEW IF EXISTS "{view_name}"')
    op.execute(
        f'''
        CREATE MATERIALIZED VIEW "{view_name}" AS
        SELECT
            p.id AS {period_id},
            p.employer_id,
            p.{year},
            p.{month},
            p.payment_date,
            SUM(CASE WHEN c.kind = 'income' AND c.is_taxable THEN i.amount_clp ELSE 0 END)
                AS taxable_income_clp,
            SUM(CASE WHEN c.kind = 'income' THEN i.amount_clp ELSE 0 END)
                AS gross_income_clp,
            SUM(CASE WHEN c.kind = 'discount' THEN i.amount_clp ELSE 0 END)
                AS total_discounts_clp,
            SUM(CASE WHEN c.kind = 'income' THEN i.amount_clp ELSE 0 END) -
            SUM(CASE WHEN c.kind = 'discount' THEN i.amount_clp ELSE 0 END)
                AS net_pay_clp
        FROM "{payroll_table}" p
        JOIN "{item_table}" i ON i.{period_id} = p.id
        JOIN "{concept_table}" c ON c.id = i.concept_id
        GROUP BY p.id, p.employer_id, p.{year}, p.{month}, p.payment_date
        '''
    )
    op.execute(
        f'CREATE UNIQUE INDEX "idx_{view_name.lower()}_{period_id}" '
        f'ON "{view_name}"({period_id})'
    )


def upgrade() -> None:
    """Rename payroll objects and semantic period columns to INC names."""
    _assert_objects_exist(tuple(name for name, _ in _TABLE_RENAMES))
    _assert_objects_exist(("PAY_MV_SUMARY",))

    op.execute('DROP MATERIALIZED VIEW "PAY_MV_SUMARY"')
    op.execute('DROP INDEX IF EXISTS "idx_pay_mv_sumary_period"')

    for source, target in _TABLE_RENAMES:
        op.rename_table(source, target)

    for table, source, target in _COLUMN_RENAMES:
        renamed_table = dict(_TABLE_RENAMES)[table]
        op.alter_column(renamed_table, source, new_column_name=target)

    _rename_summary_view(
        "INC_MV_PAY_SUMMARY",
        "INC_PAYROLL",
        "INC_PAY_ITEM",
        "INC_PAY_CONCEPT",
        "payroll_id",
        "accrual_year",
        "accrual_month",
    )


def downgrade() -> None:
    """Restore PAY names and the original summary-view vocabulary."""
    _assert_objects_exist(tuple(target for _, target in _TABLE_RENAMES))
    _assert_objects_exist(("INC_MV_PAY_SUMMARY",))

    op.execute('DROP MATERIALIZED VIEW "INC_MV_PAY_SUMMARY"')
    op.execute('DROP INDEX IF EXISTS "idx_inc_mv_pay_summary_payroll_id"')

    for table, source, target in _COLUMN_RENAMES:
        renamed_table = dict(_TABLE_RENAMES)[table]
        op.alter_column(renamed_table, target, new_column_name=source)

    for source, target in reversed(_TABLE_RENAMES):
        op.rename_table(target, source)

    _rename_summary_view(
        "PAY_MV_SUMARY",
        "PAY_PERIOD",
        "PAY_ITEM",
        "PAY_CONCEPT",
        "period_id",
        "period_year",
        "period_month",
    )
