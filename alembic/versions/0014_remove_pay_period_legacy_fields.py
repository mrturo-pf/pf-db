"""Remove legacy PAY_PERIOD workflow and contract-kind fields.

The application no longer exposes review/status or accepts contract kind from
payroll imports/API contracts. Contract kind is resolved from PAY_EMP_CONT.
PAY_EMPLOYER lifecycle dates remain temporarily for the next contract-source
migration; they are not removed until all lifecycle queries use PAY_EMP_CONT.

Revision ID: 0014
Revises: 0013
Create Date: 2026-10-03
"""

from alembic import op

revision: str = "0014"
down_revision: str | None = "0013"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    """Drop legacy period fields and their now-unused enum types."""
    op.execute('ALTER TABLE "PAY_PERIOD" DROP COLUMN IF EXISTS status')
    op.execute(
        'ALTER TABLE "PAY_PERIOD" '
        "DROP COLUMN IF EXISTS employment_contract_kind"
    )
    op.execute("DROP TYPE IF EXISTS payroll_status")
    op.execute("DROP TYPE IF EXISTS employment_contract_kind")


def downgrade() -> None:
    """Restore legacy fields and enum types with safe defaults."""
    op.execute(
        "CREATE TYPE payroll_status AS ENUM ('projected', 'actual', 'reviewed')"
    )
    op.execute(
        "CREATE TYPE employment_contract_kind AS ENUM ('indefinite', 'fixed_term')"
    )
    op.execute(
        'ALTER TABLE "PAY_PERIOD" ADD COLUMN IF NOT EXISTS status '
        "payroll_status NOT NULL DEFAULT 'projected'"
    )
    op.execute(
        'ALTER TABLE "PAY_PERIOD" ADD COLUMN IF NOT EXISTS employment_contract_kind '
        "employment_contract_kind NOT NULL DEFAULT 'indefinite'"
    )
