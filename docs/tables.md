# Tables Reference

Complete documentation of the 20 tables managed by pf-db, including ownership, relationships, and connection details.

**Source of truth:** every schema block below is copied verbatim from
[`db/01_schema.sql`](../db/01_schema.sql). If this file and `01_schema.sql` ever
disagree, `01_schema.sql` wins -- treat that as a bug in this doc, not the other way
around.

## Overview

pf-db manages **20 tables** across two domains:
- **Financial rates:** 5 tables (owned by pf-rates)
- **Payroll:** 15 tables + 1 materialized view (owned by pf-payroll)

Payroll models a **single person's own payroll across one or more employers** over
time, not a multi-employee company payroll system -- `PAY_PERIOD` has no
employee-level column at all, only `employer_id` + `period_year`/`period_month`.

## Table ownership

Ownership means: only the microservices that own a domain **write** to those tables. Any microservice may **read** any table.

| Tables | Domain | Owner | Access pattern |
|---|---|---|---|
| `RAT_CURRENCY`, `RAT_EXCH_RATE`, `RAT_ECON_INDEX`, `RAT_TAX_BRCKT`, `RAT_EXPORT_JOB` | Financial rates | [pf-rates](../pf-rates) | pf-payroll reads via HTTP API (never direct SQL) |
| All others (15 tables + 1 view) | Payroll | [pf-payroll](../pf-payroll) | Exclusive write access |

## Connection string

**Local:**
```
postgresql+asyncpg://pf_db:pf_db@localhost:5432/pf_db
```

**Production:**
Set via `PF_DATABASE_URL` in Secret Manager, injected into Cloud Run services at runtime.

Each consuming microservice sets its own env-var prefix for the connection string.

## Seed files

Three seed files layer on top of `01_schema.sql`, each with a different purpose --
see [`development.md`](development.md) for the Make targets that run them:

| File | Purpose | Idempotency |
|---|---|---|
| `db/02_seed_base.sql` | Authoritative catalog rows (currencies, institutions, contribution caps, concepts) safe for **every** environment. Upserts, then deletes any row not in the file -- a FK-referenced row about to be deleted rolls back the whole transaction instead of silently orphaning children. | Full upsert + prune |
| `db/03_seed_test.sql` | Non-production fixtures: one zero-value pension/health plan per institution (so tests have *something* to reference), plus a few fake complementary-insurance providers/plans. | Insert-if-not-exists, no prune |
| `db/04_seed_real.sql` | Real/production-like data: actual AFP PlanVital commission rate, actual ESENCIAL health plan tiers (Base/GES/Adicionales), real historical contribution caps by year, and three real employers (`DALT-CONSULTORES`, `CLINICA-ALEMANA`, `WALMART-CHILE`). | Insert-if-not-exists / upsert, no prune |

## Financial rates tables (5 tables)

### RAT_CURRENCY

Supported currencies **and index units** (UF/UTM are not fiat currencies but share
this table, distinguished by `unit_kind`).

**Owner:** pf-rates

**Schema:**
```sql
CREATE TABLE "RAT_CURRENCY" (
    code      CHAR(3)     PRIMARY KEY,
    name      VARCHAR(60) NOT NULL,
    is_fiat   BOOLEAN     NOT NULL DEFAULT TRUE,
    unit_kind VARCHAR(20) NOT NULL DEFAULT 'currency'
        CHECK (unit_kind IN ('currency', 'index_unit'))
);
```

**Sample data** (`db/02_seed_base.sql`, the full/authoritative set -- rows not in this
file get deleted):
| code | name | is_fiat | unit_kind |
|---|---|---|---|
| CLP | Peso chileno | true | currency |
| USD | US Dollar | true | currency |
| EUR | Euro | true | currency |
| UF | Unidad de Fomento | false | index_unit |
| UTM | Unidad Tributaria Mensual | false | index_unit |

**Seed:** `db/02_seed_base.sql`

---

### RAT_EXCH_RATE

Historical exchange rates (CLP value for foreign currencies and index units).

**Owner:** pf-rates

