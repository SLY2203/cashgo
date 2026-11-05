from datetime import datetime, timedelta, timezone
from decimal import Decimal

from fastapi import APIRouter, Depends, Header, HTTPException, Response
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import (FxQuote, KycStatus, PayoutMethod, Transaction,
                        TxnStatus, User)
from app.schemas import (QuoteRequest, QuoteResponse, TransactionResponse,
                         TransferRequest)
from app.services import fees as fee_service
from app.services import wallets as wallet_service
from app.services.messaging import generate_voucher_code, send_payout_sms

router = APIRouter(prefix="/remittances", tags=["remittances"])


def _txn_response(txn: Transaction) -> TransactionResponse:
    return TransactionResponse(
        transaction_id=txn.id, voucher_code=txn.voucher_code,
        status=txn.status.value, send_amount=txn.send_amount,
        send_currency=txn.send_currency, fee_amount=txn.fee_amount,
        exchange_rate=txn.exchange_rate, payout_amount=txn.payout_amount,
        payout_currency=txn.payout_currency, recipient_name=txn.recipient_name,
        recipient_phone=txn.recipient_phone, created_at=txn.created_at,
        paid_out_at=txn.paid_out_at, status_history=txn.status_history or [],
    )


@router.get("/corridors/")
def list_corridors(db: Session = Depends(get_db)):
    """Active corridors grouped as {src_country, dst_country} → send/payout
    currencies. The app builds its pickers from this so admin-added corridors
    appear without an app update."""
    from app.models import CorridorFeeConfig
    rows = db.execute(
        select(CorridorFeeConfig.source_country,
               CorridorFeeConfig.dest_country,
               CorridorFeeConfig.send_currency,
               CorridorFeeConfig.payout_currency)
        .where(CorridorFeeConfig.is_active.is_(True))).all()
    corridors: dict[tuple, dict] = {}
    for src, dst, sc, pc in rows:
        key = (src, sc, dst)
        c = corridors.setdefault(key, {
            "source_country": src, "send_currency": sc,
            "dest_country": dst, "payout_currencies": []})
        if pc not in c["payout_currencies"]:
            c["payout_currencies"].append(pc)
    return sorted(corridors.values(),
                  key=lambda c: (c["source_country"], c["dest_country"]))


@router.post("/quote/", response_model=QuoteResponse)
def create_quote(body: QuoteRequest, db: Session = Depends(get_db)):
    try:
        calc = fee_service.calculate_quote(
            db, body.source_country, body.dest_country,
            body.send_currency, body.payout_currency, body.send_amount,
        )
    except fee_service.CorridorNotSupported as e:
        raise HTTPException(404, str(e))
    except ValueError as e:
        raise HTTPException(502, str(e))  # FX provider failure

    quote = FxQuote(
        source_country=body.source_country.upper(),
        dest_country=body.dest_country.upper(),
        send_currency=body.send_currency.upper(),
        payout_currency=body.payout_currency.upper(),
        send_amount=body.send_amount,
        mid_rate=calc.mid_rate,
        applied_rate=calc.applied_rate,
        fee_amount=calc.fee_amount,
        payout_amount=calc.payout_amount,
        fee_config_id=calc.fee_config_id,
        expires_at=datetime.now(timezone.utc) + timedelta(seconds=settings.QUOTE_TTL_SECONDS),
    )
    db.add(quote)
    db.commit()
    db.refresh(quote)

    return QuoteResponse(
        quote_id=quote.id,
        send_amount=quote.send_amount,
        send_currency=quote.send_currency,
        fee_amount=quote.fee_amount,
        total_debit=calc.total_debit,
        mid_rate=quote.mid_rate,
        applied_rate=quote.applied_rate,
        payout_amount=quote.payout_amount,
        payout_currency=quote.payout_currency,
        expires_at=quote.expires_at,
    )


