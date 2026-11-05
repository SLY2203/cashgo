-- CashGo — agent attribution on payment intents (agent cash-in receipts)
BEGIN;

ALTER TABLE payment_intents
    ADD COLUMN agent_id UUID REFERENCES pickup_agents(id);

CREATE INDEX idx_intents_agent ON payment_intents (agent_id, created_at);

COMMIT;
