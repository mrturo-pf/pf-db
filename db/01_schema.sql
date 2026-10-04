-- ============================================================
-- Combined idempotent DDL for the PF database.
-- Owned by pf-db; do NOT run this file directly in production.
-- Use Alembic migrations instead: make migrate
--
-- Table names use the service-prefix convention (RAT_ / PAY_), all
-- UPPERCASE, max 14 chars. Because these identifiers contain uppercase
-- letters, PostgreSQL requires them to be double-quoted EVERYWHERE they
-- are referenced (CREATE TABLE, REFERENCES, indexes, views) — otherwise
-- PostgreSQL folds the unquoted identifier to lowercase and it will not
-- match the actual (quoted, mixed-case) table. See alembic/versions/
-- 0003_rename_tables_service_prefix.py for the migration that hit this
-- exact bug.
--
-- Sections:
--   1. Financial rates     (financial rates domain)
--   2. Reference data      (payroll domain)
--   3. Payroll core        (payroll domain)
--   4. Analytics           (payroll domain)
-- ============================================================

CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE TABLE IF NOT EXISTS "RAT_CURRENCY" (
    code      CHAR(3)     PRIMARY KEY,
    name      VARCHAR(60) NOT NULL,
    is_fiat   BOOLEAN     NOT NULL DEFAULT TRUE,
    unit_kind VARCHAR(20) NOT NULL DEFAULT 'currency'
        CHECK (unit_kind IN ('currency', 'index_unit'))
);

CREATE TABLE IF NOT EXISTS "RAT_EXCH_RATE" (
    id            BIGSERIAL     PRIMARY KEY,
    currency_code CHAR(3)       NOT NULL REFERENCES "RAT_CURRENCY"(code),
    rate_date     DATE          NOT NULL,
    value_clp     NUMERIC(18,6) NOT NULL CHECK (value_clp > 0),
    source        VARCHAR(40)   NOT NULL DEFAULT 'manual',
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    UNIQUE (currency_code, rate_date)
);

CREATE TABLE IF NOT EXISTS "RAT_ECON_INDEX" (
    id             BIGSERIAL     PRIMARY KEY,
    code           VARCHAR(20)   NOT NULL,
    period_year    SMALLINT      NOT NULL CHECK (period_year BETWEEN 1990 AND 2100),
    period_month   SMALLINT      NOT NULL CHECK (period_month BETWEEN 1 AND 12),
    index_value    NUMERIC(12,6) NOT NULL CHECK (index_value > 0),
    monthly_change NUMERIC(7,4),
    yearly_change  NUMERIC(7,4),
    base_period    VARCHAR(10)   NOT NULL DEFAULT 'DIC-2018',
    source         VARCHAR(40)   NOT NULL DEFAULT 'manual',
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_economic_indices UNIQUE (code, period_year, period_month)
);

CREATE TABLE IF NOT EXISTS "RAT_TAX_BRCKT" (
    id              BIGSERIAL     PRIMARY KEY,
    valid_from      DATE          NOT NULL,
    valid_to        DATE,
    lower_bound_utm NUMERIC(10,4) NOT NULL CHECK (lower_bound_utm >= 0),
    upper_bound_utm NUMERIC(10,4),
    marginal_rate   NUMERIC(8,6)  NOT NULL CHECK (marginal_rate >= 0 AND marginal_rate <= 1),
    rebate_utm      NUMERIC(10,4) NOT NULL DEFAULT 0 CHECK (rebate_utm >= 0),
    CONSTRAINT chk_income_tax_bracket_bounds
        CHECK (upper_bound_utm IS NULL OR upper_bound_utm > lower_bound_utm),
    UNIQUE (valid_from, lower_bound_utm)
);

