import uuid
from datetime import datetime
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, Field


# ---- Quotes -----------------------------------------------------------------
class QuoteRequest(BaseModel):
    source_country: str = Field(min_length=2, max_length=2)
    dest_country: str = Field(min_length=2, max_length=2)
    send_currency: str = Field(min_length=3, max_length=3)
    payout_currency: str = Field(min_length=3, max_length=3)
    send_amount: Decimal = Field(gt=0)


class QuoteResponse(BaseModel):
    quote_id: uuid.UUID
    send_amount: Decimal
    send_currency: str
    fee_amount: Decimal
    total_debit: Decimal
    mid_rate: Decimal
    applied_rate: Decimal
    payout_amount: Decimal
    payout_currency: str
    expires_at: datetime


# ---- Transfers ---------------------------------------------------------------
class TransferRequest(BaseModel):
    quote_id: uuid.UUID
    recipient_phone: str = Field(min_length=7, max_length=20)
    recipient_full_name: str = Field(min_length=2, max_length=120)
    payout_method: str = "CASH_PICKUP"


class TransactionResponse(BaseModel):
    transaction_id: uuid.UUID
    voucher_code: str
    status: str
    send_amount: Decimal
    send_currency: str
    fee_amount: Decimal
    exchange_rate: Decimal
    payout_amount: Decimal
    payout_currency: str
    recipient_name: str
    recipient_phone: str
    created_at: datetime
    paid_out_at: Optional[datetime] = None
    status_history: list = []


# ---- Agents ------------------------------------------------------------------
class AgentResponse(BaseModel):
    id: uuid.UUID
    agent_name: str
    city: str
    country_code: str
    address: Optional[str]
    supported_currencies: list[str]
    operating_hours: dict
    latitude: float
    longitude: float
    distance_m: float


# ---- Admin: fee configs -------------------------------------------------------
class FeeConfigIn(BaseModel):
    source_country: str = Field(min_length=2, max_length=2)
    dest_country: str = Field(min_length=2, max_length=2)
    send_currency: str = Field(min_length=3, max_length=3)
    payout_currency: str = Field(min_length=3, max_length=3)
    min_amount: Decimal = Field(ge=0)
    max_amount: Decimal = Field(gt=0)
    flat_fee: Decimal = Field(ge=0, default=0)
    percent_fee: Decimal = Field(ge=0, le=1, default=0)
    fx_margin_markup: Decimal = Field(ge=0, le=1, default=0)
    is_active: bool = True


class FeeConfigOut(FeeConfigIn):
    id: uuid.UUID
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# ---- Auth --------------------------------------------------------------------
class RegisterRequest(BaseModel):
    phone: str = Field(min_length=7, max_length=20)
    full_name: str = Field(min_length=2, max_length=120)
    country_code: str = Field(min_length=2, max_length=2)
    email: Optional[str] = None


class OtpRequest(BaseModel):
    phone: str = Field(min_length=7, max_length=20)


class OtpVerifyRequest(BaseModel):
    phone: str = Field(min_length=7, max_length=20)
    code: str = Field(min_length=6, max_length=6)


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: uuid.UUID
    kyc_status: str


# ---- Wallets -------------------------------------------------------------------
class TopupRequest(BaseModel):
    currency: str = Field(min_length=3, max_length=3)
    amount: Decimal = Field(gt=0)


class WalletResponse(BaseModel):
    currency: str
    balance: Decimal
    escrowed: Decimal


# ---- KYC -----------------------------------------------------------------------
class KycSubmitRequest(BaseModel):
    document_type: str = Field(pattern="^(PASSPORT|NATIONAL_ID|DRIVERS_LICENSE)$")
    id_number: str = Field(min_length=4, max_length=64)


# ---- Redemption ----------------------------------------------------------------
class RedeemRequest(BaseModel):
    voucher_code: str
    agent_id: uuid.UUID
