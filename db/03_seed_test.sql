-- ============================================================
-- Test-only seed data — non-production fixtures.
-- Applied via: make seed-test  (runs seed-base first)
-- ============================================================

-- ============================================================
-- 1. Economic indices used by local API smoke tests
-- ============================================================
INSERT INTO "RAT_ECON_INDEX" (
    code, accrual_year, accrual_month, index_value, source
) VALUES
    ('UF',  2026, 1, 39000.000000, 'test'),
    ('UF',  2026, 2, 39100.000000, 'test'),
    ('UF',  2026, 3, 39200.000000, 'test'),
    ('UTM', 2026, 1,    65000.000000, 'test'),
    ('UTM', 2026, 2,    65100.000000, 'test'),
    ('UTM', 2026, 3,    65200.000000, 'test'),
    ('UF',  2027, 1, 40000.000000, 'test')
ON CONFLICT (code, accrual_year, accrual_month) DO UPDATE
SET index_value = EXCLUDED.index_value,
    source = EXCLUDED.source;

-- ============================================================
-- 2. Exchange rates used by local payroll validation tests
-- ============================================================
INSERT INTO "RAT_EXCH_RATE" (currency_code, rate_date, value_clp, source)
VALUES ('UF', DATE '2027-01-31', 40000.000000, 'test')
ON CONFLICT (currency_code, rate_date) DO UPDATE
SET value_clp = EXCLUDED.value_clp,
    source = EXCLUDED.source;

-- ============================================================
-- 3. Pension plans (one base plan per institution)
-- ============================================================
INSERT INTO "INC_PENS_PLAN" (institution_id, valid_from, valid_to, additional_rate)
SELECT pi.id, DATE '2026-01-01', NULL, 0
FROM "INC_PENS_INST" pi
WHERE NOT EXISTS (
    SELECT 1
    FROM "INC_PENS_PLAN" pp
    WHERE pp.institution_id = pi.id
      AND pp.valid_from     = DATE '2026-01-01'
      AND pp.additional_rate = 0
);

-- ============================================================
-- 4. Health plans (one base plan per institution)
-- ============================================================
INSERT INTO "INC_HLTH_PLAN" (institution_id, valid_from, valid_to, plan_name, contracted_uf)
SELECT hi.id, DATE '2026-01-01', NULL, 'Base', 0
FROM "INC_HLTH_INST" hi
WHERE NOT EXISTS (
    SELECT 1
    FROM "INC_HLTH_PLAN" hp
    WHERE hp.institution_id = hi.id
      AND hp.valid_from     = DATE '2026-01-01'
      AND COALESCE(hp.plan_name, '') = 'Base'
      AND hp.contracted_uf  = 0
);

-- ============================================================
-- 5. Complementary insurance providers
-- ============================================================
INSERT INTO "INC_COMP_PROV" (name) VALUES
    ('SEGUROS CAJA'),
    ('ISANA'),
    ('CONSALUD')
ON CONFLICT (name) DO NOTHING;

-- ============================================================
-- 6. Complementary insurance plans
-- ============================================================
INSERT INTO "INC_COMP_PLAN" (
    provider_id, name, cost_type, cost_value, cost_currency, valid_from, valid_to
) VALUES
    (
        (SELECT id FROM "INC_COMP_PROV" WHERE name = 'SEGUROS CAJA'),
        'Plan Clínico Plus - Fixed',
        'fixed_clp'::complementary_insurance_cost_type,
        50000, 'CLP', DATE '2025-01-01', NULL
    ),
    (
        (SELECT id FROM "INC_COMP_PROV" WHERE name = 'SEGUROS CAJA'),
        'Plan Clínico Plus - Variable',
        'variable_percentage'::complementary_insurance_cost_type,
        2.5, 'CLP', DATE '2025-01-01', NULL
    ),
    (
        (SELECT id FROM "INC_COMP_PROV" WHERE name = 'ISANA'),
        'Plan Integral - Fixed',
        'fixed_clp'::complementary_insurance_cost_type,
        35000, 'CLP', DATE '2025-01-01', NULL
    ),
    (
        (SELECT id FROM "INC_COMP_PROV" WHERE name = 'ISANA'),
        'Plan Integral - Variable',
        'variable_percentage'::complementary_insurance_cost_type,
        2.0, 'CLP', DATE '2025-01-01', NULL
    ),
    (
        (SELECT id FROM "INC_COMP_PROV" WHERE name = 'CONSALUD'),
        'Plan Premium - Fixed',
        'fixed_clp'::complementary_insurance_cost_type,
        55000, 'CLP', DATE '2025-01-01', NULL
    ),
    (
        (SELECT id FROM "INC_COMP_PROV" WHERE name = 'CONSALUD'),
        'Plan Premium - Variable',
        'variable_percentage'::complementary_insurance_cost_type,
        3.0, 'CLP', DATE '2025-01-01', NULL
    );
