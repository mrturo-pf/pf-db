"""rename tables with service prefix and 14 char limit

Revision ID: 0003
Revises: 0002
Create Date: 2026-07-25

Renames all tables to follow naming convention:
- UPPERCASE
- Max 14 characters
- Service prefix: RAT_ (pf-rates) or PAY_ (pf-payroll)

"""
from alembic import op

# revision identifiers, used by Alembic.
revision = '0003'
down_revision = '0002'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Rename all tables to new naming convention."""

    # pf-rates tables (RAT_ prefix)
    op.rename_table('currencies', 'RAT_CURRENCY')
    op.rename_table('exchange_rates', 'RAT_EXCH_RATE')
    op.rename_table('economic_indices', 'RAT_ECON_INDEX')
    op.rename_table('income_tax_brackets', 'RAT_TAX_BRCKT')

    # pf-payroll tables (PAY_ prefix)
    op.rename_table('pension_institutions', 'PAY_PENS_INST')
    op.rename_table('health_institutions', 'PAY_HLTH_INST')
    op.rename_table('pension_plans', 'PAY_PENS_PLAN')
    op.rename_table('health_plans', 'PAY_HLTH_PLAN')
    op.rename_table('contribution_caps', 'PAY_CNTRB_CAP')
    op.rename_table('complementary_insurance_providers', 'PAY_COMP_PROV')
    op.rename_table('complementary_insurance_plans', 'PAY_COMP_PLAN')
    op.rename_table('employers', 'PAY_EMPLOYER')
    op.rename_table('payroll_periods', 'PAY_PERIOD')
    op.rename_table('payroll_period_health_plans', 'PAY_PRD_HLTH')
    op.rename_table('payroll_complementary_insurance', 'PAY_PRD_COMP')
    op.rename_table('payroll_concepts', 'PAY_CONCEPT')
    op.rename_table('payroll_items', 'PAY_ITEM')

    # Materialized view
    op.execute('DROP MATERIALIZED VIEW IF EXISTS mv_payroll_summary')
    op.execute('''
        CREATE MATERIALIZED VIEW PAY_MV_SUMARY AS
        SELECT
            pp.id AS period_id,
            pp.employer_id,
            pp.period_year,
            pp.period_month,
            pp.payment_date,
            SUM(CASE WHEN pc.kind = 'income' THEN pi.amount_clp ELSE 0 END)
                AS taxable_income_clp,
            SUM(CASE WHEN pc.kind = 'income' THEN pi.amount_clp ELSE 0 END)
                AS gross_income_clp,
            SUM(CASE WHEN pc.kind = 'discount' THEN pi.amount_clp ELSE 0 END)
                AS total_discounts_clp,
            SUM(CASE WHEN pc.kind = 'income' THEN pi.amount_clp ELSE 0 END) -
            SUM(CASE WHEN pc.kind = 'discount' THEN pi.amount_clp ELSE 0 END)
                AS net_pay_clp
        FROM PAY_PERIOD pp
        LEFT JOIN PAY_ITEM pi ON pp.id = pi.period_id
        LEFT JOIN PAY_CONCEPT pc ON pi.concept_id = pc.id
        GROUP BY pp.id, pp.employer_id, pp.period_year, pp.period_month, pp.payment_date
    ''')
    op.execute('CREATE UNIQUE INDEX idx_pay_mv_sumary_period ON PAY_MV_SUMARY(period_id)')


def downgrade() -> None:
    """Revert table names to original naming convention."""

    # Materialized view
    op.execute('DROP MATERIALIZED VIEW IF EXISTS PAY_MV_SUMARY')
    op.execute('''
        CREATE MATERIALIZED VIEW mv_payroll_summary AS
        SELECT
            pp.id AS period_id,
            pp.employer_id,
            pp.period_year,
            pp.period_month,
            pp.payment_date,
            SUM(CASE WHEN pc.kind = 'income' THEN pi.amount_clp ELSE 0 END)
                AS taxable_income_clp,
            SUM(CASE WHEN pc.kind = 'income' THEN pi.amount_clp ELSE 0 END)
                AS gross_income_clp,
            SUM(CASE WHEN pc.kind = 'discount' THEN pi.amount_clp ELSE 0 END)
                AS total_discounts_clp,
            SUM(CASE WHEN pc.kind = 'income' THEN pi.amount_clp ELSE 0 END) -
            SUM(CASE WHEN pc.kind = 'discount' THEN pi.amount_clp ELSE 0 END)
                AS net_pay_clp
        FROM payroll_periods pp
        LEFT JOIN payroll_items pi ON pp.id = pi.period_id
        LEFT JOIN payroll_concepts pc ON pi.concept_id = pc.id
        GROUP BY pp.id, pp.employer_id, pp.period_year, pp.period_month, pp.payment_date
    ''')
    op.execute(
        'CREATE UNIQUE INDEX idx_mv_payroll_summary_period '
        'ON mv_payroll_summary(period_id)'
    )

    # pf-payroll tables (reverse order for FK dependencies)
    op.rename_table('PAY_ITEM', 'payroll_items')
    op.rename_table('PAY_CONCEPT', 'payroll_concepts')
    op.rename_table('PAY_PRD_COMP', 'payroll_complementary_insurance')
    op.rename_table('PAY_PRD_HLTH', 'payroll_period_health_plans')
    op.rename_table('PAY_PERIOD', 'payroll_periods')
    op.rename_table('PAY_EMPLOYER', 'employers')
    op.rename_table('PAY_COMP_PLAN', 'complementary_insurance_plans')
    op.rename_table('PAY_COMP_PROV', 'complementary_insurance_providers')
    op.rename_table('PAY_CNTRB_CAP', 'contribution_caps')
    op.rename_table('PAY_HLTH_PLAN', 'health_plans')
    op.rename_table('PAY_PENS_PLAN', 'pension_plans')
    op.rename_table('PAY_HLTH_INST', 'health_institutions')
    op.rename_table('PAY_PENS_INST', 'pension_institutions')

    # pf-rates tables
    op.rename_table('RAT_TAX_BRCKT', 'income_tax_brackets')
    op.rename_table('RAT_ECON_INDEX', 'economic_indices')
    op.rename_table('RAT_EXCH_RATE', 'exchange_rates')
    op.rename_table('RAT_CURRENCY', 'currencies')
