"""KYC provider abstraction.

Without SMILE_* env vars: instant-verify simulator (current behavior).
With them: submits an ID-info job to Smile Identity — covers ZW (Zim nat ID),
ZM (NRC), ZA (ID card), TZ (NIDA). Result arrives async; production would
poll or use Smile's callback. Here we synchronously check the job result
for simplicity.
"""
import hashlib
import hmac
import time
import uuid

import httpx

from app.core.config import settings

_SMILE_URL = "https://testapi.smileidentity.com/v1"  # prod: api.smileidentity.com

_COUNTRY_ID_TYPES = {
    "ZW": "NATIONAL_ID", "ZM": "NATIONAL_ID",
    "ZA": "NATIONAL_ID", "TZ": "NATIONAL_ID",
}


class KycResult:
    def __init__(self, verified: bool, job_id: str | None = None,
                 message: str = ""):
        self.verified = verified
        self.job_id = job_id
        self.message = message


def _signature(ts: str) -> str:
    key = (settings.SMILE_PARTNER_ID + ts).encode()
    return hmac.new(key, settings.SMILE_API_KEY.encode(),
                    hashlib.sha256).hexdigest()


def verify_id(country: str, document_type: str, id_number: str,
              full_name: str, phone: str) -> KycResult:
    if not (settings.SMILE_PARTNER_ID and settings.SMILE_API_KEY):
        return KycResult(verified=True, message="simulated")

    ts = str(int(time.time()))
    job_id = f"cashgo-{uuid.uuid4().hex[:12]}"
    payload = {
        "source_sdk": "rest_api", "source_sdk_version": "1.0.0",
        "partner_id": settings.SMILE_PARTNER_ID,
        "signature": _signature(ts), "timestamp": ts,
        "country": country,
        "id_type": _COUNTRY_ID_TYPES.get(country, document_type),
        "id_number": id_number,
        "first_name": full_name.split()[0],
        "last_name": " ".join(full_name.split()[1:]) or "-",
        "phone_number": phone,
        "job_id": job_id,
        "callback_url": "",  # sync mode
    }
    try:
        res = httpx.post(f"{_SMILE_URL}/id_verification", json=payload,
                         timeout=15.0)
        res.raise_for_status()
        data = res.json()
        return KycResult(
            verified=data.get("ResultCode") == "1012",  # verified match
            job_id=job_id,
            message=data.get("ResultText", ""),
        )
    except Exception:
        # Fail closed? For MVP: fail open with a flag — production must
        # return unverified and queue a retry.
        return KycResult(verified=False, job_id=job_id,
                         message="provider unreachable")
