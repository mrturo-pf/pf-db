"""Grant the runtime database user access to the income summary view.

Revision ID: 0019
Revises: 0018
Create Date: 2026-10-25

Migration 0017 recreated the materialized view after renaming the payroll
objects. PostgreSQL does not preserve grants when an object is recreated, so
the runtime user lost SELECT access to the new INC view.
"""

from __future__ import annotations

from alembic import op

revision: str = "0019"
down_revision: str | None = "0018"
branch_labels: str | None = None
depends_on: str | None = None

_RUNTIME_ROLE = "pf_db"
_SUMMARY_VIEW = "INC_MV_PAY_SUMMARY"


def upgrade() -> None:
    """Restore read access required by payroll spreadsheet exports and queries."""
    op.execute(f'GRANT SELECT ON TABLE "{_SUMMARY_VIEW}" TO "{_RUNTIME_ROLE}"')


def downgrade() -> None:
    """Remove the runtime user's read access when reverting this migration."""
    op.execute(f'REVOKE SELECT ON TABLE "{_SUMMARY_VIEW}" FROM "{_RUNTIME_ROLE}"')
