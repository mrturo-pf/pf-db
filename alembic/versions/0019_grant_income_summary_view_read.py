"""Grant the runtime database user access to the income summary view.

Revision ID: 0019
Revises: 0018
Create Date: 2026-10-25

Migration 0017 recreated the materialized view after renaming the payroll
objects. PostgreSQL does not preserve grants when an object is recreated, so
roles allowed to read payrolls lost SELECT access to the new INC view. The
migration discovers those existing login roles instead of assuming a database
role name that may not exist on every PostgreSQL provider.
"""

from __future__ import annotations

from alembic import op

revision: str = "0019"
down_revision: str | None = "0018"
branch_labels: str | None = None
depends_on: str | None = None

_SUMMARY_VIEW = "INC_MV_PAY_SUMMARY"
_RUNTIME_SOURCE_TABLE = "INC_PAYROLL"


def _change_runtime_view_grant(statement: str, role_keyword: str) -> None:
    """Apply a view grant to login roles already allowed to read payrolls."""
    op.execute(
        f"""
        DO $$
        DECLARE
            role_name text;
        BEGIN
            FOR role_name IN
                SELECT rolname
                FROM pg_roles
                WHERE rolcanlogin
                  AND has_table_privilege(
                      rolname,
                      'public."{_RUNTIME_SOURCE_TABLE}"',
                      'SELECT'
                  )
            LOOP
                EXECUTE format(
                    '{statement} ON TABLE public."{_SUMMARY_VIEW}" {role_keyword} %I',
                    role_name
                );
            END LOOP;
        END
        $$;
        """
    )


def upgrade() -> None:
    """Restore read access for roles already allowed to read payrolls."""
    _change_runtime_view_grant("GRANT SELECT", "TO")


def downgrade() -> None:
    """Remove the restored view grant from those runtime-capable roles."""
    _change_runtime_view_grant("REVOKE SELECT", "FROM")
