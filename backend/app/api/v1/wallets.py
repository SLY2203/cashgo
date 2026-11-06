"""Wallet endpoints — top-up goes through a payment provider when configured."""
from decimal import Decimal

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user
from app.models import PaymentIntent, User, Wallet
from app.schemas import TopupRequest, WalletResponse
from app.services import payments, wallets as wallet_service

router = APIRouter(prefix="/wallets", tags=["wallets"])


@router.get("/", response_model=list[WalletResponse])
def list_wallets(user: User = Depends(get_current_user),
                 db: Session = Depends(get_db)):
    rows = db.execute(select(Wallet).where(Wallet.user_id == user.id)).scalars()
    return [WalletResponse(currency=w.currency, balance=w.balance,
                           escrowed=w.escrowed) for w in rows]


@router.post("/topup/", status_code=201)
def topup(body: TopupRequest, user: User = Depends(get_current_user),
          db: Session = Depends(get_db)):
    """Create a payment intent. With Paystack configured, returns a hosted
    checkout URL; in dev mode the wallet is credited immediately."""
    ref = payments.new_reference()
    email = user.email or f"{user.phone.lstrip('+')}@cashgo.dev"

    intent = PaymentIntent(user_id=user.id, reference=ref,
                           currency=body.currency.upper(),
                           amount=body.amount)
    result = payments.create_intent(ref, email, Decimal(str(body.amount)),
                                    body.currency)
    intent.payment_url = result["payment_url"]

    if result["dev_mode"]:
        # Simulator path — credit immediately
        wallet = wallet_service.get_wallet(db, user.id, body.currency)
        if wallet is None:
            wallet = Wallet(user_id=user.id, currency=body.currency.upper())
            db.add(wallet)
            db.flush()
        intent.wallet_id = wallet.id
        intent.status = "PAID"
        intent.paid_at = payments.mark_paid()
        wallet_service.topup(db, wallet, Decimal(str(body.amount)),
                             f"Dev top-up {ref}")
        wallet_service.audit(db, "TOPUP", actor=user.id, ref=ref,
                             detail={"amount": str(body.amount),
                                     "ccy": body.currency.upper(),
                                     "via": "dev"})
    db.add(intent)
    db.commit()

    return {
        "reference": ref,
        "dev_mode": result["dev_mode"],
        "payment_url": result["payment_url"],
        "status": intent.status,
    }
