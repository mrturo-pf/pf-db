"""Provide a least-privilege operation for refreshing the income summary view.

Revision ID: 0022
Revises: 0021
Create Date: 2026-10-28

Runtime roles may read the summary materialized view but cannot refresh it with
SELECT alone. The migration owner creates a locked-down SECURITY DEFINER
function and grants EXECUTE only to login roles already allowed to read payroll.
"""

from __future__ import annotations

from alembic import op

revision: str = "0022"
down_revision: str | None = "0021"
branch_labels: str | None = None
depends_on: str | None = None

_FUNCTION = "INC_FN_REFRESH_PAY_SUMMARY"
_SUMMARY_VIEW = "INC_MV_PAY_SUMMARY"
_RUNTIME_SOURCE_TABLE = "INC_PAYROLL"


def upgrade() -> None:
    """Create and grant the least-privilege summary refresh operation."""
    op.execute(
        f'''
        CREATE OR REPLACE FUNCTION public."{_FUNCTION}"()
        RETURNS void
        LANGUAGE sql
        SECURITY DEFINER
        SET search_path = pg_catalog, public
        AS $$
            REFRESH MATERIALIZED VIEW public."{_SUMMARY_VIEW}";
        $$;
        '''
    )
    op.execute(
        f'REVOKE ALL ON FUNCTION public."{_FUNCTION}"() FROM PUBLIC'
    )
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
                    'GRANT EXECUTE ON FUNCTION public."{_FUNCTION}"() TO %I',
                    role_name
                );
            END LOOP;
        END
        $$;
        '''
    )


def downgrade() -> None:
    """Remove runtime execution access and the refresh function."""
    op.execute(f'DROP FUNCTION IF EXISTS public."{_FUNCTION}"()')
