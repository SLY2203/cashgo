"""Payment intents + Paystack webhook."""
from datetime import datetime, timezone
from decimal import Decimal
from uuid import UUID

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user
from app.models import PaymentIntent, User, Wallet
from app.services import payments, wallets as wallet_service

router = APIRouter(prefix="/payments", tags=["payments"])


@router.get("/intents/{reference}/status")
def intent_status(reference: str, user: User = Depends(get_current_user),
                  db: Session = Depends(get_db)):
    intent = db.execute(select(PaymentIntent)
                        .where(PaymentIntent.reference == reference)).scalar_one_or_none()
    if intent is None or intent.user_id != user.id:
        raise HTTPException(404, "Intent not found")
    # Webhook may lag — confirm server-side as a fallback
    if intent.status == "INITIATED" and payments.verify_transaction(reference):
        _credit(db, intent)
    return {"reference": intent.reference, "status": intent.status}


@router.post("/paystack/webhook")
async def paystack_webhook(request: Request,
                           x_paystack_signature: str | None = Header(default=None),
                           db: Session = Depends(get_db)):
    body = await request.body()
    event = payments.verify_webhook(body, x_paystack_signature)
    if event is None:
        raise HTTPException(401, "Invalid signature")
    if event.get("event") == "charge.success":
        ref = event["data"]["reference"]
        intent = db.execute(select(PaymentIntent)
                            .where(PaymentIntent.reference == ref)).scalar_one_or_none()
        if intent and intent.status == "INITIATED":
            _credit(db, intent)
    return {"received": True}


def _credit(db: Session, intent: PaymentIntent) -> None:
    """Credit the wallet once — idempotent via status check."""
    intent.status = "PAID"
    intent.paid_at = datetime.now(timezone.utc)
    wallet = wallet_service.get_wallet(db, intent.user_id, intent.currency)
    if wallet is None:
        wallet = Wallet(user_id=intent.user_id, currency=intent.currency)
        db.add(wallet)
        db.flush()
    intent.wallet_id = wallet.id
    wallet_service.topup(db, wallet, Decimal(str(intent.amount)),
                         f"Top-up {intent.provider} {intent.reference}")
    db.commit()
