-- CashGo — idempotency keys + payment references
BEGIN;

-- Prevents double-charges when the client retries a transfer after a timeout
ALTER TABLE transactions
    ADD COLUMN idempotency_key VARCHAR(64);
CREATE UNIQUE INDEX uq_txn_idem
    ON transactions (idempotency_key) WHERE idempotency_key IS NOT NULL;

-- Payment-provider top-up intents (Paystack reference → wallet credit status)
CREATE TABLE payment_intents (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID          NOT NULL REFERENCES users(id),
    wallet_id   UUID          REFERENCES wallets(id),
    reference   VARCHAR(80)   NOT NULL UNIQUE,   -- provider reference
    currency    CHAR(3)       NOT NULL,
    amount      NUMERIC(18,4) NOT NULL,
    provider    VARCHAR(24)   NOT NULL DEFAULT 'paystack',
    status      VARCHAR(16)   NOT NULL DEFAULT 'INITIATED',  -- INITIATED|PAID|FAILED
    payment_url TEXT,                                    -- hosted checkout page
    paid_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT now()
);
CREATE INDEX idx_intents_user ON payment_intents (user_id);

COMMIT;
