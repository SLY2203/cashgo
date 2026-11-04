-- CashGo — Auth (OTP) + wallet/escrow ledger
BEGIN;

-- ---------------------------------------------------------------------------
-- OTP codes (phone verification / login)
-- ---------------------------------------------------------------------------
CREATE TABLE otp_codes (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone       VARCHAR(20)  NOT NULL,
    code_hash   TEXT         NOT NULL,          -- sha256(code + salt), never plaintext
    purpose     VARCHAR(16)  NOT NULL,          -- 'login' | 'register'
    expires_at  TIMESTAMPTZ  NOT NULL,
    consumed_at TIMESTAMPTZ,
    attempts    SMALLINT     NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX idx_otp_phone ON otp_codes (phone, purpose, expires_at);

-- ---------------------------------------------------------------------------
-- Wallets — one per user per currency
-- ---------------------------------------------------------------------------
CREATE TABLE wallets (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID          NOT NULL REFERENCES users(id),
    currency    CHAR(3)       NOT NULL,
    balance     NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (balance >= 0),
    escrowed    NUMERIC(18,4) NOT NULL DEFAULT 0 CHECK (escrowed >= 0),
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT uq_wallet_user_currency UNIQUE (user_id, currency)
);

-- ---------------------------------------------------------------------------
-- Double-entry-style ledger — every balance/escrow movement is recorded
-- ---------------------------------------------------------------------------
CREATE TABLE ledger_entries (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id       UUID          NOT NULL REFERENCES wallets(id),
    transaction_id  UUID          REFERENCES transactions(id),
    entry_type      VARCHAR(24)   NOT NULL,  -- TOPUP | ESCROW_HOLD | ESCROW_RELEASE |
                                           --  ESCROW_DEBIT | REFUND | PAYOUT_SETTLE
    amount          NUMERIC(18,4) NOT NULL,
    balance_after   NUMERIC(18,4) NOT NULL,
    escrowed_after  NUMERIC(18,4) NOT NULL,
    memo            VARCHAR(200),
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT now()
);
CREATE INDEX idx_ledger_wallet ON ledger_entries (wallet_id);
CREATE INDEX idx_ledger_txn    ON ledger_entries (transaction_id);

COMMIT;
