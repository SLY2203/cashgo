"""Phone-OTP authentication + JWT issuance."""
import hashlib
import secrets
from datetime import datetime, timedelta, timezone

import jwt
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models import OtpCode, User


def _hash(code: str, salt: str) -> str:
    return hashlib.sha256(f"{salt}:{code}".encode()).hexdigest()


def request_otp(db: Session, phone: str, purpose: str) -> str:
    """Create an OTP row and 'send' it. Returns the code (dev simulator — in
    prod this goes over SMS and is never returned)."""
    code = f"{secrets.randbelow(1_000_000):06d}"
    salt = secrets.token_hex(8)
    db.add(OtpCode(
        phone=phone, purpose=purpose,
        code_hash=_hash(code, salt) + ":" + salt,
        expires_at=datetime.now(timezone.utc) + timedelta(seconds=settings.OTP_TTL_SECONDS),
    ))
    db.commit()
    from app.services.messaging import send_otp_sms
    send_otp_sms(phone, code)
    return code


class OtpInvalid(Exception):
    pass


def verify_otp(db: Session, phone: str, code: str, purpose: str) -> None:
    otp = db.execute(
        select(OtpCode)
        .where(OtpCode.phone == phone, OtpCode.purpose == purpose,
               OtpCode.consumed_at.is_(None))
        .order_by(OtpCode.created_at.desc())
        .limit(1)
    ).scalar_one_or_none()

    now = datetime.now(timezone.utc)
    if otp is None or otp.expires_at < now or otp.attempts >= settings.OTP_MAX_ATTEMPTS:
        raise OtpInvalid("OTP expired or too many attempts")

    stored_hash, salt = otp.code_hash.split(":")
    otp.attempts += 1
    if _hash(code, salt) != stored_hash:
        db.commit()
        raise OtpInvalid("Incorrect code")

    otp.consumed_at = now
    db.commit()


def _qr_signature(payload_without_sig: dict) -> str:
    import json as _json
    canonical = _json.dumps(payload_without_sig, sort_keys=True,
                            separators=(",", ":"))
    return hashlib.sha256(
        f"{settings.JWT_SECRET}|{canonical}".encode()).hexdigest()[:32]


def sign_qr_payload(payload: dict, ttl_seconds: int = 120) -> dict:
    """Agent-side: server stamps + signs the QR payload so a screenshot
    can't be replayed later or forged."""
    import time as _time
    p = dict(payload)
    p["ts"] = int(_time.time())
    p["sig"] = _qr_signature(p)
    return p


class QrInvalid(Exception):
    pass


def verify_qr_payload(payload: dict, ttl_seconds: int = 300) -> None:
    """Client-side: reject unsigned, tampered, or stale (>5min) payloads."""
    import time as _time
    sig = payload.get("sig")
    ts = payload.get("ts")
    if not sig or not ts:
        raise QrInvalid("Unsigned QR payload")
    check = {k: v for k, v in payload.items() if k != "sig"}
    if not secrets.compare_digest(sig, _qr_signature(check)):
        raise QrInvalid("Invalid QR signature")
    if _time.time() - int(ts) > ttl_seconds:
        raise QrInvalid("QR expired — ask the agent to generate a new one")


def issue_token(user: User) -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode(
        {"sub": str(user.id), "phone": user.phone,
         "iat": now, "exp": now + timedelta(seconds=settings.JWT_TTL_SECONDS)},
        settings.JWT_SECRET, algorithm="HS256",
    )
