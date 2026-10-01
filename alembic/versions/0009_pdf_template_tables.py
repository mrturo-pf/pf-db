"""Add PDF template management tables (PAY_PDF_TEMPLATE + PAY_PDF_TEMPLATE_FIELD).

Moves payroll-PDF-payslip templates out of pf-payroll's git-tracked JSON
files (`infrastructure/pdf_import/templates/<employer slug>/v<N>.json`) into
the database, per
`pf-payroll/docs/proposals/pdf-template-management-design-recommendation.md`.
Two normalized tables (not a JSONB `fields` column) so `concept_code` can
carry a real FK to `PAY_CONCEPT(code)` -- closing an integrity gap the old
hand-edited JSON format could not offer at all (a typo'd `concept_code`
there silently produced a field that never resolves, only discoverable at
`pdf-preview` time against a real PDF).

`is_active BOOLEAN NOT NULL DEFAULT TRUE` on `PAY_PDF_TEMPLATE` follows the
exact logical-delete precedent already established by `PAY_PENS_INST` /
`PAY_HLTH_INST` -- flipped by an `UPDATE`, never a row `DELETE`.

`employer_id` is a nullable, admin-only FK to `PAY_EMPLOYER` -- it is never
read by the actual PDF-matching code (`select_template()`), which keeps
using `employer_match_pattern` (a regex against the full raw PDF text)
exactly as today, since the printed employer name on a real PDF does not
necessarily match `PAY_EMPLOYER.name` verbatim.

Tables: PAY_PDF_TEMPLATE, PAY_PDF_TEMPLATE_FIELD.

Revision ID: 0009
Revises: 0008
Create Date: 2026-09-30
"""

from alembic import op

revision: str = "0009"
down_revision: str | None = "0008"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    """Create PAY_PDF_TEMPLATE and PAY_PDF_TEMPLATE_FIELD."""
    op.execute("""
        CREATE TABLE IF NOT EXISTS "PAY_PDF_TEMPLATE" (
            id                     BIGSERIAL     PRIMARY KEY,
            template_id            VARCHAR(80)   NOT NULL UNIQUE,
            employer_id            BIGINT        REFERENCES "PAY_EMPLOYER"(id),
            employer_name          VARCHAR(120)  NOT NULL,
            employer_match_pattern VARCHAR(500)  NOT NULL,
            version                INTEGER       NOT NULL DEFAULT 1 CHECK (version > 0),
            is_active              BOOLEAN       NOT NULL DEFAULT TRUE,
            created_at             TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
            updated_at             TIMESTAMPTZ   NOT NULL DEFAULT NOW()
        )
    """)
    op.execute("""
        CREATE TABLE IF NOT EXISTS "PAY_PDF_TEMPLATE_FIELD" (
            id                BIGSERIAL     PRIMARY KEY,
            template_id       BIGINT        NOT NULL
                REFERENCES "PAY_PDF_TEMPLATE"(id) ON DELETE CASCADE,
            pdf_label_pattern VARCHAR(500)  NOT NULL,
            concept_code      VARCHAR(40)   NOT NULL REFERENCES "PAY_CONCEPT"(code),
            kind              VARCHAR(20)   NOT NULL CHECK (kind IN ('income', 'discount')),
            confidence        NUMERIC(3,2)  NOT NULL DEFAULT 0.90
                CHECK (confidence BETWEEN 0 AND 1)
        )
    """)
    op.execute(
        'CREATE INDEX IF NOT EXISTS idx_pay_pdf_template_field_template_id '
        'ON "PAY_PDF_TEMPLATE_FIELD"(template_id)'
    )
    op.execute(
        'CREATE INDEX IF NOT EXISTS idx_pay_pdf_template_is_active '
        'ON "PAY_PDF_TEMPLATE"(is_active)'
    )


def downgrade() -> None:
    """Drop PAY_PDF_TEMPLATE_FIELD then PAY_PDF_TEMPLATE."""
    op.execute('DROP TABLE IF EXISTS "PAY_PDF_TEMPLATE_FIELD"')
    op.execute('DROP TABLE IF EXISTS "PAY_PDF_TEMPLATE"')
