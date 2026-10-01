-- ============================================================
-- Real / production-like seed data.
-- Applied via: make seed-real  (runs seed-base first)
-- ============================================================

-- ============================================================
-- 1. Pension plans — one plan per AFP with real commission rates
-- ============================================================
INSERT INTO "PAY_PENS_PLAN" (institution_id, valid_from, valid_to, additional_rate)
SELECT pi.id, DATE '2024-11-01', NULL, 0.0116
FROM "PAY_PENS_INST" pi
WHERE pi.code = 'AFP_PLANVITAL'
  AND NOT EXISTS (
      SELECT 1
      FROM "PAY_PENS_PLAN" pp
      WHERE pp.institution_id = pi.id
        AND pp.valid_from     = DATE '2024-11-01'
  );

-- ============================================================
-- 2. Health plans
-- ============================================================
-- One-time correction: a prior version of this file inserted an
-- open-ended 'Base' tier at 2024-11-01/5.42 UF, keyed for idempotency on
-- (valid_from, plan_name). The health-additional-uf-mismatch investigation
-- later corrected that same row (Neon id 8 at the time) via UPDATE ...
-- SET valid_from = '2026-03-01' instead of DELETE+INSERT (see
-- pf-payroll/docs/investigations/health-additional-uf-mismatch.md,
-- Session 4). That silently broke this file's NOT-EXISTS idempotency
-- check: once the real row's valid_from moved away from '2024-11-01',
-- any later deploy re-running this file with the old VALUES list found
-- no conflict and re-inserted the stale, already-fixed-away value --
-- which then double-counts against the correct time-versioned tier below
-- for every period from 2024-11 onward (get_health_plans_overlapping_month()
-- deliberately returns every overlapping plan, so two 'Base' rows both
-- contribute). This DELETE is idempotent and safe to keep permanently.
DELETE FROM "PAY_HLTH_PLAN"
WHERE plan_name = 'Base'
  AND valid_from = '2024-11-01'
  AND valid_to IS NULL
  AND contracted_uf = 5.42;

INSERT INTO "PAY_HLTH_PLAN" (institution_id, valid_from, valid_to, plan_name, contracted_uf)
SELECT hi.id, entry.valid_from, entry.valid_to, entry.plan_name, entry.contracted_uf
FROM "PAY_HLTH_INST" hi
CROSS JOIN (VALUES
    (DATE '2025-02-25', DATE '2025-02-28', 'Base',        4.94::NUMERIC(10,4)),
    (DATE '2025-03-01', DATE '2025-07-31', 'Base',        4.94::NUMERIC(10,4)),
    (DATE '2025-08-01', DATE '2025-12-31', 'Base',        5.19::NUMERIC(10,4)),
    (DATE '2026-01-01', DATE '2026-02-28', 'Base',        5.30::NUMERIC(10,4)),
    (DATE '2026-03-01', DATE '2026-05-31', 'Base',        5.42::NUMERIC(10,4)),
    (DATE '2026-06-01', NULL::DATE,        'Base',        5.53::NUMERIC(10,4)),
    (DATE '2024-11-01', NULL::DATE,        'GES',         0.91::NUMERIC(10,4)),
    (DATE '2024-11-01', NULL::DATE,        'Adicionales', 0.79::NUMERIC(10,4))
) AS entry(valid_from, valid_to, plan_name, contracted_uf)
WHERE hi.code = 'ESENCIAL'
  AND NOT EXISTS (
      SELECT 1
      FROM "PAY_HLTH_PLAN" hp
      WHERE hp.institution_id = hi.id
        AND hp.valid_from     = entry.valid_from
        AND COALESCE(hp.plan_name, '') = entry.plan_name
  );

-- ============================================================
-- 3. Contribution caps
-- ============================================================
INSERT INTO "PAY_CNTRB_CAP" (cap_type, valid_from, valid_to, value_uf) VALUES
    ('pension_health', DATE '2024-01-01', DATE '2024-12-31', 84.3000),
    ('pension_health', DATE '2025-01-01', DATE '2025-12-31', 87.8000),
    ('pension_health', DATE '2026-01-01', DATE '2026-01-31', 89.9000),
    ('pension_health', DATE '2026-02-01', NULL, 90.0000)
ON CONFLICT (cap_type, valid_from) DO UPDATE
SET
    valid_to = EXCLUDED.valid_to,
    value_uf = EXCLUDED.value_uf;

-- ============================================================
-- 4. Employers
-- ============================================================