CREATE TABLE IF NOT EXISTS "RAT_EXPORT_JOB" (
    id                   BIGSERIAL     PRIMARY KEY,
    status               VARCHAR(20)   NOT NULL DEFAULT 'pending'
        CONSTRAINT chk_rat_export_job_status
        CHECK (status IN ('pending', 'running', 'succeeded', 'failed', 'cancelled')),
    lookback_days        INTEGER       NOT NULL CHECK (lookback_days >= 0),
    forward_days         INTEGER       NOT NULL CHECK (forward_days >= 0),
    rows_written         INTEGER,
    file_id              VARCHAR(200),
    error_message        TEXT,
    cancel_requested_at  TIMESTAMPTZ,
    total_items          INTEGER       CHECK (total_items IS NULL OR total_items >= 0),
    processed_items      INTEGER       NOT NULL DEFAULT 0 CHECK (processed_items >= 0),
    created_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rat_export_job_status_created
    ON "RAT_EXPORT_JOB" (status, created_at);

-- ============================================================
-- 2. Reference data — pension & health institutions
-- ============================================================
DO $$ BEGIN
    CREATE TYPE health_institution_kind AS ENUM ('fonasa', 'isapre');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE contribution_cap_type AS ENUM ('pension_health', 'unemployment');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE complementary_insurance_cost_type
        AS ENUM ('fixed_clp', 'fixed_uf', 'variable_percentage');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS "PAY_PENS_INST" (
    id             BIGSERIAL    PRIMARY KEY,
    code           VARCHAR(40)  NOT NULL UNIQUE,
    name           VARCHAR(120) NOT NULL,
    mandatory_rate NUMERIC(6,4) NOT NULL DEFAULT 0.10,
    is_active      BOOLEAN      NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS "PAY_HLTH_INST" (
    id             BIGSERIAL               PRIMARY KEY,
    code           VARCHAR(40)             NOT NULL UNIQUE,
    name           VARCHAR(120)            NOT NULL,
    kind           health_institution_kind NOT NULL,
    mandatory_rate NUMERIC(6,4)            NOT NULL DEFAULT 0.07,
    is_active      BOOLEAN                 NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS "PAY_PENS_PLAN" (
    id              BIGSERIAL    PRIMARY KEY,
    institution_id  BIGINT       NOT NULL REFERENCES "PAY_PENS_INST"(id),
    valid_from      DATE         NOT NULL,
    valid_to        DATE,
    additional_rate NUMERIC(6,4) NOT NULL DEFAULT 0 CHECK (additional_rate >= 0),
    CONSTRAINT chk_pension_plan_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS "PAY_HLTH_PLAN" (
    id             BIGSERIAL     PRIMARY KEY,
    institution_id BIGINT        NOT NULL REFERENCES "PAY_HLTH_INST"(id),
    valid_from     DATE          NOT NULL,
    valid_to       DATE,
    plan_name      VARCHAR(120),
    contracted_uf  NUMERIC(10,4) NOT NULL DEFAULT 0 CHECK (contracted_uf >= 0),
    CONSTRAINT chk_health_plan_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS "PAY_CNTRB_CAP" (
    id         BIGSERIAL             PRIMARY KEY,
    cap_type   contribution_cap_type NOT NULL,
    valid_from DATE                  NOT NULL,
    valid_to   DATE,
    value_uf   NUMERIC(10,4)         NOT NULL CHECK (value_uf > 0),
    UNIQUE (cap_type, valid_from)
);

CREATE TABLE IF NOT EXISTS "PAY_COMP_PROV" (
    id   BIGSERIAL    PRIMARY KEY,
    name VARCHAR(120) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS "PAY_COMP_PLAN" (
    id            BIGSERIAL                         PRIMARY KEY,
    provider_id   BIGINT                            NOT NULL
        REFERENCES "PAY_COMP_PROV"(id),
    name          VARCHAR(120)                      NOT NULL,
    cost_type     complementary_insurance_cost_type NOT NULL,
    cost_value    NUMERIC(12,4)                     NOT NULL CHECK (cost_value >= 0),
    cost_currency CHAR(3)                           NOT NULL DEFAULT 'CLP',
    valid_from    DATE                              NOT NULL,
    valid_to      DATE,
    CONSTRAINT chk_complementary_plan_dates
        CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

-- ============================================================
-- 3. Payroll core
-- ============================================================
DO $$ BEGIN
    CREATE TYPE employer_payment_date_rule AS ENUM (
        'last_business_day_of_month',
        'fixed_day_of_month',
        'calendar_days_before_end_of_month'
    );
EXCEPTION WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE employer_fixed_day_roll
        AS ENUM ('previous_business_day', 'next_business_day');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS "PAY_EMPLOYER" (
    id                                       BIGSERIAL                  PRIMARY KEY,
    name                                     VARCHAR(120)               NOT NULL UNIQUE,
    tax_id                                   VARCHAR(32),
    country_code                             CHAR(2)                    NOT NULL DEFAULT 'CL',
    first_increase_period_year               SMALLINT
        CHECK (first_increase_period_year BETWEEN 1990 AND 2100),
    first_increase_period_month              SMALLINT
        CHECK (first_increase_period_month BETWEEN 1 AND 12),
    increase_frequency                       SMALLINT
        CHECK (increase_frequency > 0),
    payment_date_rule                        employer_payment_date_rule NOT NULL
        DEFAULT 'last_business_day_of_month',
    payment_month_offset                     SMALLINT                   NOT NULL DEFAULT 0
        CHECK (payment_month_offset >= 0),
    payment_day_of_month                     SMALLINT
        CHECK (payment_day_of_month BETWEEN 1 AND 31),
    payment_business_day_offset              SMALLINT                   NOT NULL DEFAULT 0
        CHECK (payment_business_day_offset >= 0),
    payment_calendar_day_offset              SMALLINT                   NOT NULL DEFAULT 0
        CHECK (payment_calendar_day_offset >= 0),
    payment_effective_on_processing_next_day BOOLEAN                    NOT NULL DEFAULT FALSE,
    payment_fixed_day_roll                   employer_fixed_day_roll    NOT NULL
        DEFAULT 'previous_business_day'
);

CREATE TABLE IF NOT EXISTS "PAY_EMP_CONT" (
    id            BIGSERIAL PRIMARY KEY,
    employer_id   BIGINT NOT NULL REFERENCES "PAY_EMPLOYER"(id),
    started_at    DATE NOT NULL,
    ended_at      DATE,
    is_indefinite BOOLEAN NOT NULL,
    position      VARCHAR(120),
    CHECK (ended_at IS NULL OR ended_at >= started_at),
    CHECK (is_indefinite OR ended_at IS NOT NULL),
    EXCLUDE USING gist (
        employer_id WITH =,
        daterange(
            started_at,
            COALESCE(ended_at, 'infinity'::date),
            '[]'
        ) WITH &&
    )
);

CREATE INDEX IF NOT EXISTS ix_pay_emp_cont_lookup
    ON "PAY_EMP_CONT" (employer_id, started_at, ended_at);
CREATE TABLE IF NOT EXISTS "PAY_PERIOD" (
    id                       BIGSERIAL                NOT NULL PRIMARY KEY,
    employer_id              BIGINT                   NOT NULL REFERENCES "PAY_EMPLOYER"(id),
    period_year              SMALLINT                 NOT NULL,
    period_month             SMALLINT                 NOT NULL,
    payment_date             DATE                     NOT NULL,
    worked_days              SMALLINT                 NOT NULL DEFAULT 30,
    declared_net_pay_clp     NUMERIC(18,2),
    expected_net_pay_clp     NUMERIC(18,2),
    net_pay_difference_clp   NUMERIC(18,2),
    pension_plan_id          BIGINT                   REFERENCES "PAY_PENS_PLAN"(id),
    UNIQUE (employer_id, period_year, period_month)
);


CREATE TABLE IF NOT EXISTS "PAY_PRD_HLTH" (
    period_id      BIGINT NOT NULL REFERENCES "PAY_PERIOD"(id) ON DELETE CASCADE,
    health_plan_id BIGINT NOT NULL REFERENCES "PAY_HLTH_PLAN"(id),
    PRIMARY KEY (period_id, health_plan_id)
);

CREATE TABLE IF NOT EXISTS "PAY_PRD_COMP" (
    period_id                       BIGINT NOT NULL
        REFERENCES "PAY_PERIOD"(id) ON DELETE CASCADE,
    complementary_insurance_plan_id BIGINT NOT NULL
        REFERENCES "PAY_COMP_PLAN"(id),
    PRIMARY KEY (period_id, complementary_insurance_plan_id)
);

CREATE TABLE IF NOT EXISTS "PAY_CONCEPT" (
    id         BIGSERIAL    PRIMARY KEY,
    code       VARCHAR(40)  NOT NULL UNIQUE,
    name       VARCHAR(120) NOT NULL,
    kind       VARCHAR(20)  NOT NULL CHECK (kind IN ('income', 'discount')),
    is_taxable BOOLEAN      NOT NULL DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS "PAY_ITEM" (
    id         BIGSERIAL     PRIMARY KEY,
    period_id  BIGINT        NOT NULL REFERENCES "PAY_PERIOD"(id) ON DELETE CASCADE,
    concept_id BIGINT        NOT NULL REFERENCES "PAY_CONCEPT"(id),
    amount_clp NUMERIC(18,2) NOT NULL,
    notes      TEXT,
    created_at TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payroll_items_period_id  ON "PAY_ITEM"(period_id);
CREATE INDEX IF NOT EXISTS idx_payroll_items_concept_id ON "PAY_ITEM"(concept_id);

-- PDF payslip templates (employer-specific raw_label -> concept_code mapping).
-- Replaces pf-payroll's former git-tracked JSON files -- see
-- pf-payroll/docs/proposals/pdf-template-management-recommendation.md.
-- employer_id is required: a template may only be created for an employer
-- that already has a PAY_EMPLOYER row (i.e. after its first payroll import
-- has run at least once). There is deliberately no employer_name column --
-- it used to be a literal-override fallback for when employer_id was NULL,
-- but that case can no longer happen. The display name is always resolved
-- fresh from PAY_EMPLOYER.name via employer_id at read time, never copied
-- into this table. See alembic/versions/0012_pdf_template_employer_id_required.py.
CREATE TABLE IF NOT EXISTS "PAY_PDF_TEMPLATE" (
    id                     BIGSERIAL     PRIMARY KEY,
    template_id            VARCHAR(80)   NOT NULL UNIQUE,
    employer_id            BIGINT        NOT NULL REFERENCES "PAY_EMPLOYER"(id),
    employer_match_pattern VARCHAR(500)  NOT NULL,
    version                INTEGER       NOT NULL DEFAULT 1 CHECK (version > 0),
    is_active              BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at             TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- kind is deliberately NOT a column here -- it would duplicate PAY_CONCEPT.kind
-- with no referential integrity tying the two copies together. The
-- application layer always resolves kind from PAY_CONCEPT at read time; see
-- migration 0010.
-- concept_id (not concept_code): every other table referencing PAY_CONCEPT
-- does so by its surrogate id (see PAY_ITEM.concept_id above) -- concept_code
-- was an unintentional inconsistency, fixed in migration 0011. concept_code
-- remains the business-facing identifier at the application layer (requests,
-- responses, CONCEPT_MAP, the PDF-matching engine); only this storage column
-- changed, resolved at the repository boundary.
CREATE TABLE IF NOT EXISTS "PAY_PDF_TEMPLATE_FIELD" (
    id                BIGSERIAL     PRIMARY KEY,
    template_id       BIGINT        NOT NULL
        REFERENCES "PAY_PDF_TEMPLATE"(id) ON DELETE CASCADE,
    pdf_label_pattern VARCHAR(500)  NOT NULL,
    concept_id        BIGINT        NOT NULL REFERENCES "PAY_CONCEPT"(id),
    confidence        NUMERIC(3,2)  NOT NULL DEFAULT 0.90 CHECK (confidence BETWEEN 0 AND 1)
);

CREATE INDEX IF NOT EXISTS idx_pay_pdf_template_field_concept_id
    ON "PAY_PDF_TEMPLATE_FIELD"(concept_id);
CREATE INDEX IF NOT EXISTS idx_pay_pdf_template_field_template_id
    ON "PAY_PDF_TEMPLATE_FIELD"(template_id);
CREATE INDEX IF NOT EXISTS idx_pay_pdf_template_is_active ON "PAY_PDF_TEMPLATE"(is_active);

-- ============================================================
-- 4. Analytics
-- ============================================================
CREATE MATERIALIZED VIEW IF NOT EXISTS "PAY_MV_SUMARY" AS
SELECT
    p.id           AS period_id,
    p.employer_id,
    p.period_year,
    p.period_month,
    p.payment_date,
    SUM(CASE WHEN c.kind = 'income' AND c.is_taxable THEN i.amount_clp ELSE 0 END)
        AS taxable_income_clp,
    SUM(CASE WHEN c.kind = 'income'   THEN i.amount_clp ELSE 0 END) AS gross_income_clp,
    SUM(CASE WHEN c.kind = 'discount' THEN i.amount_clp ELSE 0 END) AS total_discounts_clp,
    SUM(CASE WHEN c.kind = 'income'   THEN i.amount_clp ELSE 0 END) -
    SUM(CASE WHEN c.kind = 'discount' THEN i.amount_clp ELSE 0 END) AS net_pay_clp
FROM "PAY_PERIOD"  p
JOIN "PAY_ITEM"    i ON i.period_id  = p.id
JOIN "PAY_CONCEPT" c ON c.id = i.concept_id
GROUP BY p.id;

CREATE UNIQUE INDEX IF NOT EXISTS idx_pay_mv_sumary_period ON "PAY_MV_SUMARY"(period_id);
