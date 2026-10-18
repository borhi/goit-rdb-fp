-- =====================================================================
-- Фінальний проєкт: Реляційні бази даних (PostgreSQL)
-- Датасет: infectious_cases.csv
-- Запуск:  psql -d <db> -f sql/final_project.sql   (з кореня репозиторію)
-- =====================================================================


-- =====================================================================
-- 1. Завантаження даних
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS pandemic;
SET search_path TO pandemic;

DROP TABLE IF EXISTS infectious_cases_normalized;
DROP TABLE IF EXISTS entities;
DROP TABLE IF EXISTS infectious_cases;

-- Сира таблиця повторює структуру CSV. Показники захворювань зберігаються
-- як TEXT, бо в CSV порожні значення — це порожні рядки (''), а не числа.
CREATE TABLE infectious_cases (
    entity               TEXT,
    code                 TEXT,
    year                 INTEGER,
    number_yaws          TEXT,
    polio_cases          TEXT,
    cases_guinea_worm    TEXT,
    number_rabies        TEXT,
    number_malaria       TEXT,
    number_hiv           TEXT,
    number_tuberculosis  TEXT,
    number_smallpox      TEXT,
    number_cholera_cases TEXT
);

-- Імпорт CSV (клієнтська команда psql). FORCE_NOT_NULL зберігає порожні
-- значення як '' — саме так, як вони записані у файлі.
\copy infectious_cases FROM 'data/infectious_cases.csv' WITH (FORMAT csv, HEADER true, FORCE_NOT_NULL (code, number_yaws, polio_cases, cases_guinea_worm, number_rabies, number_malaria, number_hiv, number_tuberculosis, number_smallpox, number_cholera_cases))

-- Перегляд даних
SELECT COUNT(*) AS total_rows FROM infectious_cases;

SELECT *
FROM infectious_cases
LIMIT 10;


-- =====================================================================
-- 2. Нормалізація до 3НФ
-- =====================================================================
-- У сирій таблиці code функціонально залежить від entity (а не від
-- ключа entity + year) — транзитивна залежність, що порушує 3НФ.
-- Виносимо пару (entity, code) в окремий довідник entities.

CREATE TABLE entities (
    id     SERIAL PRIMARY KEY,
    entity TEXT NOT NULL UNIQUE,
    code   TEXT              -- NULL для регіонів / груп країн без ISO-коду
);

INSERT INTO entities (entity, code)
SELECT DISTINCT entity, NULLIF(code, '')
FROM infectious_cases
ORDER BY entity;

-- Таблиця показників: замість entity та code — зовнішній ключ entity_id.
-- Порожні рядки перетворюються на NULL, значення — на NUMERIC.
CREATE TABLE infectious_cases_normalized (
    id                   SERIAL PRIMARY KEY,
    entity_id            INTEGER NOT NULL REFERENCES entities (id),
    year                 INTEGER NOT NULL,
    number_yaws          NUMERIC,
    polio_cases          NUMERIC,
    cases_guinea_worm    NUMERIC,
    number_rabies        NUMERIC,
    number_malaria       NUMERIC,
    number_hiv           NUMERIC,
    number_tuberculosis  NUMERIC,
    number_smallpox      NUMERIC,
    number_cholera_cases NUMERIC,
    UNIQUE (entity_id, year)
);

INSERT INTO infectious_cases_normalized (
    entity_id, year,
    number_yaws, polio_cases, cases_guinea_worm, number_rabies, number_malaria,
    number_hiv, number_tuberculosis, number_smallpox, number_cholera_cases
)
SELECT
    e.id,
    ic.year,
    NULLIF(ic.number_yaws, '')::NUMERIC,
    NULLIF(ic.polio_cases, '')::NUMERIC,
    NULLIF(ic.cases_guinea_worm, '')::NUMERIC,
    NULLIF(ic.number_rabies, '')::NUMERIC,
    NULLIF(ic.number_malaria, '')::NUMERIC,
    NULLIF(ic.number_hiv, '')::NUMERIC,
    NULLIF(ic.number_tuberculosis, '')::NUMERIC,
    NULLIF(ic.number_smallpox, '')::NUMERIC,
    NULLIF(ic.number_cholera_cases, '')::NUMERIC
