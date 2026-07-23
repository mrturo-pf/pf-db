# Tables Reference

Complete documentation of the 17 tables managed by pf-db, including ownership, relationships, and connection details.

## Overview

pf-db manages **17 tables** across two domains:
- **Financial rates:** 4 tables (owned by pf-rates)
- **Payroll:** 13 tables + 1 materialized view (owned by pf-payroll)

## Table ownership

Ownership means: only the microservices that own a domain **write** to those tables. Any microservice may **read** any table.

| Tables | Domain | Owner | Access pattern |
|---|---|---|---|
| `currencies`, `exchange_rates`, `economic_indices`, `income_tax_brackets` | Financial rates | [pf-rates](../pf-rates) | pf-payroll reads via HTTP API (never direct SQL) |
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

### currencies

Supported currencies for exchange rates.

**Owner:** pf-rates

**Schema:**
```sql
CREATE TABLE currencies (
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

### exchange_rates

Historical exchange rates (CLP value for foreign currencies).

**Owner:** pf-rates

**Schema:**
```sql
CREATE TABLE exchange_rates (
    id SERIAL PRIMARY KEY,
    currency_code VARCHAR(3) REFERENCES currencies(code),
    rate_date DATE NOT NULL,
    value_clp NUMERIC(12, 4) NOT NULL,
    UNIQUE (currency_code, rate_date)
);

CREATE INDEX idx_exchange_rates_currency_date ON exchange_rates(currency_code, rate_date);
```

**Sample data:**
| id | currency_code | rate_date | value_clp |
|---|---|---|---|
| 1 | USD | 2024-01-15 | 897.5000 |
| 2 | EUR | 2024-01-15 | 978.2500 |

**Source:** Mindicador.cl, Banco Central de Chile (BCCH)

---

### economic_indices

Economic indices (UF, UTM, IPC) with monthly values.

**Owner:** pf-rates

**Schema:**
```sql
CREATE TABLE economic_indices (
    id SERIAL PRIMARY KEY,
    code VARCHAR(10) NOT NULL,
    year INTEGER NOT NULL,
    month INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
    value NUMERIC(12, 2) NOT NULL CHECK (value > 0),
    UNIQUE (code, year, month)
);

CREATE INDEX idx_economic_indices_code_year_month ON economic_indices(code, year, month);
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

### income_tax_brackets

Income tax brackets for Chilean payroll tax calculation.

**Owner:** pf-rates

**Schema:**
```sql
CREATE TABLE income_tax_brackets (
    id SERIAL PRIMARY KEY,
    year INTEGER NOT NULL,
    lower_bound_utm NUMERIC(6, 2) NOT NULL,
    upper_bound_utm NUMERIC(6, 2),
    rate NUMERIC(5, 4) NOT NULL,
    rebate_utm NUMERIC(6, 2) NOT NULL,
    UNIQUE (year, lower_bound_utm)
);

CREATE INDEX idx_income_tax_brackets_year ON income_tax_brackets(year);
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

## Payroll tables (13 tables + 1 view)

### pension_institutions

AFP (pension fund administrator) institutions.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE pension_institutions (
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

### health_institutions

Health institutions (Fonasa + Isapres).

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE health_institutions (
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

### pension_plans

Pension plan types.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE pension_plans (
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

### health_plans

Health plan types.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE health_plans (
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

### contribution_caps

Monthly contribution caps (UF-based).

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE contribution_caps (
    id SERIAL PRIMARY KEY,
    year INTEGER NOT NULL,
    month INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
    afp_cap_uf NUMERIC(6, 2) NOT NULL,
    health_cap_uf NUMERIC(6, 2) NOT NULL,
    UNIQUE (year, month)
);

CREATE INDEX idx_contribution_caps_year_month ON contribution_caps(year, month);
```

**Sample data:**
| id | year | month | afp_cap_uf | health_cap_uf |
|---|---|---|---|---|
| 1 | 2024 | 1 | 83.30 | 99.20 |

**Seed:** `db/02_seed_base.sql`

**Note:** Caps are updated monthly by SII (Servicio de Impuestos Internos).

---

### complementary_insurance_providers

