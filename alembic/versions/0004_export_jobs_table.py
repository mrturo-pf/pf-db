"""Add export jobs tracking table for async CSV exports.

Backs pf-rates' `POST /exchange-rates/export {"async": true}` flow: the
request creates a row here and returns immediately, a background task
updates it as it progresses, and `GET /exchange-rates/export/jobs/{id}`
reads it back. Living in the DB (not in-process memory) is required
because Cloud Run can run multiple instances and scale to zero -- any
instance must be able to answer a status check for a job started by a
different (or since-recycled) instance.

Table: RAT_EXPORT_JOB.

Revision ID: 0004
Revises: 0003
Create Date: 2026-09-14
"""

from alembic import op

revision: str = "0004"
down_revision: str | None = "0003"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    """Create the RAT_EXPORT_JOB table."""
    op.execute("""
        CREATE TABLE IF NOT EXISTS "RAT_EXPORT_JOB" (
            id             BIGSERIAL     PRIMARY KEY,
            status         VARCHAR(20)   NOT NULL DEFAULT 'pending'
                CONSTRAINT chk_rat_export_job_status
                CHECK (status IN ('pending', 'running', 'succeeded', 'failed')),
            lookback_days  INTEGER       NOT NULL CHECK (lookback_days >= 0),
            forward_days   INTEGER       NOT NULL CHECK (forward_days >= 0),
            rows_written   INTEGER,
            file_id        VARCHAR(200),
            error_message  TEXT,
            created_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
            updated_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW()
        )
    """)


def downgrade() -> None:
    """Drop the RAT_EXPORT_JOB table."""
    op.execute('DROP TABLE IF EXISTS "RAT_EXPORT_JOB"')
