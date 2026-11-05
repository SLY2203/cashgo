"""Voucher generation + SMS via Africa's Talking (simulator fallback).

Covers ZM/TZ/ZA/ZW well. Set AT_USERNAME + AT_API_KEY to go live
("sandbox" username + sandbox key for free testing).
"""
import logging
import secrets
import string

import httpx

from app.core.config import settings

logger = logging.getLogger("cashgo.sms")

_ALPHABET = string.ascii_uppercase + string.digits
_AT_URLS = {
    "prod": "https://api.africastalking.com/version1/messaging",
    "sandbox": "https://api.sandbox.africastalking.com/version1/messaging",
}


def generate_voucher_code() -> str:
    """CG-XXXX-XXXX — 8 secure random alphanumerics, formatted."""
    return "CG-" + "".join(secrets.choice(_ALPHABET) for _ in range(4)) \
           + "-" + "".join(secrets.choice(_ALPHABET) for _ in range(4))


def _send_sms(phone: str, text: str) -> None:
    if not (settings.AT_USERNAME and settings.AT_API_KEY):
        logger.info("[SMS-sim] to=%s | %s", phone, text)
        print(f"[SMS -> {phone}] {text}")
        return
    url = _AT_URLS["sandbox" if settings.AT_USERNAME == "sandbox" else "prod"]
    try:
        httpx.post(url, data={
            "username": settings.AT_USERNAME,
            "to": phone,
            "message": text,
            "from": settings.AT_SENDER_ID,
        }, headers={"apiKey": settings.AT_API_KEY,
                    "Accept": "application/json"}, timeout=10.0)
    except Exception:
        logger.exception("[SMS] Africa's Talking send failed to %s", phone)


def send_payout_sms(phone: str, voucher_code: str, amount, currency: str,
                    sender_name: str) -> None:
    _send_sms(phone,
              f"CashGo: You received {amount} {currency} from {sender_name}. "
              f"Pickup code: {voucher_code} at any CashGo agent.")


def send_otp_sms(phone: str, code: str) -> None:
    _send_sms(phone, f"CashGo code: {code}. Valid 5 minutes.")
