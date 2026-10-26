-- ============================================================
-- Test-only seed data — non-production fixtures.
-- Applied via: make seed-test  (runs seed-base first)
-- ============================================================

-- ============================================================
-- 1. Exchange rates used by local payroll validation tests
-- ============================================================
INSERT INTO "RAT_EXCH_RATE" (currency_code, rate_date, value_clp, source)
VALUES ('UF', DATE '2027-01-31', 40000.000000, 'test')
ON CONFLICT (currency_code, rate_date) DO UPDATE
SET value_clp = EXCLUDED.value_clp,
    source = EXCLUDED.source;

-- ============================================================
-- 2. Pension plans (one base plan per institution)
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
-- 3. Health plans (one base plan per institution)
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
-- 4. Complementary insurance providers
-- ============================================================
INSERT INTO "INC_COMP_PROV" (name) VALUES
    ('SEGUROS CAJA'),
    ('ISANA'),
    ('CONSALUD')
ON CONFLICT (name) DO NOTHING;

-- ============================================================
-- 5. Complementary insurance plans
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
