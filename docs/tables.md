# Tables Reference

Complete documentation of the 18 tables managed by pf-db, including ownership, relationships, and connection details.

## Overview

pf-db manages **18 tables** across two domains:
- **Financial rates:** 5 tables (owned by pf-rates)
- **Payroll:** 13 tables + 1 materialized view (owned by pf-payroll)

## Table ownership

Ownership means: only the microservices that own a domain **write** to those tables. Any microservice may **read** any table.

| Tables | Domain | Owner | Access pattern |
|---|---|---|---|
| `RAT_CURRENCY`, `RAT_EXCH_RATE`, `RAT_ECON_INDEX`, `RAT_TAX_BRCKT`, `RAT_EXPORT_JOB` | Financial rates | [pf-rates](../pf-rates) | pf-payroll reads via HTTP API (never direct SQL) |
| All others (13 tables + 1 view) | Payroll | [pf-payroll](../pf-payroll) | Exclusive write access |

## Connection string

**Local:**
```
postgresql+asyncpg://pf_db:pf_db@localhost:5432/pf_db
```

**Production:**
Set via `PF_DATABASE_URL` in Secret Manager, injected into Cloud Run services at runtime.

Each consuming microservice sets its own env-var prefix for the connection string.

## Financial rates tables (4 tables)

### RAT_CURRENCY

Supported currencies for exchange rates.

**Owner:** pf-rates

**Schema:**
```sql
CREATE TABLE "RAT_CURRENCY" (
    code VARCHAR(3) PRIMARY KEY,
    name VARCHAR(100) NOT NULL
);
```

**Sample data:**
| code | name |
|---|---|
| USD | United States Dollar |
| EUR | Euro |

**Seed:** `db/02_seed_base.sql`

---

### RAT_EXCH_RATE

Historical exchange rates (CLP value for foreign currencies).

**Owner:** pf-rates

**Schema:**
```sql
CREATE TABLE "RAT_EXCH_RATE" (
    id SERIAL PRIMARY KEY,
    currency_code VARCHAR(3) REFERENCES "RAT_CURRENCY"(code),
    rate_date DATE NOT NULL,
    value_clp NUMERIC(12, 4) NOT NULL,
    UNIQUE (currency_code, rate_date)
);
```

**Sample data:**
| id | currency_code | rate_date | value_clp |
|---|---|---|---|
| 1 | USD | 2024-01-15 | 897.5000 |
| 2 | EUR | 2024-01-15 | 978.2500 |

**Source:** Mindicador.cl, Banco Central de Chile (BCCH)

---

### RAT_ECON_INDEX

Economic indices (UF, UTM, IPC) with monthly values.

**Owner:** pf-rates

**Schema:**
```sql
CREATE TABLE "RAT_ECON_INDEX" (
    id SERIAL PRIMARY KEY,
    code VARCHAR(10) NOT NULL,
    year INTEGER NOT NULL,
    month INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
    value NUMERIC(12, 2) NOT NULL CHECK (value > 0),
    UNIQUE (code, year, month)
);
```

**Sample data:**
| id | code | year | month | value |
|---|---|---|---|---|
| 1 | UF | 2024 | 1 | 36500.25 |
| 2 | UTM | 2024 | 1 | 65000.00 |
| 3 | IPC | 2024 | 1 | 145.30 |

**Source:** Banco Central de Chile (BCCH), INE (IPC)

**Note:** UF includes pre-published future values (BCCH publishes up to 3 months ahead).

---

### RAT_TAX_BRCKT

Income tax brackets for Chilean payroll tax calculation.

**Owner:** pf-rates

**Schema:**
```sql
CREATE TABLE "RAT_TAX_BRCKT" (
    id SERIAL PRIMARY KEY,
    year INTEGER NOT NULL,
    lower_bound_utm NUMERIC(6, 2) NOT NULL,
    upper_bound_utm NUMERIC(6, 2),
    rate NUMERIC(5, 4) NOT NULL,
    rebate_utm NUMERIC(6, 2) NOT NULL,
    UNIQUE (year, lower_bound_utm)
);
```

**Sample data (2024):**
| id | year | lower_bound_utm | upper_bound_utm | rate | rebate_utm |
|---|---|---|---|---|---|
| 1 | 2024 | 0.00 | 13.50 | 0.0000 | 0.00 |
| 2 | 2024 | 13.50 | 30.00 | 0.0400 | 0.54 |
| 3 | 2024 | 30.00 | 50.00 | 0.0800 | 1.74 |
| 4 | 2024 | 50.00 | 70.00 | 0.1350 | 4.49 |

**Seed:** `db/02_seed_base.sql`

---

### RAT_EXPORT_JOB

