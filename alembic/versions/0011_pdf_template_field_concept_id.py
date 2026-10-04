"""Switch PAY_PDF_TEMPLATE_FIELD to reference PAY_CONCEPT by id, not code.

Every other table that references `PAY_CONCEPT` does so through its
surrogate integer primary key -- `PAY_ITEM.concept_id BIGINT REFERENCES
PAY_CONCEPT(id)` is the established convention (see `01_schema.sql`, section
3). `PAY_PDF_TEMPLATE_FIELD.concept_code VARCHAR(40) REFERENCES
PAY_CONCEPT(code)` (added in 0009) was the only place in the whole schema
that referenced `PAY_CONCEPT` by its natural key instead -- an unintentional
inconsistency, not a deliberate design choice, caught during a follow-up
review (see
pf-payroll/docs/proposals/pdf-template-management-plan.md's
"Follow-up session" section for the full writeup).

This migration adds `concept_id`, backfills it from the existing
`concept_code` values, then drops `concept_code` entirely. The application
layer's DTOs/API contract are unaffected -- `concept_code` remains the
business-facing identifier everywhere outside the database (requests,
responses, the PDF-matching engine, `CONCEPT_MAP`); only the storage column
changes, resolved at the repository boundary exactly like `kind` already is
(see migration 0010).

Revision ID: 0011
Revises: 0010
Create Date: 2026-10-01
"""

from alembic import op

revision: str = "0011"
down_revision: str | None = "0010"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    """Add concept_id, backfill it from concept_code, then drop concept_code."""
    op.execute(
        'ALTER TABLE "PAY_PDF_TEMPLATE_FIELD" ADD COLUMN IF NOT EXISTS concept_id BIGINT'
    )
    op.execute("""
        UPDATE "PAY_PDF_TEMPLATE_FIELD" f
        SET concept_id = c.id
        FROM "PAY_CONCEPT" c
        WHERE f.concept_code = c.code AND f.concept_id IS NULL
    """)
    op.execute(
        'ALTER TABLE "PAY_PDF_TEMPLATE_FIELD" ALTER COLUMN concept_id SET NOT NULL'
    )
    op.execute("""
        ALTER TABLE "PAY_PDF_TEMPLATE_FIELD"
        ADD CONSTRAINT fk_pay_pdf_template_field_concept_id
        FOREIGN KEY (concept_id) REFERENCES "PAY_CONCEPT"(id)
    """)
    op.execute(
        'ALTER TABLE "PAY_PDF_TEMPLATE_FIELD" DROP COLUMN IF EXISTS concept_code'
    )
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_pay_pdf_template_field_concept_id
        ON "PAY_PDF_TEMPLATE_FIELD"(concept_id)
    """)


def downgrade() -> None:
    """Restore concept_code, backfilling it from concept_id, then drop concept_id."""
    op.execute(
        'DROP INDEX IF EXISTS idx_pay_pdf_template_field_concept_id'
    )
    op.execute(
        'ALTER TABLE "PAY_PDF_TEMPLATE_FIELD" ADD COLUMN IF NOT EXISTS concept_code VARCHAR(40)'
    )
    op.execute("""
        UPDATE "PAY_PDF_TEMPLATE_FIELD" f
        SET concept_code = c.code
        FROM "PAY_CONCEPT" c
        WHERE f.concept_id = c.id AND f.concept_code IS NULL
    """)
    op.execute(
        'ALTER TABLE "PAY_PDF_TEMPLATE_FIELD" ALTER COLUMN concept_code SET NOT NULL'
    )
    op.execute("""
        ALTER TABLE "PAY_PDF_TEMPLATE_FIELD"
        ADD CONSTRAINT "PAY_PDF_TEMPLATE_FIELD_concept_code_fkey"
        FOREIGN KEY (concept_code) REFERENCES "PAY_CONCEPT"(code)
    """)
    op.execute(
        'ALTER TABLE "PAY_PDF_TEMPLATE_FIELD" DROP CONSTRAINT IF EXISTS '
        "fk_pay_pdf_template_field_concept_id"
    )
    op.execute(
        'ALTER TABLE "PAY_PDF_TEMPLATE_FIELD" DROP COLUMN IF EXISTS concept_id'
    )
