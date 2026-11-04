"""Voucher generation + SMS notification simulator."""
import logging
import secrets
import string

logger = logging.getLogger("cashgo.sms")

_ALPHABET = string.ascii_uppercase + string.digits


def generate_voucher_code() -> str:
    """CG-XXXX-XXXX — 8 secure random alphanumerics, formatted."""
    return "CG-" + "".join(secrets.choice(_ALPHABET) for _ in range(4)) \
           + "-" + "".join(secrets.choice(_ALPHABET) for _ in range(4))


def send_payout_sms(phone: str, voucher_code: str, amount, currency: str,
                    sender_name: str) -> None:
    """Simulator — logs instead of hitting Twilio/Africa's Talking."""
    logger.info(
        "[SMS] to=%s | CashGo: You received %s %s from %s. "
        "Pickup code: %s at any CashGo agent.",
        phone, amount, currency, sender_name, voucher_code,
    )
    print(f"[SMS -> {phone}] CashGo: You received {amount} {currency} from "
          f"{sender_name}. Pickup code: {voucher_code} at any CashGo agent.")
