-- LAB 1: FISHERIES STAR SCHEMA (PostgreSQL 16+)
-- Run the entire file in VS Code with SQLTools, pgAdmin, or DBeaver.
-- WARNING: This recreates the fisheries_dw schema.

DROP SCHEMA IF EXISTS fisheries_dw CASCADE;
CREATE SCHEMA fisheries_dw;
SET search_path TO fisheries_dw, public;

-- DIMENSIONS
CREATE TABLE dim_date (
    date_key INTEGER PRIMARY KEY,
    full_date DATE NOT NULL UNIQUE,
    calendar_year INTEGER NOT NULL,
    month_number INTEGER NOT NULL,
    month_name VARCHAR(15) NOT NULL,
    quarter_number INTEGER NOT NULL,
    day_number INTEGER NOT NULL
);

CREATE TABLE dim_port (
    port_key SERIAL PRIMARY KEY,
    port_code VARCHAR(20) UNIQUE NOT NULL,
    port_name VARCHAR(100) NOT NULL,
    municipality VARCHAR(100) NOT NULL,
    cooperative_name VARCHAR(120) NOT NULL
);

CREATE TABLE dim_species (
    species_key SERIAL PRIMARY KEY,
    species_code VARCHAR(20) UNIQUE NOT NULL,
    species_name VARCHAR(100) NOT NULL,
    fish_category VARCHAR(60) NOT NULL
);

