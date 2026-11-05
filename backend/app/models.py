import enum
import uuid
from datetime import datetime

from geoalchemy2 import Geography
from sqlalchemy import (ARRAY, TIMESTAMP, Boolean, CheckConstraint, Enum,
                        ForeignKey, Index, Numeric, String, Text, func)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class KycStatus(str, enum.Enum):
    PENDING = "PENDING"
    VERIFIED = "VERIFIED"
    REJECTED = "REJECTED"
    SUSPENDED = "SUSPENDED"


class TxnStatus(str, enum.Enum):
    PENDING = "PENDING"
    READY_FOR_PICKUP = "READY_FOR_PICKUP"
    COMPLETED = "COMPLETED"
    CANCELLED = "CANCELLED"
    FAILED = "FAILED"
    EXPIRED = "EXPIRED"


class PayoutMethod(str, enum.Enum):
    CASH_PICKUP = "CASH_PICKUP"
    MOBILE_MONEY = "MOBILE_MONEY"
    BANK = "BANK"


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    phone: Mapped[str] = mapped_column(String(20), unique=True)
    full_name: Mapped[str] = mapped_column(String(120))
    email: Mapped[str | None] = mapped_column(String(255))
    country_code: Mapped[str] = mapped_column(String(2))
    kyc_status: Mapped[KycStatus] = mapped_column(Enum(KycStatus, name="kyc_status"), default=KycStatus.PENDING)
    kyc_id_number: Mapped[str | None] = mapped_column(String(64))
    kyc_document: Mapped[str | None] = mapped_column(String(32))
    pin_hash: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), server_default=func.now(), onupdate=func.now())

    transactions: Mapped[list["Transaction"]] = relationship(back_populates="sender")


class CorridorFeeConfig(Base):
    __tablename__ = "corridor_fee_configs"
    __table_args__ = (
        CheckConstraint("max_amount > min_amount", name="chk_tier_range"),
        CheckConstraint("flat_fee >= 0 AND percent_fee >= 0 AND fx_margin_markup >= 0", name="chk_fees_nonneg"),
        Index("idx_fee_corridor", "source_country", "dest_country", "is_active"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    source_country: Mapped[str] = mapped_column(String(2))
    dest_country: Mapped[str] = mapped_column(String(2))
    send_currency: Mapped[str] = mapped_column(String(3))
    payout_currency: Mapped[str] = mapped_column(String(3))
    min_amount: Mapped[float] = mapped_column(Numeric(18, 4))
    max_amount: Mapped[float] = mapped_column(Numeric(18, 4))
    flat_fee: Mapped[float] = mapped_column(Numeric(18, 4), default=0)
    percent_fee: Mapped[float] = mapped_column(Numeric(6, 4), default=0)
    fx_margin_markup: Mapped[float] = mapped_column(Numeric(6, 4), default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), server_default=func.now(), onupdate=func.now())


class FxQuote(Base):
    __tablename__ = "fx_quotes"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    source_country: Mapped[str] = mapped_column(String(2))
    dest_country: Mapped[str] = mapped_column(String(2))
    send_currency: Mapped[str] = mapped_column(String(3))
    payout_currency: Mapped[str] = mapped_column(String(3))
    send_amount: Mapped[float] = mapped_column(Numeric(18, 4))
    mid_rate: Mapped[float] = mapped_column(Numeric(20, 8))
    applied_rate: Mapped[float] = mapped_column(Numeric(20, 8))
    fee_amount: Mapped[float] = mapped_column(Numeric(18, 4))
    payout_amount: Mapped[float] = mapped_column(Numeric(18, 4))
    fee_config_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("corridor_fee_configs.id"))
    expires_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True))
    consumed_at: Mapped[datetime | None] = mapped_column(TIMESTAMP(timezone=True))
    created_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), server_default=func.now())


