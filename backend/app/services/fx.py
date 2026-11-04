"""FX rate service: fetches mid-market rates with an in-memory TTL cache.

Provider is swappable — defaults to the free ER-API. In production you'd layer
multiple providers + a Redis cache + persistence for audit.
"""
import time
from decimal import Decimal

import httpx

from app.core.config import settings

_cache: dict[str, tuple[float, dict[str, float]]] = {}  # base -> (fetched_at, rates)

# Offline fallback rates (relative to base currency) so the API works in dev
# without network access. Key: "SRC:DST".
_FALLBACK_RATES: dict[str, Decimal] = {
    "USD:NGN": Decimal("1550.00"),
    "USD:GHS": Decimal("15.20"),
    "USD:KES": Decimal("129.00"),
    "USD:XOF": Decimal("600.00"),
    "GBP:NGN": Decimal("1960.00"),
    "EUR:XOF": Decimal("655.96"),
    "USD:USD": Decimal("1"),
}


def _fetch_rates(base: str) -> dict[str, float]:
    cached = _cache.get(base)
    if cached and (time.time() - cached[0]) < settings.FX_CACHE_TTL_SECONDS:
        return cached[1]
    try:
        resp = httpx.get(f"{settings.FX_API_URL}/{base}", timeout=5.0)
        resp.raise_for_status()
        rates: dict[str, float] = resp.json()["rates"]
    except Exception:
        rates = cached[1] if cached else {}
    if rates:
        _cache[base] = (time.time(), rates)
    return rates


def get_mid_rate(send_currency: str, payout_currency: str) -> Decimal:
    """Return mid-market rate: 1 unit of send_currency in payout_currency."""
    if send_currency == payout_currency:
        return Decimal("1")
    rates = _fetch_rates(send_currency.upper())
    rate = rates.get(payout_currency.upper())
    if rate is None:
        fallback = _FALLBACK_RATES.get(f"{send_currency.upper()}:{payout_currency.upper()}")
        if fallback is None:
            raise ValueError(f"No FX rate for {send_currency}->{payout_currency}")
        return fallback
    return Decimal(str(rate))
