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

-- ============================================================
-- 1. Financial rates
-- ============================================================
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
    CREATE TYPE payroll_status AS ENUM ('projected', 'actual', 'reviewed');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE employment_contract_kind AS ENUM ('indefinite', 'fixed_term');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

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
    started_at                               DATE                       NOT NULL,
    ended_at                                 DATE,
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

CREATE TABLE IF NOT EXISTS "PAY_PERIOD" (
    id                       BIGSERIAL                NOT NULL PRIMARY KEY,
    employer_id              BIGINT                   NOT NULL REFERENCES "PAY_EMPLOYER"(id),
    period_year              SMALLINT                 NOT NULL,
    period_month             SMALLINT                 NOT NULL,
    payment_date             DATE                     NOT NULL,
    worked_days              SMALLINT                 NOT NULL DEFAULT 30,
    status                   payroll_status           NOT NULL DEFAULT 'projected',
    employment_contract_kind employment_contract_kind NOT NULL DEFAULT 'indefinite',
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
