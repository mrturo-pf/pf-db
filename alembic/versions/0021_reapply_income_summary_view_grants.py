"""Reapply runtime read access after provider role provisioning.

Revision ID: 0021
Revises: 0020
Create Date: 2026-10-26

Revision 0019 applied grants only to login roles that already had SELECT on
INC_PAYROLL at migration time. Provider role provisioning can happen after
that migration, so this revision repeats the least-privilege discovery once
all runtime grants are present.
"""

from __future__ import annotations

from alembic import op

revision: str = "0021"
down_revision: str | None = "0020"
branch_labels: str | None = None
depends_on: str | None = None

_SUMMARY_VIEW = "INC_MV_PAY_SUMMARY"
_RUNTIME_SOURCE_TABLE = "INC_PAYROLL"


def upgrade() -> None:
    """Grant the summary view to existing login roles allowed to read payrolls."""
    op.execute(
        f'''
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
                    'GRANT SELECT ON TABLE public."{_SUMMARY_VIEW}" TO %I',
                    role_name
                );
            END LOOP;
        END
        $$;
        '''
    )


def downgrade() -> None:
    """Leave the runtime grant in place when reverting the reapplication-only revision."""
