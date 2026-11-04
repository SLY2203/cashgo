-- CashGo MVP — Initial Schema (PostgreSQL 14+ / PostGIS 3+)
BEGIN;

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
CREATE TYPE kyc_status AS ENUM ('PENDING', 'VERIFIED', 'REJECTED', 'SUSPENDED');
CREATE TYPE txn_status AS ENUM (
    'PENDING',          -- created, awaiting funding/escrow
    'READY_FOR_PICKUP', -- funded, voucher active
    'COMPLETED',        -- cash paid out by agent
    'CANCELLED',
    'FAILED',
    'EXPIRED'
);
CREATE TYPE payout_method AS ENUM ('CASH_PICKUP', 'MOBILE_MONEY', 'BANK');

-- ---------------------------------------------------------------------------
-- Users / sender profiles
-- ---------------------------------------------------------------------------
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone           VARCHAR(20)  NOT NULL UNIQUE,       -- E.164
    full_name       VARCHAR(120) NOT NULL,
    email           VARCHAR(255),
    country_code    CHAR(2)      NOT NULL,              -- ISO 3166-1 alpha-2, sender's country
    kyc_status      kyc_status   NOT NULL DEFAULT 'PENDING',
    kyc_id_number   VARCHAR(64),
    kyc_document    VARCHAR(32),                        -- PASSPORT | NATIONAL_ID | DRIVERS_LICENSE
    pin_hash        TEXT,                               -- bcrypt hashed app PIN
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Corridor fee configuration (admin-controlled pricing)
-- ---------------------------------------------------------------------------
CREATE TABLE corridor_fee_configs (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_country   CHAR(2)        NOT NULL,
    dest_country     CHAR(2)        NOT NULL,
    send_currency    CHAR(3)        NOT NULL,           -- ISO 4217 e.g. USD
    payout_currency  CHAR(3)        NOT NULL,           -- e.g. NGN, KES, GHS

    -- tiered fee structure
    min_amount       NUMERIC(18,4)  NOT NULL,
    max_amount       NUMERIC(18,4)  NOT NULL,
    flat_fee         NUMERIC(18,4)  NOT NULL DEFAULT 0,
    percent_fee      NUMERIC(6,4)   NOT NULL DEFAULT 0, -- e.g. 0.0150 = 1.5%
    fx_margin_markup NUMERIC(6,4)   NOT NULL DEFAULT 0, -- spread applied on mid-market rate

    is_active        BOOLEAN        NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMPTZ    NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ    NOT NULL DEFAULT now(),

    CONSTRAINT chk_tier_range    CHECK (max_amount > min_amount),
    CONSTRAINT chk_fees_nonneg   CHECK (flat_fee >= 0 AND percent_fee >= 0 AND fx_margin_markup >= 0),
    CONSTRAINT uq_corridor_tier  UNIQUE (source_country, dest_country,
                                       send_currency, payout_currency,
                                       min_amount, max_amount)
);
CREATE INDEX idx_fee_corridor ON corridor_fee_configs
    (source_country, dest_country, is_active);

-- ---------------------------------------------------------------------------
-- FX quote locks (60-second guaranteed pricing)
-- ---------------------------------------------------------------------------
CREATE TABLE fx_quotes (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_country   CHAR(2)        NOT NULL,
    dest_country     CHAR(2)        NOT NULL,
    send_currency    CHAR(3)        NOT NULL,
    payout_currency  CHAR(3)        NOT NULL,
    send_amount      NUMERIC(18,4)  NOT NULL,
    mid_rate         NUMERIC(20,8)  NOT NULL,  -- raw market rate
    applied_rate     NUMERIC(20,8)  NOT NULL,  -- mid_rate * (1 - fx_margin_markup)
    fee_amount       NUMERIC(18,4)  NOT NULL,
    payout_amount    NUMERIC(18,4)  NOT NULL,
    fee_config_id    UUID REFERENCES corridor_fee_configs(id),
    expires_at       TIMESTAMPTZ    NOT NULL,
    consumed_at      TIMESTAMPTZ,              -- set when converted into a transfer
    created_at       TIMESTAMPTZ    NOT NULL DEFAULT now()
);
CREATE INDEX idx_fx_quotes_expiry ON fx_quotes (expires_at);

-- ---------------------------------------------------------------------------
-- Transactions / remittances
-- ---------------------------------------------------------------------------
CREATE TABLE transactions (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id          UUID          NOT NULL REFERENCES users(id),
    quote_id           UUID          REFERENCES fx_quotes(id),

    recipient_phone    VARCHAR(20)   NOT NULL,
    recipient_name     VARCHAR(120)  NOT NULL,
    payout_method      payout_method NOT NULL DEFAULT 'CASH_PICKUP',

    send_currency      CHAR(3)       NOT NULL,
    payout_currency    CHAR(3)       NOT NULL,
    send_amount        NUMERIC(18,4) NOT NULL,
    fee_amount         NUMERIC(18,4) NOT NULL,
    exchange_rate      NUMERIC(20,8) NOT NULL,  -- locked rate
    payout_amount      NUMERIC(18,4) NOT NULL,

    voucher_code       VARCHAR(12)   NOT NULL UNIQUE,  -- CG-XXXX-XXXX
    status             txn_status    NOT NULL DEFAULT 'PENDING',

    pickup_agent_id    UUID,                          -- FK added below
    paid_out_at        TIMESTAMPTZ,
    status_history     JSONB         NOT NULL DEFAULT '[]',

    created_at         TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ   NOT NULL DEFAULT now()
);
CREATE INDEX idx_txn_sender  ON transactions (sender_id);
CREATE INDEX idx_txn_status  ON transactions (status);
CREATE INDEX idx_txn_voucher ON transactions (voucher_code);

-- ---------------------------------------------------------------------------
-- Cash pickup agents / booths (PostGIS)
-- ---------------------------------------------------------------------------
CREATE TABLE pickup_agents (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_name           VARCHAR(160) NOT NULL,
    city                 VARCHAR(100) NOT NULL,
    country_code         CHAR(2)      NOT NULL,
    address              TEXT,
    supported_currencies CHAR(3)[]    NOT NULL DEFAULT '{}',
    operating_hours      JSONB        NOT NULL DEFAULT '{}',  -- {"mon": "08:00-18:00", ...}
    phone                VARCHAR(20),
    is_active            BOOLEAN      NOT NULL DEFAULT TRUE,
    location             GEOGRAPHY(POINT, 4326) NOT NULL,     -- lon/lat WGS84
    created_at           TIMESTAMPTZ  NOT NULL DEFAULT now()
);

ALTER TABLE transactions
    ADD CONSTRAINT fk_txn_pickup_agent
    FOREIGN KEY (pickup_agent_id) REFERENCES pickup_agents(id);

CREATE INDEX idx_agents_geo     ON pickup_agents USING GIST (location);
CREATE INDEX idx_agents_country ON pickup_agents (country_code, is_active);

-- Example distance query used by GET /agents/nearest/:
--   SELECT *, ST_Distance(location, ST_MakePoint(:lon,:lat)::geography) AS dist_m
--   FROM pickup_agents
--   WHERE is_active AND country_code = :cc
--     AND ST_DWithin(location, ST_MakePoint(:lon,:lat)::geography, :radius_m)
--   ORDER BY location <-> ST_MakePoint(:lon,:lat)::geography;

COMMIT;