-- SCD TYPE 2: retain old vessel versions for historical reports
CREATE TABLE dim_vessel (
    vessel_key SERIAL PRIMARY KEY,
    vessel_code VARCHAR(20) NOT NULL,
    vessel_name VARCHAR(100) NOT NULL,
    vessel_type VARCHAR(60) NOT NULL,
    cooperative_name VARCHAR(120) NOT NULL,
    valid_from DATE NOT NULL,
    valid_to DATE,
    is_current BOOLEAN NOT NULL DEFAULT TRUE,
    CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE UNIQUE INDEX uq_vessel_current
ON dim_vessel(vessel_code) WHERE is_current = TRUE;

-- FACT TABLE
CREATE TABLE fact_landing (
    landing_key BIGSERIAL PRIMARY KEY,
    date_key INTEGER NOT NULL REFERENCES dim_date(date_key),
    port_key INTEGER NOT NULL REFERENCES dim_port(port_key),
    species_key INTEGER NOT NULL REFERENCES dim_species(species_key),
    vessel_key INTEGER NOT NULL REFERENCES dim_vessel(vessel_key),
    quantity_kg NUMERIC(12,2) NOT NULL CHECK (quantity_kg > 0),
    price_per_kg NUMERIC(12,2) NOT NULL CHECK (price_per_kg >= 0),
    total_value NUMERIC(14,2) GENERATED ALWAYS AS
        (quantity_kg * price_per_kg) STORED
);

CREATE INDEX idx_fact_date ON fact_landing(date_key);
CREATE INDEX idx_fact_port ON fact_landing(port_key);
CREATE INDEX idx_fact_species ON fact_landing(species_key);

-- DATE DIMENSION: 2020-01-01 through 2030-12-31
INSERT INTO dim_date
(date_key, full_date, calendar_year, month_number, month_name, quarter_number, day_number)
SELECT
    TO_CHAR(d::date, 'YYYYMMDD')::INTEGER,
    d::date,
    EXTRACT(YEAR FROM d)::INTEGER,
    EXTRACT(MONTH FROM d)::INTEGER,
    TO_CHAR(d::date, 'FMMonth'),
    EXTRACT(QUARTER FROM d)::INTEGER,
    EXTRACT(DAY FROM d)::INTEGER
FROM GENERATE_SERIES(DATE '2020-01-01', DATE '2030-12-31', INTERVAL '1 day') AS g(d);

-- SAMPLE DIMENSIONS
INSERT INTO dim_port (port_code, port_name, municipality, cooperative_name) VALUES
('P001','Sibutu Main Port','Sibutu','Sibutu Fishers Cooperative'),
('P002','Bongao Fish Port','Bongao','Bongao Fisheries Cooperative'),
('P003','Sitangkai Port','Sitangkai','Sitangkai Fishers Cooperative'),
('P004','Tandubas Landing','Tandubas','Tandubas Fishers Cooperative'),
('P005','Simunul Landing','Simunul','Simunul Fisheries Cooperative');

INSERT INTO dim_species (species_code, species_name, fish_category) VALUES
('SP001','Yellowfin Tuna','Tuna'),
('SP002','Skipjack Tuna','Tuna'),
('SP003','Round Scad','Small Pelagic'),
('SP004','Indian Mackerel','Small Pelagic'),
('SP005','Grouper','Reef Fish'),
('SP006','Snapper','Reef Fish'),
('SP007','Squid','Cephalopod'),
('SP008','Spanish Mackerel','Large Pelagic');

INSERT INTO dim_vessel
(vessel_code, vessel_name, vessel_type, cooperative_name, valid_from, valid_to, is_current) VALUES
('V001','Sea Star 1','Motorized Boat','Sibutu Fishers Cooperative','2020-01-01',NULL,TRUE),
('V002','Ocean Pearl','Motorized Boat','Bongao Fisheries Cooperative','2020-01-01',NULL,TRUE),
('V003','Blue Wave','Fishing Boat','Sitangkai Fishers Cooperative','2020-01-01',NULL,TRUE),
('V004','Sea Hunter','Fishing Boat','Tandubas Fishers Cooperative','2020-01-01',NULL,TRUE),
('V005','Island Catch','Motorized Boat','Simunul Fishers Cooperative','2020-01-01',NULL,TRUE),
('V006','Marina 6','Fishing Boat','Sibutu Fishers Cooperative','2020-01-01',NULL,TRUE),
('V007','Golden Fish','Motorized Boat','Bongao Fisheries Cooperative','2020-01-01',NULL,TRUE),
('V008','Sea Breeze','Fishing Boat','Sitangkai Fishers Cooperative','2020-01-01',NULL,TRUE);

-- 240 GENERATED FACT ROWS (minimum required: 200)
INSERT INTO fact_landing
(date_key, port_key, species_key, vessel_key, quantity_kg, price_per_kg)
SELECT
    TO_CHAR((DATE '2020-01-01' + ((n * 13) % 4017))::date, 'YYYYMMDD')::INTEGER,
    ((n - 1) % 5) + 1,
    ((n - 1) % 8) + 1,
    ((n - 1) % 8) + 1,
    (25 + ((n * 17) % 176))::NUMERIC(12,2),
    (80 + ((n * 7) % 121))::NUMERIC(12,2)
FROM GENERATE_SERIES(1, 240) AS s(n);

-- QUERY 1: KILOGRAMS PER MONTH
SELECT d.calendar_year, d.month_number, d.month_name,
       SUM(f.quantity_kg) AS total_kg
FROM fact_landing f
JOIN dim_date d ON d.date_key = f.date_key
GROUP BY d.calendar_year, d.month_number, d.month_name
ORDER BY d.calendar_year, d.month_number;

-- QUERY 2: TOP SPECIES PER PORT
WITH species_port AS (
    SELECT p.port_name, sp.species_name,
           SUM(f.quantity_kg) AS total_kg,
           RANK() OVER (PARTITION BY p.port_key ORDER BY SUM(f.quantity_kg) DESC) AS species_rank
    FROM fact_landing f
    JOIN dim_port p ON p.port_key = f.port_key
    JOIN dim_species sp ON sp.species_key = f.species_key
    GROUP BY p.port_key, p.port_name, sp.species_key, sp.species_name
)
SELECT port_name, species_name, total_kg, species_rank
FROM species_port
WHERE species_rank = 1
ORDER BY port_name;

-- QUERY 3: VALUE PER COOPERATIVE
SELECT v.cooperative_name, SUM(f.total_value) AS total_value
FROM fact_landing f
JOIN dim_vessel v ON v.vessel_key = f.vessel_key
GROUP BY v.cooperative_name
ORDER BY total_value DESC;

-- SCD TYPE 2 DEMONSTRATION: VESSEL V001
-- Save old historical report before changing the vessel.
CREATE TEMP TABLE report_before AS
SELECT v.vessel_code, v.vessel_name, v.cooperative_name,
       SUM(f.quantity_kg) AS total_kg, SUM(f.total_value) AS total_value
FROM fact_landing f
JOIN dim_vessel v ON v.vessel_key = f.vessel_key
WHERE v.vessel_code = 'V001'
GROUP BY v.vessel_code, v.vessel_name, v.cooperative_name;

-- Expire old version and add a new version.
UPDATE dim_vessel
SET valid_to = DATE '2026-11-07', is_current = FALSE
WHERE vessel_code = 'V001' AND is_current = TRUE;

INSERT INTO dim_vessel
(vessel_code, vessel_name, vessel_type, cooperative_name, valid_from, valid_to, is_current)
VALUES
('V001','Sea Star 1 - Updated','Motorized Boat',
 'Bongao Fisheries Cooperative',DATE '2026-11-08',NULL,TRUE);

-- New fact record points to the new vessel version.
INSERT INTO fact_landing
(date_key, port_key, species_key, vessel_key, quantity_kg, price_per_kg)
SELECT 20261108, 1, 1, vessel_key, 150, 125
FROM dim_vessel
WHERE vessel_code = 'V001' AND is_current = TRUE;

-- Compare historical report before and after; expected result is TRUE.
CREATE TEMP TABLE report_after AS
SELECT v.vessel_code, v.vessel_name, v.cooperative_name,
       SUM(f.quantity_kg) AS total_kg, SUM(f.total_value) AS total_value
FROM fact_landing f
JOIN dim_vessel v ON v.vessel_key = f.vessel_key
WHERE v.vessel_code = 'V001' AND f.date_key < 20261108
GROUP BY v.vessel_code, v.vessel_name, v.cooperative_name;

SELECT b.vessel_code, b.vessel_name, b.cooperative_name,
       b.total_kg AS kg_before, a.total_kg AS kg_after,
       b.total_value AS value_before, a.total_value AS value_after,
       (b.total_kg = a.total_kg AND b.total_value = a.total_value) AS historical_report_unchanged
FROM report_before b
JOIN report_after a USING (vessel_code, vessel_name, cooperative_name);

-- Verify SCD Type 2 versions for V001.
SELECT vessel_code, vessel_name, cooperative_name, valid_from, valid_to, is_current
FROM dim_vessel WHERE vessel_code = 'V001' ORDER BY valid_from;

-- FINAL ROW COUNTS (fact_landing should show 241)
SELECT 'dim_date' AS table_name, COUNT(*) AS row_count FROM dim_date
UNION ALL SELECT 'dim_port', COUNT(*) FROM dim_port
UNION ALL SELECT 'dim_species', COUNT(*) FROM dim_species
UNION ALL SELECT 'dim_vessel', COUNT(*) FROM dim_vessel
UNION ALL SELECT 'fact_landing', COUNT(*) FROM fact_landing
ORDER BY table_name;