Async CSV export job tracking (`POST /exchange-rates/export {"async": true}`).

**Owner:** pf-rates

**Schema:**
```sql
CREATE TABLE "RAT_EXPORT_JOB" (
    id             BIGSERIAL     PRIMARY KEY,
    status         VARCHAR(20)   NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'running', 'succeeded', 'failed')),
    lookback_days  INTEGER       NOT NULL CHECK (lookback_days >= 0),
    forward_days   INTEGER       NOT NULL CHECK (forward_days >= 0),
    rows_written   INTEGER,
    file_id        VARCHAR(200),
    error_message  TEXT,
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
```

**Sample data:**
| id | status | lookback_days | forward_days | rows_written | file_id |
|---|---|---|---|---|---|
| 1 | succeeded | 6100 | 30 | 24521 | 1a2b3c... |

**Note:** row is created by the trigger request and updated in place by the
background task as it progresses (`pending` -> `running` -> `succeeded`/`failed`).
No seed data -- purely operational/runtime state.

---

## Payroll tables (13 tables + 1 view)

### PAY_PENS_INST

AFP (pension fund administrator) institutions.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_PENS_INST" (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE
);
```

**Sample data:**
| id | name |
|---|---|
| 1 | Capital |
| 2 | Cuprum |
| 3 | Habitat |
| 4 | PlanVital |
| 5 | Provida |
| 6 | Modelo |
| 7 | Uno |

**Seed:** `db/02_seed_base.sql`

---

### PAY_HLTH_INST

Health institutions (Fonasa + Isapres).

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_HLTH_INST" (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE
);
```

**Sample data:**
| id | name |
|---|---|
| 1 | Fonasa |
| 2 | Banmédica |
| 3 | Colmena |
| 4 | Consalud |
| 5 | Cruz Blanca |
| 6 | Nueva Masvida |
| 7 | Vida Tres |

**Seed:** `db/02_seed_base.sql`

---

### PAY_PENS_PLAN

Pension plan types.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_PENS_PLAN" (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE
);
```

**Sample data:**
| id | name |
|---|---|
| 1 | Mandatory |
| 2 | Voluntary |

**Seed:** `db/03_seed_test.sql`

---

### PAY_HLTH_PLAN

Health plan types.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_HLTH_PLAN" (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE
);
```

**Sample data:**
| id | name |
|---|---|
| 1 | Fonasa |
| 2 | Isapre |

**Seed:** `db/03_seed_test.sql`

---

### PAY_CNTRB_CAP

Monthly contribution caps (UF-based).

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_CNTRB_CAP" (
    id SERIAL PRIMARY KEY,
    year INTEGER NOT NULL,
    month INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
    afp_cap_uf NUMERIC(6, 2) NOT NULL,
    health_cap_uf NUMERIC(6, 2) NOT NULL,
    UNIQUE (year, month)
);
```

**Sample data:**
| id | year | month | afp_cap_uf | health_cap_uf |
|---|---|---|---|---|
| 1 | 2024 | 1 | 83.30 | 99.20 |

**Seed:** `db/02_seed_base.sql`

**Note:** Caps are updated monthly by SII (Servicio de Impuestos Internos).

---

### PAY_COMP_PROV

Complementary insurance providers.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_COMP_PROV" (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE
);
```

**Sample data:**
| id | name |
|---|---|
| 1 | Vida Security |
| 2 | Consorcio |

**Seed:** `db/03_seed_test.sql`

---

### PAY_COMP_PLAN

Complementary insurance plan types.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_COMP_PLAN" (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE
);
```

**Sample data:**
| id | name |
|---|---|
| 1 | Basic |
| 2 | Premium |

**Seed:** `db/03_seed_test.sql`

---

### PAY_EMPLOYER

Employer entities.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_EMPLOYER" (
    id SERIAL PRIMARY KEY,
    rut VARCHAR(12) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL
);
```

**Sample data:**
| id | rut | name |
|---|---|---|
| 1 | 76.123.456-7 | Example Corp |

---

### PAY_PERIOD

Payroll periods (month/year + payment date).

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_PERIOD" (
    id SERIAL PRIMARY KEY,
    employer_id INTEGER REFERENCES "PAY_EMPLOYER"(id),
    year INTEGER NOT NULL,
    month INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
    payment_date DATE NOT NULL,
    UNIQUE (employer_id, year, month)
);

CREATE INDEX idx_payroll_periods_employer ON "PAY_PERIOD"(employer_id);
```

---

### PAY_PRD_HLTH

Health plan selections per payroll period.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_PRD_HLTH" (
    id SERIAL PRIMARY KEY,
    payroll_period_id INTEGER REFERENCES "PAY_PERIOD"(id),
    health_institution_id INTEGER REFERENCES "PAY_HLTH_INST"(id),
    plan_value_clp NUMERIC(12, 2) NOT NULL,
    UNIQUE (payroll_period_id, health_institution_id)
);
```