INSERT INTO "PAY_EMPLOYER" (
    name,
    tax_id,
    country_code,
    started_at,
    payment_date_rule,
    payment_month_offset,
    payment_day_of_month,
    payment_business_day_offset,
    payment_calendar_day_offset,
    payment_effective_on_processing_next_day,
    payment_fixed_day_roll,
    first_increase_period_year,
    first_increase_period_month,
    increase_frequency
) VALUES
    (
        'DALT-CONSULTORES',
        '52.005.257-7',
        'CL',
        DATE '2016-07-18',
        'last_business_day_of_month',
        0,
        NULL,
        0,
        0,
        FALSE,
        'previous_business_day',
        NULL,
        NULL,
        NULL
    ),
    (
        'CLINICA-ALEMANA',
        '77.413.290-2',
        'CL',
        DATE '2018-04-03',
        'calendar_days_before_end_of_month',
        0,
        NULL,
        0,
        7,
        TRUE,
        'previous_business_day',
        NULL,
        NULL,
        6
    ),
    (
        'WALMART-CHILE',
        '76.042.014-K',
        'CL',
        DATE '2024-11-18',
        'last_business_day_of_month',
        0,
        NULL,
        1,
        0,
        TRUE,
        'previous_business_day',
        2026,
        5,
        NULL
    )
ON CONFLICT (name) DO UPDATE
SET
    tax_id = EXCLUDED.tax_id,
    country_code = EXCLUDED.country_code,
    started_at = EXCLUDED.started_at,
    payment_date_rule = EXCLUDED.payment_date_rule,
    payment_month_offset = EXCLUDED.payment_month_offset,
    payment_day_of_month = EXCLUDED.payment_day_of_month,
    payment_business_day_offset = EXCLUDED.payment_business_day_offset,
    payment_calendar_day_offset = EXCLUDED.payment_calendar_day_offset,
    payment_effective_on_processing_next_day = EXCLUDED.payment_effective_on_processing_next_day,
    payment_fixed_day_roll = EXCLUDED.payment_fixed_day_roll;

-- ============================================================
-- 5. Complementary insurance providers
-- ============================================================
INSERT INTO "PAY_COMP_PROV" (name) VALUES
    ('METLIFE')
ON CONFLICT (name) DO NOTHING;

-- ============================================================
-- 6. Complementary insurance plans
-- ============================================================
INSERT INTO "PAY_COMP_PLAN" (
    provider_id,
    name,
    cost_type,
    cost_value,
    cost_currency,
    valid_from,
    valid_to
)
SELECT
    p.id,
    entry.name,
    entry.cost_type::complementary_insurance_cost_type,
    entry.cost_value,
    entry.cost_currency,
    entry.valid_from,
    entry.valid_to
FROM "PAY_COMP_PROV" p
CROSS JOIN (VALUES
    ('SEGURO DENTAL - PLAN AVANZADO',    'fixed_uf', 0.19::NUMERIC(12,4), 'UF', DATE '2025-02-01', NULL::DATE),
    ('SEGURO DE SALUD - PLAN DESTACADO', 'fixed_uf', 0.25::NUMERIC(12,4), 'UF', DATE '2025-01-01', DATE '2025-01-01'),
    ('SEGURO DE SALUD - PLAN DESTACADO', 'fixed_uf', 0.83::NUMERIC(12,4), 'UF', DATE '2025-02-01', NULL::DATE),
    ('SEGURO CATASTROFICO - PLAN AVANZADO', 'fixed_uf', 0.13::NUMERIC(12,4), 'UF', DATE '2025-02-01', NULL::DATE)
) AS entry(name, cost_type, cost_value, cost_currency, valid_from, valid_to)
WHERE p.name = 'METLIFE'
  AND NOT EXISTS (
      SELECT 1
      FROM "PAY_COMP_PLAN" cp
      WHERE cp.provider_id = p.id
        AND cp.name        = entry.name
        AND cp.valid_from  = entry.valid_from
  );

-- ============================================================
-- 7. PDF payslip templates
-- ============================================================
-- Migrates the one real template that used to live only as a git-tracked
-- JSON file (pf-payroll's former
-- infrastructure/pdf_import/templates/walmart-chile/v1.json, now deleted --
-- see pf-payroll/docs/proposals/pdf-template-management-design-plan.md).
-- This keeps a fresh `make seed-real` bootstrapped with the real template
-- with no manual POST /payroll/templates call required to reach parity.
INSERT INTO "PAY_PDF_TEMPLATE" (
    template_id, employer_id, employer_name, employer_match_pattern, version, is_active
)
SELECT
    'walmart-chile-v1',
    e.id,
    'WALMART-CHILE',
    '(?i)walmart-chile|walmart\s+chile',
    1,
    TRUE
