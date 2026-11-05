"""Paystack top-up integration.

Flow: POST /wallets/topup → PaymentIntent + hosted checkout URL → user pays →
Paystack calls /payments/paystack/webhook (HMAC-SHA512 verified) → wallet
credited + ledger entry. Without PAYSTACK_SECRET_KEY the intent is instantly
marked PAID so the dev flow still tops up.
"""
import hashlib
import hmac
import uuid
from datetime import datetime, timezone
from decimal import Decimal

import httpx

from app.core.config import settings

PAYSTACK_API = "https://api.paystack.co"

# Paystack doesn't settle ZWG/ZMW/TZS natively — for dev we charge the
# equivalent in ZAR (their supported rail) and credit the chosen currency.
_SETTLE_CCY = "ZAR"


def create_intent(reference: str, email: str, amount: Decimal,
                  currency: str) -> dict:
    """Returns {'payment_url': str|None, 'dev_mode': bool}."""
    if not settings.PAYSTACK_SECRET_KEY:
        return {"payment_url": None, "dev_mode": True}
    res = httpx.post(
        f"{PAYSTACK_API}/transaction/initialize",
        headers={"Authorization": f"Bearer {settings.PAYSTACK_SECRET_KEY}"},
        json={
            "reference": reference,
            "email": email,
            # Paystack wants the subunit (cents) amount
            "amount": int(amount * 100),
            "currency": _SETTLE_CCY,
            "metadata": {"wallet_currency": currency},
        },
        timeout=10.0,
    )
    res.raise_for_status()
    data = res.json()["data"]
    return {"payment_url": data["authorization_url"], "dev_mode": False}


def new_reference() -> str:
    return f"CG-{uuid.uuid4().hex[:20]}"


def verify_webhook(raw_body: bytes, signature: str | None) -> dict | None:
    """HMAC-SHA512 check; returns parsed event dict or None if invalid.
    In dev mode (no secret) accepts everything."""
    if not settings.PAYSTACK_SECRET_KEY:
        import json
        return json.loads(raw_body)
    expected = hmac.new(settings.PAYSTACK_SECRET_KEY.encode(),
                        raw_body, hashlib.sha512).hexdigest()
    if not signature or not hmac.compare_digest(expected, signature):
        return None
    import json
    return json.loads(raw_body)


def verify_transaction(reference: str) -> bool:
    """Server-side confirm — used when the webhook hasn't arrived (dev/testing)."""
    if not settings.PAYSTACK_SECRET_KEY:
        return True
    res = httpx.get(f"{PAYSTACK_API}/transaction/verify/{reference}",
                    headers={"Authorization": f"Bearer {settings.PAYSTACK_SECRET_KEY}"},
                    timeout=10.0)
    res.raise_for_status()
    return res.json()["data"]["status"] == "success"


def mark_paid() -> datetime:
    return datetime.now(timezone.utc)