@router.post("/transfer/", response_model=TransactionResponse, status_code=201)
def create_transfer(body: TransferRequest, response: Response,
                    db: Session = Depends(get_db),
                    sender: User = Depends(get_current_user),
                    idempotency_key: str | None = Header(default=None)):
    # Idempotent retry: same key → same transaction, never a double escrow
    if idempotency_key:
        existing = db.execute(
            select(Transaction).where(
                Transaction.idempotency_key == idempotency_key)
        ).scalar_one_or_none()
        if existing is not None:
            if existing.sender_id != sender.id:
                raise HTTPException(409, "Idempotency key belongs to another user")
            response.status_code = 200
            return _txn_response(existing)
    if sender.kyc_status != KycStatus.VERIFIED:
        raise HTTPException(403, f"KYC not verified (status: {sender.kyc_status.value})")

    quote = db.get(FxQuote, body.quote_id, with_for_update=True)
    if quote is None:
        raise HTTPException(404, "Quote not found")
    if quote.consumed_at is not None:
        raise HTTPException(409, "Quote already used")
    if quote.expires_at < datetime.now(timezone.utc):
        raise HTTPException(410, "Quote expired — request a new one")

    txn = Transaction(
        sender_id=sender.id,
        quote_id=quote.id,
        recipient_phone=body.recipient_phone,
        recipient_name=body.recipient_full_name,
        payout_method=PayoutMethod(body.payout_method),
        send_currency=quote.send_currency,
        payout_currency=quote.payout_currency,
        send_amount=quote.send_amount,
        fee_amount=quote.fee_amount,
        exchange_rate=quote.applied_rate,
        payout_amount=quote.payout_amount,
        voucher_code=generate_voucher_code(),
        idempotency_key=idempotency_key,
        status=TxnStatus.PENDING,
        status_history=[{"status": TxnStatus.PENDING.value,
                         "at": datetime.now(timezone.utc).isoformat()}],
    )
    db.add(txn)
    db.flush()

    # Escrow: lock send_amount + fee in the sender's wallet
    total_debit = Decimal(str(quote.send_amount)) + Decimal(str(quote.fee_amount))
    wallet = wallet_service.get_wallet(db, sender.id, quote.send_currency)
    if wallet is None:
        raise HTTPException(402, f"No {quote.send_currency} wallet — top up first")
    try:
        wallet_service.escrow_hold(db, wallet, total_debit, txn)
    except wallet_service.InsufficientFunds as e:
        raise HTTPException(402, str(e))

    quote.consumed_at = datetime.now(timezone.utc)
    txn.status = TxnStatus.READY_FOR_PICKUP
    txn.status_history = txn.status_history + [{
        "status": TxnStatus.READY_FOR_PICKUP.value,
        "at": datetime.now(timezone.utc).isoformat()}]
    db.commit()
    db.refresh(txn)

    send_payout_sms(body.recipient_phone, txn.voucher_code,
                    txn.payout_amount, txn.payout_currency, sender.full_name)
    return _txn_response(txn)


@router.get("/transactions/", response_model=list[TransactionResponse])
def list_transactions(db: Session = Depends(get_db),
                      user: User = Depends(get_current_user)):
    rows = db.execute(
        select(Transaction)
        .where(Transaction.sender_id == user.id)
        .order_by(Transaction.created_at.desc())
        .limit(100)).scalars()
    return [_txn_response(t) for t in rows]


@router.get("/transactions/{txn_id}", response_model=TransactionResponse)
def get_transaction(txn_id: str, db: Session = Depends(get_db),
                    user: User = Depends(get_current_user)):
    txn = db.get(Transaction, txn_id)
    if txn is None or txn.sender_id != user.id:
        raise HTTPException(404, "Transaction not found")
    return _txn_response(txn)


@router.post("/transactions/{txn_id}/cancel", response_model=TransactionResponse)
def cancel_transaction(txn_id: str, db: Session = Depends(get_db),
                       user: User = Depends(get_current_user)):
    txn = db.get(Transaction, txn_id, with_for_update=True)
    if txn is None or txn.sender_id != user.id:
        raise HTTPException(404, "Transaction not found")
    if txn.status != TxnStatus.READY_FOR_PICKUP:
        raise HTTPException(409, f"Cannot cancel a {txn.status.value} transfer")

    wallet = wallet_service.get_wallet(db, user.id, txn.send_currency)
    wallet_service.escrow_release(
        db, wallet,
        Decimal(str(txn.send_amount)) + Decimal(str(txn.fee_amount)), txn)

    txn.status = TxnStatus.CANCELLED
    txn.status_history = txn.status_history + [{
        "status": TxnStatus.CANCELLED.value,
        "at": datetime.now(timezone.utc).isoformat()}]
    db.commit()
    db.refresh(txn)
    return _txn_response(txn)