FROM infectious_cases AS ic
JOIN entities AS e ON e.entity = ic.entity
ORDER BY e.id, ic.year;

-- Перевірка: кількість рядків має збігатися з сирою таблицею
SELECT
    (SELECT COUNT(*) FROM infectious_cases)            AS raw_rows,
    (SELECT COUNT(*) FROM entities)                    AS entities_rows,
    (SELECT COUNT(*) FROM infectious_cases_normalized) AS normalized_rows;

SELECT * FROM entities ORDER BY id LIMIT 10;

SELECT * FROM infectious_cases_normalized ORDER BY id LIMIT 10;


-- =====================================================================
-- 3. Аналіз Number_rabies
-- =====================================================================

SELECT
    e.id,
    e.entity,
    e.code,
    ROUND(AVG(n.number_rabies), 2) AS avg_rabies,
    MIN(n.number_rabies)           AS min_rabies,
    MAX(n.number_rabies)           AS max_rabies,
    ROUND(SUM(n.number_rabies), 2) AS sum_rabies
FROM infectious_cases_normalized AS n
JOIN entities AS e ON e.id = n.entity_id
WHERE n.number_rabies IS NOT NULL
GROUP BY e.id, e.entity, e.code
ORDER BY avg_rabies DESC
LIMIT 10;


-- =====================================================================
-- 4. Колонка різниці в роках (вбудовані функції)
-- =====================================================================

SELECT
    e.entity,
    n.year,
    MAKE_DATE(n.year, 1, 1)                                         AS year_start_date,
    CURRENT_DATE                                                    AS today,
    EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAKE_DATE(n.year, 1, 1)))::INT AS years_diff
FROM infectious_cases_normalized AS n
JOIN entities AS e ON e.id = n.entity_id
ORDER BY n.id
LIMIT 10;


-- =====================================================================
-- 5. Власні функції
-- =====================================================================

-- 5.1 Різниця в роках між 1 січня заданого року та поточною датою
CREATE OR REPLACE FUNCTION fn_years_diff(p_year INTEGER)
RETURNS INTEGER
LANGUAGE sql
STABLE
AS $$
    SELECT EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAKE_DATE(p_year, 1, 1)))::INT;
$$;

-- 5.2 Середня кількість захворювань за період: річна кількість / дільник
--     (12 — місяць, 4 — квартал, 2 — півріччя). Дільник 0 або NULL → NULL.
CREATE OR REPLACE FUNCTION fn_avg_cases_per_period(p_cases_per_year NUMERIC, p_divider NUMERIC)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT ROUND(p_cases_per_year / NULLIF(p_divider, 0), 2);
$$;

-- Перевірка fn_years_diff на прикладі з умови
SELECT 1996 AS year, MAKE_DATE(1996, 1, 1) AS year_start_date, fn_years_diff(1996) AS years_diff;

-- Використання fn_years_diff у запиті
SELECT
    e.entity,
    n.year,
    fn_years_diff(n.year) AS years_diff
FROM infectious_cases_normalized AS n
JOIN entities AS e ON e.id = n.entity_id
ORDER BY n.id
LIMIT 10;

-- Використання fn_avg_cases_per_period: лише записи, де number_rabies
-- є числом (у сирій таблиці — перевірка регулярним виразом)
SELECT
    entity,
    year,
    number_rabies::NUMERIC                                     AS rabies_per_year,
    fn_avg_cases_per_period(number_rabies::NUMERIC, 12)        AS avg_per_month,
    fn_avg_cases_per_period(number_rabies::NUMERIC, 4)         AS avg_per_quarter,
    fn_avg_cases_per_period(number_rabies::NUMERIC, 2)         AS avg_per_half_year
FROM infectious_cases
WHERE number_rabies ~ '^-?[0-9]+(\.[0-9]+)?$'
ORDER BY entity, year
LIMIT 10;
