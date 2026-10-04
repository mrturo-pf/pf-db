"""Drop PAY_PDF_TEMPLATE.employer_name; employer_id becomes required.

`employer_name` was a nullable *literal override* column, added as a
fallback for the case where a template had no `employer_id` to resolve a
display name from (see migration `0010`'s own docstring). Product decided
that fallback is not worth the column: a template may only be created for
an employer that already has a `PAY_EMPLOYER` row (i.e. after its first
payroll import has run at least once) -- `employer_id` is now mandatory,
and the display name is *always* resolved fresh from `PAY_EMPLOYER.name` at
read time, exactly like it already was for the subset of rows that had a
NULL `employer_name` before this migration.

This is a real behavior change, not just a storage cleanup: it is no longer
possible to pre-create a template for a brand-new employer before their
first import. That tradeoff was confirmed explicitly by the user rather
than assumed -- see pf-payroll/docs/proposals/
pdf-template-management-plan.md's "Third follow-up" section.

Revision ID: 0012
Revises: 0011
Create Date: 2026-10-01
"""

from alembic import op

revision: str = "0012"
down_revision: str | None = "0011"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    """Backfill employer_id where possible, then require it and drop employer_name."""
    # Defensive backfill: in theory a pre-existing row could have relied on
    # employer_name alone (employer_id NULL) under the old CHECK constraint.
    # None do in practice (the real seed already always sets employer_id),
    # but resolve it here rather than assume, exactly like migration 0011
    # backfilled concept_id from concept_code instead of assuming every row
    # already had one.
    op.execute("""
        UPDATE "PAY_PDF_TEMPLATE" t
        SET employer_id = e.id
        FROM "PAY_EMPLOYER" e
        WHERE t.employer_id IS NULL AND t.employer_name = e.name
    """)
    op.execute("""
        DO $$
        DECLARE
            orphan_count INTEGER;
        BEGIN
            SELECT count(*) INTO orphan_count
            FROM "PAY_PDF_TEMPLATE"
            WHERE employer_id IS NULL;
            IF orphan_count > 0 THEN
                RAISE EXCEPTION
                    'Cannot make PAY_PDF_TEMPLATE.employer_id NOT NULL: % row(s) '
                    'have no employer_id and no matching PAY_EMPLOYER.name to '
                    'backfill from.', orphan_count;
            END IF;
        END $$;
    """)
    op.execute('ALTER TABLE "PAY_PDF_TEMPLATE" ALTER COLUMN employer_id SET NOT NULL')
    op.execute(
        'ALTER TABLE "PAY_PDF_TEMPLATE" '
        "DROP CONSTRAINT IF EXISTS chk_pay_pdf_template_employer_ref"
    )
    op.execute('ALTER TABLE "PAY_PDF_TEMPLATE" DROP COLUMN IF EXISTS employer_name')


def downgrade() -> None:
    """Restore employer_name (NULL -- the original literal is gone) and the CHECK."""
    op.execute(
        'ALTER TABLE "PAY_PDF_TEMPLATE" ADD COLUMN IF NOT EXISTS employer_name '
        "VARCHAR(120)"
    )
    op.execute('ALTER TABLE "PAY_PDF_TEMPLATE" ALTER COLUMN employer_id DROP NOT NULL')
    op.execute("""
        ALTER TABLE "PAY_PDF_TEMPLATE"
        ADD CONSTRAINT chk_pay_pdf_template_employer_ref
        CHECK (employer_id IS NOT NULL OR employer_name IS NOT NULL)
    """)