Complementary insurance providers.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE complementary_insurance_providers (
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

### complementary_insurance_plans

Complementary insurance plan types.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE complementary_insurance_plans (
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

### employers

Employer entities.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE employers (
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

### payroll_periods

Payroll periods (month/year + payment date).

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE payroll_periods (
    id SERIAL PRIMARY KEY,
    employer_id INTEGER REFERENCES employers(id),
    year INTEGER NOT NULL,
    month INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
    payment_date DATE NOT NULL,
    UNIQUE (employer_id, year, month)
);

CREATE INDEX idx_payroll_periods_employer ON payroll_periods(employer_id);
```

---

### payroll_period_health_plans

Health plan selections per payroll period.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE payroll_period_health_plans (
    id SERIAL PRIMARY KEY,
    payroll_period_id INTEGER REFERENCES payroll_periods(id),
    health_institution_id INTEGER REFERENCES health_institutions(id),
    plan_value_clp NUMERIC(12, 2) NOT NULL,
    UNIQUE (payroll_period_id, health_institution_id)
);
```

---

### payroll_complementary_insurance

Complementary insurance per payroll period.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE payroll_complementary_insurance (
    id SERIAL PRIMARY KEY,
    payroll_period_id INTEGER REFERENCES payroll_periods(id),
    provider_id INTEGER REFERENCES complementary_insurance_providers(id),
    plan_id INTEGER REFERENCES complementary_insurance_plans(id),
    premium_clp NUMERIC(12, 2) NOT NULL
);
```

---

### payroll_concepts

Custom payroll concepts (bonuses, deductions).

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE payroll_concepts (
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

### payroll_items

Individual payroll line items.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE TABLE payroll_items (
    id SERIAL PRIMARY KEY,
    payroll_period_id INTEGER REFERENCES payroll_periods(id),
    employee_rut VARCHAR(12) NOT NULL,
    concept_id INTEGER REFERENCES payroll_concepts(id),
    amount_clp NUMERIC(12, 2) NOT NULL
);

CREATE INDEX idx_payroll_items_period ON payroll_items(payroll_period_id);
CREATE INDEX idx_payroll_items_employee ON payroll_items(employee_rut);
```

---

### mv_payroll_summary (materialized view)

Aggregated payroll summaries for analytics.

**Owner:** pf-payroll

**Schema:**
```sql
CREATE MATERIALIZED VIEW mv_payroll_summary AS
SELECT 
    pp.id AS payroll_period_id,
    pp.employer_id,
    pp.year,
    pp.month,
    COUNT(DISTINCT pi.employee_rut) AS employee_count,
    SUM(CASE WHEN pc.category = 'income' THEN pi.amount_clp ELSE 0 END) AS total_income,
    SUM(CASE WHEN pc.category = 'deduction' THEN pi.amount_clp ELSE 0 END) AS total_deductions
FROM payroll_periods pp
LEFT JOIN payroll_items pi ON pp.id = pi.payroll_period_id
LEFT JOIN payroll_concepts pc ON pi.concept_id = pc.id
GROUP BY pp.id, pp.employer_id, pp.year, pp.month;

CREATE UNIQUE INDEX idx_mv_payroll_summary_period ON mv_payroll_summary(payroll_period_id);
```

**Refresh:**
```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_payroll_summary;
```

---

## Entity Relationship Diagram

```
[currencies] 1---N [exchange_rates]

[employers] 1---N [payroll_periods]

[payroll_periods] 1---N [payroll_period_health_plans]
                  1---N [payroll_complementary_insurance]
                  1---N [payroll_items]

[payroll_items] N---1 [payroll_concepts]

[payroll_period_health_plans] N---1 [health_institutions]

[payroll_complementary_insurance] N---1 [complementary_insurance_providers]
                                   N---1 [complementary_insurance_plans]

[pension_institutions] (referenced by application, not FK)
[health_institutions] (referenced by payroll_period_health_plans)
```

## Data flow

```
External Sources (Mindicador, BCCH, SII)
  |
  v
pf-rates (/refresh endpoints)
  |
  v
PostgreSQL (currencies, exchange_rates, economic_indices, income_tax_brackets)
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