**Schema:**
```sql
CREATE TABLE "RAT_EXCH_RATE" (
    id            BIGSERIAL     PRIMARY KEY,
    currency_code CHAR(3)       NOT NULL REFERENCES "RAT_CURRENCY"(code),
    rate_date     DATE          NOT NULL,
    value_clp     NUMERIC(18,6) NOT NULL CHECK (value_clp > 0),
    source        VARCHAR(40)   NOT NULL DEFAULT 'manual',
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    UNIQUE (currency_code, rate_date)
);
```

**No seed file** -- populated at runtime by `POST /exchange-rates/refresh` and the
startup background sync (SII for `UF`/`UTM`, `mindicador.cl` fallback, optional BCCh
credentials for `USD`/`EUR`). `source` records which provider resolved that row.

**Source:** Mindicador.cl, Banco Central de Chile (BCCh), SII

---

### RAT_ECON_INDEX

Economic indices (`UF`, `UTM`, `IPC_CL`) with monthly values and period-over-period
change rates.

**Owner:** pf-rates

**Schema:**
```sql
CREATE TABLE "RAT_ECON_INDEX" (
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
```

**No seed file** -- populated at runtime by `POST /economic-indices/refresh` and the
startup background sync.

**Source:** Banco Central de Chile (BCCh), INE (`IPC_CL`)

**Note:** UF may include pre-published future values (BCCh publishes roughly a month ahead).

---

### RAT_TAX_BRCKT

Income tax brackets for Chilean monthly withholding, as **valid-date ranges** rather
than one row per calendar year.

**Owner:** pf-rates

**Schema:**
```sql
CREATE TABLE "RAT_TAX_BRCKT" (
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
```

**No seed file** -- populated at runtime by `POST /income-tax-brackets/refresh` (SII).

---

### RAT_EXPORT_JOB

Async CSV export job tracking (`POST /exports/financial-data {"async": true}`),
including cooperative cancellation
(`POST /exports/jobs/{job_id}/stop` and the bulk `POST /exports/jobs/stop`).

**Owner:** pf-rates

**Schema:**
```sql
CREATE TABLE "RAT_EXPORT_JOB" (
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

CREATE INDEX idx_rat_export_job_status_created ON "RAT_EXPORT_JOB" (status, created_at);
```

`export_kind` (added in migration `0007`, dropped in migration `0008`) used to
distinguish which endpoint produced the job -- `'exchange_rates'` for the
now-removed `POST /exchange-rates/export`, or `'combined'` for
`POST /exports/financial-data`. Once the exchange-rates-only endpoint was retired,
`POST /exports/financial-data` became the only export trigger left, so the
discriminator no longer distinguished between anything and was removed.

`cancel_requested_at` (added in migration `0005`) is set once a stop is requested and
polled cooperatively by the running export loop -- pf-rates has no message queue in
front of it (Cloud Run + BackgroundTasks only, by deliberate cost choice), so a job
stops itself at its next checkpoint rather than being force-killed instantly from
another instance.

`total_items`/`processed_items` (added in migration `0006`) track progress while a
job is `'running'`: `total_items` is the number of (currency, date) pairs the export
loop will visit, resolved once at the start of execution (`NULL` before then);
`processed_items` increases as the loop advances. `GET /exports/jobs` and the
single-job GET derive a `progress_percent` from these two columns rather than storing
it directly -- one source of truth, no risk of the stored percentage drifting from
the raw counts.

**No seed file** -- purely operational/runtime state, created by each export trigger.

---

## Payroll tables (15 tables + 1 view)

### PAY_PENS_INST