FROM "PAY_EMPLOYER" e
WHERE e.name = 'WALMART-CHILE'
ON CONFLICT (template_id) DO UPDATE
SET
    employer_id             = EXCLUDED.employer_id,
    employer_name           = EXCLUDED.employer_name,
    employer_match_pattern  = EXCLUDED.employer_match_pattern,
    version                 = EXCLUDED.version,
    is_active               = EXCLUDED.is_active,
    updated_at              = NOW();

-- Fields are fully replaced (delete+insert) rather than individually
-- upserted -- no natural per-field unique key exists, and this mirrors the
-- same delete-then-reinsert convention pf-payroll's own import_rows()
-- already uses for PAY_ITEM rows (see spreadsheet-export-design-plan.md's
-- Correction 2). Safe here: this is seed data, re-run idempotently, not a
-- live request path.
DELETE FROM "PAY_PDF_TEMPLATE_FIELD"
WHERE template_id = (
    SELECT id FROM "PAY_PDF_TEMPLATE" WHERE template_id = 'walmart-chile-v1'
);

INSERT INTO "PAY_PDF_TEMPLATE_FIELD" (
    template_id, pdf_label_pattern, concept_code, kind, confidence
)
SELECT t.id, f.pdf_label_pattern, f.concept_code, f.kind, f.confidence
FROM "PAY_PDF_TEMPLATE" t
CROSS JOIN (VALUES
    ('(?i)^SUELDO$',                                   'SALARY_BASE',                           'income',   0.90),
    ('(?i)GRATIFICACION\s+LEGAL',                      'LEGAL_GRATUITY',                        'income',   0.90),
    ('(?i)ASIGNACI[OÓ]N\s+TRAB\.?\s+H[IÍ]BRIDO',       'TELEWORK_REFUND',                       'income',   0.60),
    ('(?i)APORTE\s+SEGURO\s+DE\s+SALUD',               'HEALTH_INSURANCE_EMPLOYER_CONTRIBUTION','income',   0.75),
    ('(?i)^IMPUESTO$',                                 'INCOME_TAX',                            'discount', 0.90),
    ('(?i)COT\.\s*SEG\.\s*CES\.',                      'UNEMPLOYMENT_INSURANCE',                'discount', 0.90),
    ('(?i)ESENCIAL\s+LEGAL',                           'HEALTH_BASE',                           'discount', 0.60),
    ('(?i)COMISI[OÓ]N\s+AFP',                          'PENSION_ADDITIONAL',                    'discount', 0.90),
    ('(?i)FONDO\s+RETIRO\s+AFP',                       'PENSION_BASE',                          'discount', 0.60),
    ('(?i)ESENCIAL\s+ADICIONAL',                       'HEALTH_ADDITIONAL_UF',                  'discount', 0.60),
    ('(?i)SEGURO\s+(DENTAL|DE\s+SALUD|CATASTR[OÓ]FICO)','HEALTH_INSURANCE',                     'discount', 0.90),
    ('(?i)^AGUINALDO',                                 'HOLIDAY_BONUS',                         'income',   0.85),
    ('(?i)ANTICIPO\s+AGUINALDO',                       'HOLIDAY_BONUS_ADVANCE',                 'discount', 0.90),
    ('(?i)BONO\s+POR\s+DISPONIBILIDAD',                'AVAILABILITY_BONUS',                    'income',   0.90),
    ('(?i)REAJUSTE\s+GRATI\.?\s*MENSUAL',              'LEGAL_GRATUITY_ADJUSTMENT',             'income',   0.85),
    ('(?i)INCENTIVO\s+VACACIONES',                     'VACATION_INCENTIVE',                    'income',   0.90),
    ('(?i)ANTICIPO\s+BONO\s+VACACIONES',               'VACATION_BONUS_ADVANCE',                'discount', 0.90),
    ('(?i)DSCTO\s+LICEN[\s-]*AUSEN\s+MES\s+ANT',       'PRIOR_MONTH_LEAVE_ABSENCE_DISCOUNT',    'discount', 0.85),
    ('(?i)DIF\.?\s*SUELDO\s+MES\s+ANTERIOR',           'PRIOR_SALARY_DIFFERENCE',               'income',   0.85),
    ('(?i)^CCAF\s+.*VIGENTE$',                         'CCAF_LOAN',                             'discount', 0.90)
) AS f(pdf_label_pattern, concept_code, kind, confidence)
WHERE t.template_id = 'walmart-chile-v1';