class PickupAgent(Base):
    __tablename__ = "pickup_agents"
    __table_args__ = (Index("idx_agents_country", "country_code", "is_active"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    agent_name: Mapped[str] = mapped_column(String(160))
    city: Mapped[str] = mapped_column(String(100))
    country_code: Mapped[str] = mapped_column(String(2))
    address: Mapped[str | None] = mapped_column(Text)
    supported_currencies: Mapped[list[str]] = mapped_column(ARRAY(String(3)), default=list)
    operating_hours: Mapped[dict] = mapped_column(JSONB, default=dict)
    phone: Mapped[str | None] = mapped_column(String(20))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    location: Mapped[object] = mapped_column(Geography(geometry_type="POINT", srid=4326))
    created_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), server_default=func.now())


class Transaction(Base):
    __tablename__ = "transactions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    sender_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"))
    quote_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("fx_quotes.id"))
    recipient_phone: Mapped[str] = mapped_column(String(20))
    recipient_name: Mapped[str] = mapped_column(String(120))
    payout_method: Mapped[PayoutMethod] = mapped_column(Enum(PayoutMethod, name="payout_method"), default=PayoutMethod.CASH_PICKUP)
    send_currency: Mapped[str] = mapped_column(String(3))
    payout_currency: Mapped[str] = mapped_column(String(3))
    send_amount: Mapped[float] = mapped_column(Numeric(18, 4))
    fee_amount: Mapped[float] = mapped_column(Numeric(18, 4))
    exchange_rate: Mapped[float] = mapped_column(Numeric(20, 8))
    payout_amount: Mapped[float] = mapped_column(Numeric(18, 4))
    voucher_code: Mapped[str] = mapped_column(String(12), unique=True)
    idempotency_key: Mapped[str | None] = mapped_column(String(64), unique=True)
    status: Mapped[TxnStatus] = mapped_column(Enum(TxnStatus, name="txn_status"), default=TxnStatus.PENDING)
    pickup_agent_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("pickup_agents.id"))
    paid_out_at: Mapped[datetime | None] = mapped_column(TIMESTAMP(timezone=True))
    status_history: Mapped[list] = mapped_column(JSONB, default=list)
    created_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), server_default=func.now(), onupdate=func.now())

    sender: Mapped[User] = relationship(back_populates="transactions")
    quote: Mapped[FxQuote | None] = relationship()


class OtpCode(Base):
    __tablename__ = "otp_codes"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    phone: Mapped[str] = mapped_column(String(20))
    code_hash: Mapped[str] = mapped_column(Text)
    purpose: Mapped[str] = mapped_column(String(16))  # login | register
    expires_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True))
    consumed_at: Mapped[datetime | None] = mapped_column(TIMESTAMP(timezone=True))
    attempts: Mapped[int] = mapped_column(default=0)
    created_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), server_default=func.now())


class Wallet(Base):
    __tablename__ = "wallets"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"))
    currency: Mapped[str] = mapped_column(String(3))
    balance: Mapped[float] = mapped_column(Numeric(18, 4), default=0)
    escrowed: Mapped[float] = mapped_column(Numeric(18, 4), default=0)
    created_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), server_default=func.now(), onupdate=func.now())


class PaymentIntent(Base):
    __tablename__ = "payment_intents"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"))
    wallet_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("wallets.id"))
    reference: Mapped[str] = mapped_column(String(80), unique=True)
    currency: Mapped[str] = mapped_column(String(3))
    amount: Mapped[float] = mapped_column(Numeric(18, 4))
    provider: Mapped[str] = mapped_column(String(24), default="paystack")
    status: Mapped[str] = mapped_column(String(16), default="INITIATED")
    payment_url: Mapped[str | None] = mapped_column(Text)
    paid_at: Mapped[datetime | None] = mapped_column(TIMESTAMP(timezone=True))
    created_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), server_default=func.now())


class LedgerEntry(Base):
    __tablename__ = "ledger_entries"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    wallet_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("wallets.id"))
    transaction_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("transactions.id"))
    entry_type: Mapped[str] = mapped_column(String(24))
    amount: Mapped[float] = mapped_column(Numeric(18, 4))
    balance_after: Mapped[float] = mapped_column(Numeric(18, 4))
    escrowed_after: Mapped[float] = mapped_column(Numeric(18, 4))
    memo: Mapped[str | None] = mapped_column(String(200))
    created_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), server_default=func.now())
