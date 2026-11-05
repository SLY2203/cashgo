from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user
from app.models import KycStatus, User
from app.schemas import (KycSubmitRequest, OtpRequest, OtpVerifyRequest,
                         RegisterRequest, TokenResponse)
from app.services import auth as auth_service

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register/", response_model=TokenResponse, status_code=201)
def register(body: RegisterRequest, db: Session = Depends(get_db)):
    exists = db.execute(
        select(User).where(User.phone == body.phone)).scalar_one_or_none()
    if exists:
        raise HTTPException(409, "Phone already registered")
    user = User(phone=body.phone, full_name=body.full_name,
                country_code=body.country_code.upper(), email=body.email)
    db.add(user)
    db.commit()
    db.refresh(user)
    return TokenResponse(access_token=auth_service.issue_token(user),
                         user_id=user.id, kyc_status=user.kyc_status.value)


@router.post("/otp/request/")
def otp_request(body: OtpRequest, db: Session = Depends(get_db)):
    user = db.execute(
        select(User).where(User.phone == body.phone)).scalar_one_or_none()
    if user is None:
        raise HTTPException(404, "Phone not registered")
    # Dev simulator returns the code in the response; prod sends via SMS only.
    code = auth_service.request_otp(db, body.phone, purpose="login")
    from app.core.config import settings
    return {"sent": True,
            "dev_code": code if not settings.AT_API_KEY else None}


@router.post("/otp/verify/", response_model=TokenResponse)
def otp_verify(body: OtpVerifyRequest, db: Session = Depends(get_db)):
    user = db.execute(
        select(User).where(User.phone == body.phone)).scalar_one_or_none()
    if user is None:
        raise HTTPException(404, "Phone not registered")
    try:
        auth_service.verify_otp(db, body.phone, body.code, purpose="login")
    except auth_service.OtpInvalid as e:
        raise HTTPException(401, str(e))
    return TokenResponse(access_token=auth_service.issue_token(user),
                         user_id=user.id, kyc_status=user.kyc_status.value)


@router.post("/kyc/")
def submit_kyc(body: KycSubmitRequest,
               user: User = Depends(get_current_user),
               db: Session = Depends(get_db)):
    """Simulated instant KYC check — in prod this posts to a verification
    provider (Smile Identity, Dojah, etc.) and a webhook flips the status."""
    from app.services import kyc as kyc_service
    result = kyc_service.verify_id(user.country_code, body.document_type,
                                   body.id_number, user.full_name, user.phone)
    user.kyc_document = body.document_type
    user.kyc_id_number = body.id_number
    user.kyc_status = KycStatus.VERIFIED if result.verified else KycStatus.REJECTED
    db.commit()
    return {"kyc_status": user.kyc_status.value, "detail": result.message}