AFP (pension fund administrator) institutions.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_PENS_INST" (
    id             BIGSERIAL    PRIMARY KEY,
    code           VARCHAR(40)  NOT NULL UNIQUE,
    name           VARCHAR(120) NOT NULL,
    mandatory_rate NUMERIC(6,4) NOT NULL DEFAULT 0.10,
    is_active      BOOLEAN      NOT NULL DEFAULT TRUE
);
```

**Sample data** (`db/02_seed_base.sql`, the full/authoritative set):
| code | name | mandatory_rate | is_active |
|---|---|---|---|
| AFP_CAPITAL | AFP Capital | 0.10 | false |
| AFP_CUPRUM | AFP Cuprum | 0.10 | false |
| AFP_HABITAT | AFP Habitat | 0.10 | false |
| AFP_MODELO | AFP Modelo | 0.10 | false |
| AFP_PLANVITAL | AFP PlanVital | 0.10 | **true** |
| AFP_PROVIDA | AFP ProVida | 0.10 | false |
| AFP_UNO | AFP Uno | 0.10 | false |

Only `AFP_PLANVITAL` is `is_active`, since it's the only one with a real assigned
plan today (see `PAY_PENS_PLAN` below) -- `is_active` gates whether reference-data
endpoints/lookups surface an institution by default, not whether the row exists.

**Seed:** `db/02_seed_base.sql`

---

### PAY_HLTH_INST

Health institutions (Fonasa + Isapres).

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_HLTH_INST" (
    id             BIGSERIAL               PRIMARY KEY,
    code           VARCHAR(40)             NOT NULL UNIQUE,
    name           VARCHAR(120)            NOT NULL,
    kind           health_institution_kind NOT NULL,
    mandatory_rate NUMERIC(6,4)            NOT NULL DEFAULT 0.07,
    is_active      BOOLEAN                 NOT NULL DEFAULT TRUE
);
```

Where `health_institution_kind` is `ENUM ('fonasa', 'isapre')`.

**Sample data** (`db/02_seed_base.sql`, the full/authoritative set):
| code | name | kind | is_active |
|---|---|---|---|
| FONASA | Fonasa | fonasa | false |
| BANMEDICA | Banmedica | isapre | false |
| COLMENA | Colmena | isapre | false |
| CONSALUD | Consalud | isapre | false |
| CRUZBLANCA | CruzBlanca | isapre | false |
| ESENCIAL | Esencial | isapre | **true** |
| NUEVA_MASVIDA | Nueva Masvida | isapre | false |
| VIDA_TRES | Vida Tres | isapre | false |

**Seed:** `db/02_seed_base.sql`

---

### PAY_PENS_PLAN

Pension plan **tiers**, one or more per institution, each valid over a date range
with its own `additional_rate` (the voluntary/commission add-on on top of the
institution's `mandatory_rate`).

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_PENS_PLAN" (
    id              BIGSERIAL    PRIMARY KEY,
    institution_id  BIGINT       NOT NULL REFERENCES "PAY_PENS_INST"(id),
    valid_from      DATE         NOT NULL,
    valid_to        DATE,
    additional_rate NUMERIC(6,4) NOT NULL DEFAULT 0 CHECK (additional_rate >= 0),
    CONSTRAINT chk_pension_plan_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);
```

**Sample data:**
- `db/03_seed_test.sql`: one `additional_rate = 0`, `valid_from = 2026-01-01`,
  open-ended plan per institution (a placeholder so tests always have *something*
  to reference).
- `db/04_seed_real.sql`: the real `AFP_PLANVITAL` plan, `additional_rate = 0.0116`,
  `valid_from = 2024-11-01`, open-ended.

**Seed:** `db/03_seed_test.sql`, `db/04_seed_real.sql`

---

### PAY_HLTH_PLAN

Health plan **tiers**, one or more per institution, each valid over a date range
with its own `contracted_uf`. A single payroll period is typically linked to
*multiple* rows here at once via `PAY_PRD_HLTH` (e.g. `Base` + `GES` + `Adicionales`
tiers for the same Isapre) -- see
[`health-additional-uf-mismatch.md`](investigations/health-additional-uf-mismatch.md)
for the domain logic (`prorated_contracted_uf()` /
`prorated_additional_amount_clp()` in pf-payroll's
`domain/health_plan_proration.py`) that prorates each tier by its day-overlap with
the period when a plan starts or ends mid-month.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_HLTH_PLAN" (
    id             BIGSERIAL     PRIMARY KEY,
    institution_id BIGINT        NOT NULL REFERENCES "PAY_HLTH_INST"(id),
    valid_from     DATE          NOT NULL,
    valid_to       DATE,
    plan_name      VARCHAR(120),
    contracted_uf  NUMERIC(10,4) NOT NULL DEFAULT 0 CHECK (contracted_uf >= 0),
    CONSTRAINT chk_health_plan_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);
```

