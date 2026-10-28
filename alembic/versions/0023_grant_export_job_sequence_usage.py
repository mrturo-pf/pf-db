"""Grant runtime sequence access required by RAT_EXPORT_JOB inserts.

Revision ID: 0023
Revises: 0022
Create Date: 2026-10-28

PostgreSQL does not include sequence privileges when a role receives INSERT on
an identity or BIGSERIAL-backed table. The pf-rates runtime role already has
least-privilege DML access to RAT_EXPORT_JOB, but creating a row also requires
USAGE/SELECT on its backing sequence.
"""

from __future__ import annotations

from alembic import op

revision: str = "0023"
down_revision: str | None = "0022"
branch_labels: str | None = None
depends_on: str | None = None

_SEQUENCE = "RAT_EXPORT_JOB_id_seq"
_EXPORT_JOB_TABLE = "RAT_EXPORT_JOB"


def _change_sequence_grant(statement: str, role_keyword: str) -> None:
    """Apply a sequence grant to existing roles that can insert export jobs."""
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
                      'public."{_EXPORT_JOB_TABLE}"',
                      'INSERT'
                  )
            LOOP
                EXECUTE format(
                    '{statement} ON SEQUENCE public."{_SEQUENCE}" {role_keyword} %I',
                    role_name
                );
            END LOOP;
        END
        $$;
        """
    )


def upgrade() -> None:
    """Grant only the sequence privileges needed for export-job inserts."""
    _change_sequence_grant("GRANT USAGE, SELECT", "TO")


def downgrade() -> None:
    """Revoke the sequence privileges granted by this revision."""
    _change_sequence_grant("REVOKE USAGE, SELECT", "FROM")
