"""Add employer employment contracts and backfill historical periods.

The new contract table becomes the future source of employment dates and
contract-kind semantics. The old PAY_EMPLOYER/PAY_PERIOD columns remain in
this expand migration so the application can be adapted before the later
contract migration removes them.

Historical contract kind is copied into an explicit boolean. It is never
inferred from ended_at: an indefinite contract may have ended later.

Revision ID: 0013
Revises: 0012
Create Date: 2026-10-02
"""

from alembic import op

revision: str = "0013"
down_revision: str | None = "0012"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    """Create PAY_EMP_CONT and backfill unambiguous employer histories."""
    op.execute("CREATE EXTENSION IF NOT EXISTS btree_gist")
    op.execute("""
        CREATE TABLE IF NOT EXISTS "PAY_EMP_CONT" (
            id            BIGSERIAL PRIMARY KEY,
            employer_id   BIGINT NOT NULL REFERENCES "PAY_EMPLOYER"(id),
            started_at    DATE NOT NULL,
            ended_at      DATE,
            is_indefinite BOOLEAN NOT NULL,
            position      VARCHAR(120),
            CHECK (ended_at IS NULL OR ended_at >= started_at),
            CHECK (is_indefinite OR ended_at IS NOT NULL)
        )
    """)
    op.execute("""
        CREATE INDEX IF NOT EXISTS ix_pay_emp_cont_lookup
        ON "PAY_EMP_CONT" (employer_id, started_at, ended_at)
    """)
    op.execute(
        'ALTER TABLE "PAY_EMP_CONT" '
        "DROP CONSTRAINT IF EXISTS ex_pay_emp_cont_no_overlap"
    )
    op.execute("""
        ALTER TABLE "PAY_EMP_CONT"
        ADD CONSTRAINT ex_pay_emp_cont_no_overlap
        EXCLUDE USING gist (
            employer_id WITH =,
            daterange(
                started_at,
                COALESCE(ended_at, 'infinity'::date),
                '[]'
            ) WITH &&
        )
    """)
    op.execute("""
        DO $$
        DECLARE
            conflicting_employer BIGINT;
        BEGIN
            SELECT employer_id INTO conflicting_employer
            FROM "PAY_PERIOD"
            GROUP BY employer_id
            HAVING count(DISTINCT employment_contract_kind) > 1
            LIMIT 1;

            IF conflicting_employer IS NOT NULL THEN
                RAISE EXCEPTION
                    'Cannot backfill PAY_EMP_CONT: employer % has conflicting '
                    'employment_contract_kind values across PAY_PERIOD.',
                    conflicting_employer;
            END IF;
        END $$;
    """)
    op.execute("""
        INSERT INTO "PAY_EMP_CONT" (
            employer_id,
            started_at,
            ended_at,
            is_indefinite,
            position
        )
        SELECT history.employer_id,
               history.started_at,
               history.ended_at,
               history.is_indefinite,
               NULL
        FROM (
            SELECT
                e.id AS employer_id,
                e.started_at,
                e.ended_at,
                COALESCE(
                    bool_and(p.employment_contract_kind::text = 'indefinite'),
                    TRUE
                ) AS is_indefinite
            FROM "PAY_EMPLOYER" e
            LEFT JOIN "PAY_PERIOD" p ON p.employer_id = e.id
            GROUP BY e.id, e.started_at, e.ended_at
        ) history
        WHERE NOT EXISTS (
            SELECT 1
            FROM "PAY_EMP_CONT" existing
            WHERE existing.employer_id = history.employer_id
        )
    """)


def downgrade() -> None:
    """Drop the contract table and its supporting objects."""
    op.execute(
        'ALTER TABLE "PAY_EMP_CONT" '
        "DROP CONSTRAINT IF EXISTS ex_pay_emp_cont_no_overlap"
    )
    op.execute('DROP INDEX IF EXISTS ix_pay_emp_cont_lookup')
    op.execute('DROP TABLE IF EXISTS "PAY_EMP_CONT"')