**Sample data:**
- `db/03_seed_test.sql`: one `plan_name = 'Base'`, `contracted_uf = 0`,
  `valid_from = 2026-01-01`, open-ended plan per institution (placeholder).
- `db/04_seed_real.sql`: three real `ESENCIAL` tiers, all `valid_from = 2024-11-01`,
  open-ended: `Base` (5.42 UF), `GES` (0.91 UF), `Adicionales` (0.79 UF). In
  practice this table also accumulates manually-inserted rows for mid-month plan
  changes (non-contiguous `valid_from`/`valid_to` per tier) -- see the
  investigation doc linked above for a real example.

**Seed:** `db/03_seed_test.sql`, `db/04_seed_real.sql`

---

### PAY_CNTRB_CAP

Monthly contribution caps (UF-based), one row per `cap_type` per valid-date range.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_CNTRB_CAP" (
    id         BIGSERIAL             PRIMARY KEY,
    cap_type   contribution_cap_type NOT NULL,
    valid_from DATE                  NOT NULL,
    valid_to   DATE,
    value_uf   NUMERIC(10,4)         NOT NULL CHECK (value_uf > 0),
    UNIQUE (cap_type, valid_from)
);
```

Where `contribution_cap_type` is `ENUM ('pension_health', 'unemployment')`.

**Sample data:**
- `db/02_seed_base.sql` (placeholder, superseded by real historical tiers below):
  `pension_health` / `unemployment`, both `valid_from = 2018-01-01`, open-ended,
  `90.06` / `135.09` UF respectively.
- `db/04_seed_real.sql` (real historical `pension_health` tiers):

  | valid_from | valid_to | value_uf |
  |---|---|---|
  | 2024-01-01 | 2024-12-31 | 84.30 |
  | 2025-01-01 | 2025-12-31 | 87.80 |
  | 2026-01-01 | 2026-01-31 | 89.90 |
  | 2026-02-01 | (open) | 90.00 |

**Seed:** `db/02_seed_base.sql`, `db/04_seed_real.sql`

**Note:** SII/the regulator republishes these caps periodically (roughly yearly) --
they are not "monthly" in the sense of one row per month, just one row per
effective-date change.

---

### PAY_COMP_PROV

Complementary (voluntary) insurance providers.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_COMP_PROV" (
    id   BIGSERIAL    PRIMARY KEY,
    name VARCHAR(120) NOT NULL UNIQUE
);
```

**Sample data:** `SEGUROS CAJA`, `ISANA`, `CONSALUD` (`db/03_seed_test.sql`);
`METLIFE` (`db/04_seed_real.sql`, the real provider).

**Seed:** `db/03_seed_test.sql`, `db/04_seed_real.sql`

---

### PAY_COMP_PLAN

Complementary insurance plans, each belonging to one provider, with a cost that can
be a fixed CLP amount, a fixed UF amount, or a percentage of the taxable base.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_COMP_PLAN" (
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
```

Where `complementary_insurance_cost_type` is
`ENUM ('fixed_clp', 'fixed_uf', 'variable_percentage')`.

**Sample data:** fake fixed/variable plan pairs for `SEGUROS CAJA`/`ISANA`/`CONSALUD`
(`db/03_seed_test.sql`); real `METLIFE` plans -- dental, health, and catastrophic
coverage, all `fixed_uf` (`db/04_seed_real.sql`).

**Seed:** `db/03_seed_test.sql`, `db/04_seed_real.sql`

---

### PAY_EMPLOYER

Employer entities -- one payroll history's worth of employer configuration,
including the rules used to derive each period's `payment_date` when it isn't
supplied directly.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_EMPLOYER" (
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
```

Where `employer_payment_date_rule` is
`ENUM ('last_business_day_of_month', 'fixed_day_of_month', 'calendar_days_before_end_of_month')`
and `employer_fixed_day_roll` is `ENUM ('previous_business_day', 'next_business_day')`.

**Sample data** (`db/04_seed_real.sql`, the only seeded employers -- others get
created ad hoc through the import flows):

| name | tax_id | started_at | payment_date_rule |
|---|---|---|---|
| DALT-CONSULTORES | 52.005.257-7 | 2016-07-18 | last_business_day_of_month |
| CLINICA-ALEMANA | 77.413.290-2 | 2018-04-03 | calendar_days_before_end_of_month |
| WALMART-CHILE | 76.042.014-K | 2024-11-18 | last_business_day_of_month |

