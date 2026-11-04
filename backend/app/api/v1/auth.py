from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.models import User
from app.schemas import (OtpRequest, OtpVerifyRequest, RegisterRequest,
                         TokenResponse)
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
    return {"sent": True, "dev_code": code}


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
