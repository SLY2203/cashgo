"""Wallet endpoints — top-up is a dev simulator; prod wires payment rails."""
from decimal import Decimal

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user
from app.models import User, Wallet
from app.schemas import TopupRequest, WalletResponse
from app.services import wallets as wallet_service

router = APIRouter(prefix="/wallets", tags=["wallets"])


@router.get("/", response_model=list[WalletResponse])
def list_wallets(user: User = Depends(get_current_user),
                 db: Session = Depends(get_db)):
    rows = db.execute(select(Wallet).where(Wallet.user_id == user.id)).scalars()
    return [WalletResponse(currency=w.currency, balance=w.balance,
                           escrowed=w.escrowed) for w in rows]


@router.post("/topup/", response_model=WalletResponse, status_code=201)
def topup(body: TopupRequest, user: User = Depends(get_current_user),
          db: Session = Depends(get_db)):
    wallet = wallet_service.get_wallet(db, user.id, body.currency)
    if wallet is None:
        wallet = Wallet(user_id=user.id, currency=body.currency.upper())
        db.add(wallet)
        db.flush()
    wallet_service.topup(db, wallet, Decimal(str(body.amount)))
    db.commit()
    return WalletResponse(currency=wallet.currency, balance=wallet.balance,
                          escrowed=wallet.escrowed)