**Seed:** `db/04_seed_real.sql`

---

### PAY_PERIOD

Payroll periods (one per employer + year + month). **No employee-level column** --
this table tracks one person's own payroll, not a multi-employee company payroll.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_PERIOD" (
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
```

Where `payroll_status` is `ENUM ('projected', 'actual', 'reviewed')` and
`employment_contract_kind` is `ENUM ('indefinite', 'fixed_term')`.

**No seed file** -- created by `POST /payroll/import/spreadsheet`,
`POST /payroll/import/json`, or the CLI's `import-payroll` command.

---

### PAY_PRD_HLTH

Junction table: which health plan tier(s) apply to a given period. Composite
primary key, no surrogate `id` -- a period commonly links to more than one row here
at once (e.g. `Base` + `GES` + `Adicionales`, see `PAY_HLTH_PLAN` above).

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_PRD_HLTH" (
    period_id      BIGINT NOT NULL REFERENCES "PAY_PERIOD"(id) ON DELETE CASCADE,
    health_plan_id BIGINT NOT NULL REFERENCES "PAY_HLTH_PLAN"(id),
    PRIMARY KEY (period_id, health_plan_id)
);
```

**No seed file** -- assigned via `POST /payroll/{period_id}/assign-plans` or
directly by the import flow.

---

### PAY_PRD_COMP

Junction table: which complementary insurance plan(s) apply to a given period.
Composite primary key, same shape as `PAY_PRD_HLTH`.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_PRD_COMP" (
    period_id                       BIGINT NOT NULL
        REFERENCES "PAY_PERIOD"(id) ON DELETE CASCADE,
    complementary_insurance_plan_id BIGINT NOT NULL
        REFERENCES "PAY_COMP_PLAN"(id),
    PRIMARY KEY (period_id, complementary_insurance_plan_id)
);
```

**No seed file** -- assigned the same way as `PAY_PRD_HLTH`.

---

### PAY_CONCEPT

Payroll concept catalog (income lines and discount lines). Closed, seeded catalog --
`concept_code` values used elsewhere (e.g. PDF import row resolution) must match a
`code` here.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_CONCEPT" (
    id         BIGSERIAL    PRIMARY KEY,
    code       VARCHAR(40)  NOT NULL UNIQUE,
    name       VARCHAR(120) NOT NULL,
    kind       VARCHAR(20)  NOT NULL CHECK (kind IN ('income', 'discount')),
    is_taxable BOOLEAN      NOT NULL DEFAULT FALSE
);
```

**Sample data** (`db/02_seed_base.sql`, the full/authoritative set -- 21 rows):
| code | kind | is_taxable |
|---|---|---|
| SALARY_BASE | income | true |
| LEGAL_GRATUITY | income | true |
| TELEWORK_REFUND | income | false |
| HEALTH_INSURANCE_EMPLOYER_CONTRIBUTION | income | true |
| VACATION_INCENTIVE | income | true |
| HOLIDAY_BONUS | income | true |
| AVAILABILITY_BONUS | income | true |
| LEGAL_GRATUITY_ADJUSTMENT | income | true |
| PRIOR_SALARY_DIFFERENCE | income | true |
| PENSION_BASE | discount | false |
| PENSION_ADDITIONAL | discount | false |
| HEALTH_BASE | discount | false |
| HEALTH_ADDITIONAL_UF | discount | false |
| HEALTH_INSURANCE | discount | false |
| VACATION_BONUS_ADVANCE | discount | false |
| HOLIDAY_BONUS_ADVANCE | discount | false |
| SALARY_ADVANCE | discount | false |
| PRIOR_MONTH_LEAVE_ABSENCE_DISCOUNT | discount | false |
| CCAF_LOAN | discount | false |
| UNEMPLOYMENT_INSURANCE | discount | false |
| INCOME_TAX | discount | false |

**Seed:** `db/02_seed_base.sql`

---

### PAY_ITEM

