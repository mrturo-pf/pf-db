-- ============================================================
-- Test-only seed data — non-production fixtures.
-- Applied via: make seed-test  (runs seed-base first)
-- ============================================================

-- ============================================================
-- 1. Economic indices used by local API smoke tests
-- ============================================================
INSERT INTO "RAT_ECON_INDEX" (code, accrual_year, accrual_month, index_value, source)
VALUES ('IPC_CL', 2026, 1, 109.710000, 'test')
ON CONFLICT (code, accrual_year, accrual_month) DO UPDATE
SET index_value = EXCLUDED.index_value,
    source = EXCLUDED.source;

-- ============================================================
-- 2. Income-tax bracket used by local API smoke tests
-- ============================================================
INSERT INTO "RAT_TAX_BRCKT" (
    valid_from, valid_to, lower_bound_utm, upper_bound_utm, marginal_rate, rebate_utm
) VALUES
    (DATE '2026-01-01', NULL, 0, 100, 0.100000, 0)
ON CONFLICT (valid_from, lower_bound_utm) DO UPDATE
SET valid_to = EXCLUDED.valid_to,
    upper_bound_utm = EXCLUDED.upper_bound_utm,
    marginal_rate = EXCLUDED.marginal_rate,
    rebate_utm = EXCLUDED.rebate_utm;

-- 3. Exchange rates used by local payroll validation tests
-- ============================================================
INSERT INTO "RAT_EXCH_RATE" (currency_code, rate_date, value_clp, source)
VALUES ('UF', DATE '2027-01-31', 40000.000000, 'test')
ON CONFLICT (currency_code, rate_date) DO UPDATE
SET value_clp = EXCLUDED.value_clp,
    source = EXCLUDED.source;

-- ============================================================
-- 4. Pension plans (one base plan per institution)
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
-- 5. Health plans (one base plan per institution)
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
-- 6. Complementary insurance providers
-- ============================================================
INSERT INTO "INC_COMP_PROV" (name) VALUES
    ('SEGUROS CAJA'),
    ('ISANA'),
    ('CONSALUD')
ON CONFLICT (name) DO NOTHING;

-- ============================================================
-- 7. Complementary insurance plans
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
