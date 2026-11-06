"""Client-side QR scan flows — initiated by the agent, executed by the app.

QR payload (JSON, generated on the agent dashboard):
    {"op": "cashin"|"cashout", "agent_id": "...", "amount": 20, "currency": "ZWG"}

- cashin : agent took client's cash → credit client's wallet instantly
- cashout: client claims an incoming READY_FOR_PICKUP transfer that matches
           amount+currency at that agent → COMPLETED, escrow settles
"""
from datetime import datetime, timezone
from decimal import Decimal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user
from app.models import (PaymentIntent, PickupAgent, Transaction, TxnStatus,
                        User, Wallet)
from app.services import wallets as wallet_service
from app.services.messaging import _send_sms, generate_voucher_code

router = APIRouter(prefix="/scan", tags=["scan"])


class ScanRequest(BaseModel):
    agent_id: UUID
    amount: Decimal = Field(gt=0)
    currency: str = Field(min_length=3, max_length=3)
    ts: int | None = None
    sig: str | None = None


def _verify(body: ScanRequest) -> None:
    from app.services import auth as auth_service
    try:
        auth_service.verify_qr_payload(body.model_dump())
    except auth_service.QrInvalid as e:
        raise HTTPException(403, str(e))


@router.post("/cashin")
def scan_cashin(body: ScanRequest, user: User = Depends(get_current_user),
                db: Session = Depends(get_db)):
    _verify(body)
    agent = db.get(PickupAgent, body.agent_id)
    if agent is None or not agent.is_active:
        raise HTTPException(404, "Agent not found or inactive")

    wallet = wallet_service.get_wallet(db, user.id, body.currency)
    if wallet is None:
        wallet = Wallet(user_id=user.id, currency=body.currency.upper())
        db.add(wallet)
        db.flush()
    wallet_service.topup(db, wallet, body.amount,
                         f"QR cash-in @ {agent.agent_name}")

    receipt = generate_voucher_code().replace("CG", "CI", 1)
    db.add(PaymentIntent(
        user_id=user.id, wallet_id=wallet.id, agent_id=agent.id,
        reference=receipt, currency=body.currency.upper(),
        amount=body.amount, provider="agent_cash_in", status="PAID",
        paid_at=datetime.now(timezone.utc)))
    db.commit()

    return {"reference": receipt, "credited": str(body.amount),
            "currency": body.currency.upper(),
            "new_balance": str(wallet.balance), "agent": agent.agent_name}


@router.post("/cashout")
def scan_cashout(body: ScanRequest, user: User = Depends(get_current_user),
                 db: Session = Depends(get_db)):
    _verify(body)
    agent = db.get(PickupAgent, body.agent_id)
    if agent is None or not agent.is_active:
        raise HTTPException(404, "Agent not found or inactive")

    # The scanning client is the recipient — match their pending transfer
    txn = db.execute(
        select(Transaction)
        .where(Transaction.recipient_phone == user.phone,
               Transaction.status == TxnStatus.READY_FOR_PICKUP,
               Transaction.payout_currency == body.currency.upper(),
               Transaction.payout_amount == body.amount)
        .with_for_update()
    ).scalar_one_or_none()
    if txn is None:
        raise HTTPException(
            404, f"No pending {body.amount} {body.currency.upper()} "
                 f"transfer for {user.phone}")

    wallet = wallet_service.get_wallet(db, txn.sender_id, txn.send_currency)
    wallet_service.escrow_settle(
        db, wallet,
        Decimal(str(txn.send_amount)) + Decimal(str(txn.fee_amount)), txn)

    txn.status = TxnStatus.COMPLETED
    txn.pickup_agent_id = agent.id
    txn.paid_out_at = datetime.now(timezone.utc)
    txn.status_history = txn.status_history + [{
        "status": TxnStatus.COMPLETED.value,
        "at": txn.paid_out_at.isoformat(),
        "agent": agent.agent_name, "via": "qr"}]
    db.commit()

    _send_sms(txn.recipient_phone,
              f"CashGo: {txn.payout_amount} {txn.payout_currency} paid out "
              f"at {agent.agent_name}. Thank you.")

    return {"status": "COMPLETED", "voucher_code": txn.voucher_code,
            "amount": f"{txn.payout_amount} {txn.payout_currency}",
            "agent": agent.agent_name}
