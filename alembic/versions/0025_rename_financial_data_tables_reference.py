"""Rename financial-data objects to the reference-data namespace.

Revision ID: 0025
Revises: 0024
Create Date: 2026-11-21

The service identity is now pf-svc-reference. The
migration preserves data and dependencies while applying the approved object
map:

- FID_RATE_UNIT -> REF_RATE_UNIT
- FID_RATE_VALUE -> REF_RATE_VALUE
- FID_ECON_INDEX -> REF_ECON_INDEX
- FID_TAX_BRCKT -> REF_TAX_BRCKT
- FID_EXPORT_JOB -> REF_EXPORT_JOB

Auxiliary sequences, constraints, indexes, and the export-job sequence grants
are renamed or re-applied so the resulting catalog is self-consistent.
"""

from __future__ import annotations

from alembic import op

revision: str = "0025"
down_revision: str | None = "0024"
branch_labels: str | None = None
depends_on: str | None = None

_TABLES = (
    ("FID_RATE_UNIT", "REF_RATE_UNIT"),
    ("FID_RATE_VALUE", "REF_RATE_VALUE"),
    ("FID_ECON_INDEX", "REF_ECON_INDEX"),
    ("FID_TAX_BRCKT", "REF_TAX_BRCKT"),
    ("FID_EXPORT_JOB", "REF_EXPORT_JOB"),
)

# PostgreSQL keeps these names when a table is renamed. Rename them explicitly
# rather than relying on server-version-specific implicit behavior.
_RENAMES = (
    ("FID_RATE_VALUE_id_seq", "REF_RATE_VALUE_id_seq"),
    ("FID_EXPORT_JOB_id_seq", "REF_EXPORT_JOB_id_seq"),
    ("fid_rate_unit_pkey", "ref_rate_unit_pkey"),
    ("fid_rate_value_pkey", "ref_rate_value_pkey"),
    (
        "fid_rate_value_currency_code_rate_date_key",
        "ref_rate_value_currency_code_rate_date_key",
    ),
    ("fid_econ_index_pkey", "ref_econ_index_pkey"),
    ("fid_econ_index_unique", "ref_econ_index_unique"),
    ("fid_tax_brckt_pkey", "ref_tax_brckt_pkey"),
    (
        "fid_tax_brckt_valid_from_lower_bound_utm_key",
        "ref_tax_brckt_valid_from_lower_bound_utm_key",
    ),
    ("fid_export_job_pkey", "ref_export_job_pkey"),
    ("chk_fid_export_job_status", "chk_ref_export_job_status"),
)


def _rename_relation(old_name: str, new_name: str) -> None:
    """Rename an existing sequence or index idempotently."""
    op.execute(
        f"""
        DO $$
        BEGIN
            IF to_regclass('public."{old_name}"') IS NOT NULL
               AND to_regclass('public."{new_name}"') IS NULL THEN
                EXECUTE 'ALTER ' ||
                    CASE WHEN '{old_name}' LIKE '%_seq' THEN 'SEQUENCE ' ELSE 'INDEX ' END ||
                    '"{old_name}" RENAME TO "{new_name}"';
            END IF;
        END
        $$;
        """
    )


def _rename_constraint(old_name: str, new_name: str) -> None:
    """Rename an existing table constraint idempotently."""
    op.execute(
        f"""
        DO $$
        DECLARE
            relation_name text;
        BEGIN
            SELECT conrelid::regclass::text
              INTO relation_name
              FROM pg_constraint
             WHERE conname = '{old_name}';
            IF relation_name IS NOT NULL AND NOT EXISTS (
                SELECT 1 FROM pg_constraint WHERE conname = '{new_name}'
            ) THEN
                EXECUTE format(
                    'ALTER TABLE %s RENAME CONSTRAINT %I TO %I',
                    relation_name, '{old_name}', '{new_name}'
                );
            END IF;
        END
        $$;
        """
    )


def _rename_index(old_name: str, new_name: str) -> None:
    """Rename an existing index idempotently."""
    op.execute(
        f"""
        DO $$
        BEGIN
            IF to_regclass('public."{old_name}"') IS NOT NULL
               AND to_regclass('public."{new_name}"') IS NULL THEN
                EXECUTE 'ALTER INDEX "{old_name}" RENAME TO "{new_name}"';
            END IF;
        END
        $$;
        """
    )


def _ensure_sequence_grants(sequence_name: str) -> None:
    """Preserve sequence grants for login roles after a sequence rename."""
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
                   AND has_sequence_privilege(
                       rolname, 'public."{sequence_name}"', 'USAGE'
                   )
            LOOP
                EXECUTE format(
                    'GRANT USAGE, SELECT ON SEQUENCE public."{sequence_name}" TO %I',
                    role_name
                );
            END LOOP;
        END
        $$;
        """
    )


def upgrade() -> None:
    """Rename financial-data tables and their catalog dependencies."""
    for old_name, new_name in _TABLES:
        op.rename_table(old_name, new_name)

    for old_name, new_name in _RENAMES:
        if old_name.startswith(("chk_", "uq_")) or old_name.endswith("_key"):
            _rename_constraint(old_name, new_name)
            if not old_name.startswith("chk_"):
                _rename_index(old_name, new_name)
        elif old_name.endswith("_pkey"):
            _rename_constraint(old_name, new_name)
            _rename_index(old_name, new_name)
        else:
            _rename_relation(old_name, new_name)

    _ensure_sequence_grants("REF_EXPORT_JOB_id_seq")


def downgrade() -> None:
    """Restore the FID_* tables and auxiliary object names."""
    for old_name, new_name in reversed(_RENAMES):
        if old_name.startswith(("chk_", "uq_")) or old_name.endswith("_key"):
            _rename_constraint(new_name, old_name)
            if not old_name.startswith("chk_"):
                _rename_index(new_name, old_name)
        elif old_name.endswith("_pkey"):
            _rename_constraint(new_name, old_name)
            _rename_index(new_name, old_name)
        else:
            _rename_relation(new_name, old_name)

    for old_name, new_name in reversed(_TABLES):
        op.rename_table(new_name, old_name)

    _ensure_sequence_grants("REF_EXPORT_JOB_id_seq")