Individual payroll line items -- one row per concept per period.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_ITEM" (
    id         BIGSERIAL     PRIMARY KEY,
    period_id  BIGINT        NOT NULL REFERENCES "PAY_PERIOD"(id) ON DELETE CASCADE,
    concept_id BIGINT        NOT NULL REFERENCES "PAY_CONCEPT"(id),
    amount_clp NUMERIC(18,2) NOT NULL,
    notes      TEXT,
    created_at TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_payroll_items_period_id  ON "PAY_ITEM"(period_id);
CREATE INDEX idx_payroll_items_concept_id ON "PAY_ITEM"(concept_id);
```

### PAY_PDF_TEMPLATE

Employer-specific payroll PDF payslip templates (raw-label -> `concept_code` mapping
rules), managed via `pf-payroll`'s `/payroll/templates` CRUD endpoints. Replaces the
former git-tracked JSON files under `pf-payroll/infrastructure/pdf_import/templates/`
-- see `pf-payroll/docs/proposals/pdf-template-management-design-recommendation.md`
and `-design-plan.md`.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_PDF_TEMPLATE" (
    id                     BIGSERIAL     PRIMARY KEY,
    template_id            VARCHAR(80)   NOT NULL UNIQUE,
    employer_id            BIGINT        NOT NULL REFERENCES "PAY_EMPLOYER"(id),
    employer_match_pattern VARCHAR(500)  NOT NULL,
    version                INTEGER       NOT NULL DEFAULT 1 CHECK (version > 0),
    is_active              BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at             TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_pay_pdf_template_is_active ON "PAY_PDF_TEMPLATE"(is_active);
```

- `employer_id` is **required** (`NOT NULL`, since migration `0012`) -- a template
  may only be created for an employer that already has a `PAY_EMPLOYER` row (i.e.
  after its first payroll import has run at least once; there is no standalone
  endpoint to create a `PAY_EMPLOYER` row ahead of that). It is still never read by
  the actual PDF-matching code (`select_template()` in pf-payroll), which keeps
  using `employer_match_pattern` (a regex against the full raw PDF text) exactly as
  before, since the printed employer name on a real PDF does not necessarily match
  `PAY_EMPLOYER.name` verbatim.
- There is deliberately **no `employer_name` column** (removed in migration `0012` --
  it briefly existed as nullable, see migration `0010`, as a literal-override fallback
  for when `employer_id` was allowed to be `NULL`; now that `employer_id` is always
  required, that fallback case can no longer happen). The application layer
  (pf-payroll) always resolves the display name fresh from `PAY_EMPLOYER.name` via
  `employer_id` at read time -- never copied into this table.
- `is_active` is the logical-delete flag, following the exact same precedent as
  `PAY_PENS_INST`/`PAY_HLTH_INST` above (flipped by `DELETE /payroll/templates/{id}`,
  never a row `DELETE`).
- `template_id` (e.g. `"walmart-chile-v1"`) is the external identifier used by the API
  and by `PdfImportPreviewResponse.template_id` -- the internal numeric `id` never
  leaves pf-payroll.

**Seed:** `db/04_seed_real.sql` (the real `walmart-chile-v1` template, migrated from the
former JSON file).

---

### PAY_PDF_TEMPLATE_FIELD

One row per label-matching rule within a `PAY_PDF_TEMPLATE` (1:N).

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_PDF_TEMPLATE_FIELD" (
    id                BIGSERIAL     PRIMARY KEY,
    template_id       BIGINT        NOT NULL
        REFERENCES "PAY_PDF_TEMPLATE"(id) ON DELETE CASCADE,
    pdf_label_pattern VARCHAR(500)  NOT NULL,
    concept_id        BIGINT        NOT NULL REFERENCES "PAY_CONCEPT"(id),
    confidence        NUMERIC(3,2)  NOT NULL DEFAULT 0.90 CHECK (confidence BETWEEN 0 AND 1)
);

