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
    print(f"[OTP -> {phone}] CashGo code: {code}")
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


def issue_token(user: User) -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode(
        {"sub": str(user.id), "phone": user.phone,
         "iat": now, "exp": now + timedelta(seconds=settings.JWT_TTL_SECONDS)},
        settings.JWT_SECRET, algorithm="HS256",
    )