---

### PAY_PRD_COMP

Complementary insurance per payroll period.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_PRD_COMP" (
    id SERIAL PRIMARY KEY,
    payroll_period_id INTEGER REFERENCES "PAY_PERIOD"(id),
    provider_id INTEGER REFERENCES "PAY_COMP_PROV"(id),
    plan_id INTEGER REFERENCES "PAY_COMP_PLAN"(id),
    premium_clp NUMERIC(12, 2) NOT NULL
);
```

---

### PAY_CONCEPT

Custom payroll concepts (bonuses, deductions).

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_CONCEPT" (
    id SERIAL PRIMARY KEY,
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    category VARCHAR(20) NOT NULL CHECK (category IN ('income', 'deduction'))
);
```

**Sample data:**
| id | code | name | category |
|---|---|---|---|
| 1 | BASE_SALARY | Base Salary | income |
| 2 | OVERTIME | Overtime | income |
| 3 | AFP | AFP Contribution | deduction |
| 4 | HEALTH | Health Contribution | deduction |

**Seed:** `db/02_seed_base.sql`

---

### PAY_ITEM

Individual payroll line items.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE "PAY_ITEM" (
    id SERIAL PRIMARY KEY,
    payroll_period_id INTEGER REFERENCES "PAY_PERIOD"(id),
    employee_rut VARCHAR(12) NOT NULL,
    concept_id INTEGER REFERENCES "PAY_CONCEPT"(id),
    amount_clp NUMERIC(12, 2) NOT NULL
);

CREATE INDEX idx_payroll_items_period ON "PAY_ITEM"(payroll_period_id);
CREATE INDEX idx_payroll_items_employee ON "PAY_ITEM"(employee_rut);
```

---

### PAY_MV_SUMARY (materialized view)

Aggregated payroll summaries for analytics.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE MATERIALIZED VIEW "PAY_MV_SUMARY" AS
SELECT 
    pp.id AS payroll_period_id,
    pp.employer_id,
    pp.year,
    pp.month,
    COUNT(DISTINCT pi.employee_rut) AS employee_count,
    SUM(CASE WHEN pc.category = 'income' THEN pi.amount_clp ELSE 0 END) AS total_income,
    SUM(CASE WHEN pc.category = 'deduction' THEN pi.amount_clp ELSE 0 END) AS total_deductions
FROM "PAY_PERIOD" pp
LEFT JOIN "PAY_ITEM" pi ON pp.id = pi.payroll_period_id
LEFT JOIN "PAY_CONCEPT" pc ON pi.concept_id = pc.id
GROUP BY pp.id, pp.employer_id, pp.year, pp.month;

CREATE UNIQUE INDEX idx_mv_payroll_summary_period ON "PAY_MV_SUMARY"(payroll_period_id);
```

**Refresh:**
```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY "PAY_MV_SUMARY";
```

---

## Entity Relationship Diagram

```
[RAT_CURRENCY] 1---N [RAT_EXCH_RATE]

[PAY_EMPLOYER] 1---N [PAY_PERIOD]

[PAY_PERIOD] 1---N [PAY_PRD_HLTH]
                  1---N [PAY_PRD_COMP]
                  1---N [PAY_ITEM]

[PAY_ITEM] N---1 [PAY_CONCEPT]

[PAY_PRD_HLTH] N---1 [PAY_HLTH_INST]

[PAY_PRD_COMP] N---1 [PAY_COMP_PROV]
                                   N---1 [PAY_COMP_PLAN]

[PAY_PENS_INST] (referenced by application, not FK)
[PAY_HLTH_INST] (referenced by PAY_PRD_HLTH)
```

## Data flow

```
External Sources (Mindicador, BCCH, SII)
  |
  v
pf-rates (/refresh endpoints)
  |
  v
PostgreSQL (RAT_CURRENCY, RAT_EXCH_RATE, RAT_ECON_INDEX, RAT_TAX_BRCKT)
  |
  v
pf-rates (GET endpoints)
  |
  v
pf-payroll (HTTP client)
  |
  v
PostgreSQL (payroll tables)
  |
  v
pf-payroll (API + reports)
```

## See also

- [Getting Started](getting-started.md) - Installation and setup
- [Development Guide](development.md) - Make commands and workflows
- [Migrations Guide](migrations.md) - Creating and managing migrations
- [pf-rates AGENTS.md](../pf-rates/AGENTS.md) - Financial rates microservice
- [pf-payroll AGENTS.md](../pf-payroll/AGENTS.md) - Payroll microservice
