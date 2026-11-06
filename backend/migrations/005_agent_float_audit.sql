-- CashGo — agent floats + audit trail
BEGIN;

-- Each booth's cash position per currency.
-- cash-out (withdrawal) debits float; cash-in (top-up) credits it.
CREATE TABLE agent_floats (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id   UUID          NOT NULL REFERENCES pickup_agents(id),
    currency   CHAR(3)       NOT NULL,
    balance    NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (balance >= 0),
    UNIQUE (agent_id, currency)
);

-- Seed every active agent a starting float in its local currency
INSERT INTO agent_floats (agent_id, currency, balance)
SELECT id, CASE country_code
             WHEN 'ZW' THEN 'ZWG' WHEN 'ZM' THEN 'ZMW'
             WHEN 'ZA' THEN 'ZAR' WHEN 'TZ' THEN 'TZS'
             ELSE 'USD' END, 10000
FROM pickup_agents WHERE is_active
ON CONFLICT DO NOTHING;

-- Immutable audit trail of money movements
CREATE TABLE audit_events (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor       VARCHAR(40),              -- user_id / agent_id / 'admin'
    action      VARCHAR(40) NOT NULL,     -- TOPUP, TRANSFER, REDEEM, CASH_IN, P2P...
    ref         VARCHAR(80),              -- txn id / voucher / reference
    detail      JSONB DEFAULT '{}',
    ip          INET,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_actor ON audit_events (actor, created_at);
CREATE INDEX idx_audit_action ON audit_events (action, created_at);

COMMIT;
