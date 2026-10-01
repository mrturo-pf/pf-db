"""Remove redundant denormalized columns from PAY_PDF_TEMPLATE*.

Two columns added in 0009 turned out to duplicate data already owned by
another table, with nothing enforcing the two copies stay in sync -- caught
during a design review (see
pf-payroll/docs/proposals/pdf-template-management-design-plan.md's
"Denormalization follow-up" section for the full writeup):

1. `PAY_PDF_TEMPLATE_FIELD.kind` duplicated `PAY_CONCEPT.kind` with zero
   referential integrity tying them together -- `concept_code` is already a
   FK to `PAY_CONCEPT(code)`, which already has its own `kind` CHECK
   (`income`/`discount`). A client could POST/PUT a field whose `kind`
   contradicted its own concept's real kind, silently misclassifying PDF
   rows as income vs. discount at preview time. Dropped outright; the
   application layer now always resolves `kind` from `PAY_CONCEPT` (a write
   actively rejects an unknown `concept_code` before it ever reaches a
   commit, rather than relying on a `kind` value nobody double-checked).

2. `PAY_PDF_TEMPLATE.employer_name` duplicated `PAY_EMPLOYER.name` (via
   `employer_id`) in every case seen so far (confirmed against the real
   `walmart-chile-v1` seed row). Unlike `kind`, there is a real, legitimate
   case where the two must be allowed to differ (`employer_id` is nullable
   -- a template is not required to be linked to a `PAY_EMPLOYER` row, and
   even when linked, the literal name printed on a PDF is not guaranteed to
   match `PAY_EMPLOYER.name` verbatim). So this column is made nullable
   rather than dropped, with a new CHECK guaranteeing every row can still
   resolve *some* display name: either its own literal `employer_name`, or
   (when that's NULL) a join through `employer_id` at read time. No value is
   ever copied from `PAY_EMPLOYER` into this column anymore -- the
   application layer resolves it fresh on every read instead.

Revision ID: 0010
Revises: 0009
Create Date: 2026-10-01
"""

from alembic import op

revision: str = "0010"
down_revision: str | None = "0009"
branch_labels: str | None = None
depends_on: str | None = None

_EMPLOYER_REF_CHECK = "chk_pay_pdf_template_employer_ref"


def upgrade() -> None:
    """Drop PAY_PDF_TEMPLATE_FIELD.kind; make PAY_PDF_TEMPLATE.employer_name nullable."""
    op.execute('ALTER TABLE "PAY_PDF_TEMPLATE_FIELD" DROP COLUMN IF EXISTS kind')
    op.execute(
        'ALTER TABLE "PAY_PDF_TEMPLATE" ALTER COLUMN employer_name DROP NOT NULL'
    )
    op.execute(f"""
        ALTER TABLE "PAY_PDF_TEMPLATE"
        ADD CONSTRAINT {_EMPLOYER_REF_CHECK}
        CHECK (employer_id IS NOT NULL OR employer_name IS NOT NULL)
    """)


def downgrade() -> None:
    """Restore both columns, backfilling from the tables they used to duplicate."""
    op.execute(
        f'ALTER TABLE "PAY_PDF_TEMPLATE" DROP CONSTRAINT IF EXISTS {_EMPLOYER_REF_CHECK}'
    )
    op.execute("""
        UPDATE "PAY_PDF_TEMPLATE" t
        SET employer_name = e.name
        FROM "PAY_EMPLOYER" e
        WHERE t.employer_name IS NULL AND t.employer_id = e.id
    """)
    op.execute(
        'ALTER TABLE "PAY_PDF_TEMPLATE" ALTER COLUMN employer_name SET NOT NULL'
    )
    op.execute("""
        ALTER TABLE "PAY_PDF_TEMPLATE_FIELD"
        ADD COLUMN IF NOT EXISTS kind VARCHAR(20) CHECK (kind IN ('income', 'discount'))
    """)
    op.execute("""
        UPDATE "PAY_PDF_TEMPLATE_FIELD" f
        SET kind = c.kind
        FROM "PAY_CONCEPT" c
        WHERE f.concept_code = c.code
    """)
    op.execute(
        'ALTER TABLE "PAY_PDF_TEMPLATE_FIELD" ALTER COLUMN kind SET NOT NULL'
    )