CREATE INDEX idx_pay_pdf_template_field_concept_id ON "PAY_PDF_TEMPLATE_FIELD"(concept_id);
CREATE INDEX idx_pay_pdf_template_field_template_id ON "PAY_PDF_TEMPLATE_FIELD"(template_id);
```

- `concept_id` carries a real FK to `PAY_CONCEPT(id)` -- an integrity upgrade the
  old hand-edited JSON format could not offer: a typo'd concept reference there
  silently produced a field that never resolves to a real concept, only
  discoverable at `pdf-preview` time against a real PDF. A write with an unknown
  `concept_code` is rejected by the application layer with a 400 before it ever
  reaches this FK (see `interfaces/api/routes/pdf_templates.py`'s
  `_resolve_field_dtos()`). The column is `concept_id`, not `concept_code`, since
  migration `0011` -- every other table referencing `PAY_CONCEPT` already does so
  by its surrogate id (`PAY_ITEM.concept_id`); the original `concept_code VARCHAR(40)
  REFERENCES PAY_CONCEPT(code)` from migration `0009` was the one inconsistent
  outlier, not a deliberate choice. `concept_code` remains the business-facing
  identifier at the application layer (requests, responses, `CONCEPT_MAP`, the
  PDF-matching engine) -- only this storage column changed, resolved at the
  repository boundary.
- There is deliberately **no `kind` column** (removed in migration `0010` -- it used to
  duplicate `PAY_CONCEPT.kind` with no referential integrity tying the two copies
  together, letting a write set a `kind` that contradicted its own concept's
  real kind). The application layer (pf-payroll) always resolves `kind` from
  `PAY_CONCEPT` via `concept_id` at read time instead.
- Deleting a `PAY_PDF_TEMPLATE` row (never done by the API -- logical delete only)
  would cascade here; in practice this only ever fires if a row is removed by hand.

**Seed:** `db/04_seed_real.sql` (the 20 fields of the real `walmart-chile-v1` template).

---

### PAY_MV_SUMARY (materialized view)

Aggregated per-period totals (gross income, taxable income, discounts, net pay) for
fast reads, refreshed on writes rather than computed on every read.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE MATERIALIZED VIEW "PAY_MV_SUMARY" AS
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

CREATE UNIQUE INDEX idx_pay_mv_sumary_period ON "PAY_MV_SUMARY"(period_id);
```

**Refresh:**
```sql
REFRESH MATERIALIZED VIEW "PAY_MV_SUMARY";
```
Run **without** `CONCURRENTLY` (it happens inside the same transaction as the
`PAY_ITEM` writes that trigger it, in
`payroll_repository_shared.py`, and `CONCURRENTLY` cannot run inside a transaction
block) -- the unique index above exists for future flexibility, not because the
current refresh call uses it.

---

## Entity Relationship Diagram

```
[PAY_EMPLOYER] 1---N [PAY_PERIOD]

[PAY_PENS_INST] 1---N [PAY_PENS_PLAN] 1---N [PAY_PERIOD] (pension_plan_id)
[PAY_HLTH_INST] 1---N [PAY_HLTH_PLAN] N---N [PAY_PERIOD] (via PAY_PRD_HLTH)
[PAY_COMP_PROV] 1---N [PAY_COMP_PLAN] N---N [PAY_PERIOD] (via PAY_PRD_COMP)

[PAY_PERIOD] 1---N [PAY_ITEM] N---1 [PAY_CONCEPT]

[PAY_EMPLOYER] 1---N [PAY_PDF_TEMPLATE] 1---N [PAY_PDF_TEMPLATE_FIELD] N---1 [PAY_CONCEPT]

[RAT_CURRENCY] 1---N [RAT_EXCH_RATE]
```

## Data flow

```
External Sources (Mindicador, BCCh, SII)
  |
  v
pf-rates (/refresh endpoints + startup background sync)
  |
  v
PostgreSQL (RAT_CURRENCY, RAT_EXCH_RATE, RAT_ECON_INDEX, RAT_TAX_BRCKT)
  |
  v
pf-rates (GET endpoints)
  |
  v
pf-payroll (HTTP client, MarketDataRepository)
  |
  v
PostgreSQL (payroll tables)
  |
  v
pf-payroll (API + PDF reports)
```

## See also

- [Getting Started](getting-started.md) - Installation and setup
- [Development Guide](development.md) - Make commands and workflows
- [Migrations Guide](migrations.md) - Creating and managing migrations
- [pf-rates AGENTS.md](../pf-rates/AGENTS.md) - Financial rates microservice
- [pf-payroll AGENTS.md](../pf-payroll/AGENTS.md) - Payroll microservice
