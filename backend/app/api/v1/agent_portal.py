"""Agent portal API + dashboard page — the booth-side web UI.

Protected by X-Agent-Key (shared static key for MVP; real version gives each
agent their own login). Lets an agent:
  1. look up a voucher when a client comes to withdraw → verify recipient
  2. redeem it → mark COMPLETED, sender escrow settles
  3. credit a client's wallet when they hand over cash (agent cash-in)
"""
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import require_agent
from app.models import (PaymentIntent, PickupAgent, Transaction, TxnStatus,
                        User, Wallet)
from app.services import wallets as wallet_service
from app.services.messaging import _send_sms, generate_voucher_code

router = APIRouter(prefix="/agent", tags=["agent"],
                   dependencies=[Depends(require_agent)])


@router.get("/agents/")
def list_agents(db: Session = Depends(get_db)):
    """For the dashboard's 'which booth am I' selector."""
    rows = db.execute(
        select(PickupAgent).where(PickupAgent.is_active.is_(True))
        .order_by(PickupAgent.country_code, PickupAgent.city)).scalars()
    return [{"id": str(a.id), "name": a.agent_name, "city": a.city,
             "country": a.country_code} for a in rows]


@router.get("/voucher/{code}")
def lookup_voucher(code: str, db: Session = Depends(get_db)):
    """Step 1 of withdrawal: verify the voucher before paying out."""
    txn = db.execute(
        select(Transaction).where(Transaction.voucher_code == code.upper())
    ).scalar_one_or_none()
    if txn is None:
        raise HTTPException(404, "Voucher not found")
    return {
        "voucher_code": txn.voucher_code,
        "status": txn.status.value,
        "recipient_name": txn.recipient_name,
        "recipient_phone": txn.recipient_phone,
        "payout_amount": str(txn.payout_amount),
        "payout_currency": txn.payout_currency,
        "sender_country": txn.sender.country_code if txn.sender else None,
        "redeemable": txn.status == TxnStatus.READY_FOR_PICKUP,
    }


@router.post("/redeem/{code}")
def redeem_voucher(code: str, agent_id: UUID, db: Session = Depends(get_db)):
    """Step 2: agent pays cash → transaction COMPLETED."""
    agent = db.get(PickupAgent, agent_id)
    if agent is None or not agent.is_active:
        raise HTTPException(404, "Agent not found or inactive")

    txn = db.execute(
        select(Transaction).where(Transaction.voucher_code == code.upper())
        .with_for_update()
    ).scalar_one_or_none()
    if txn is None:
        raise HTTPException(404, "Voucher not found")
    if txn.status != TxnStatus.READY_FOR_PICKUP:
        raise HTTPException(409, f"Not redeemable (status: {txn.status.value})")

    wallet = wallet_service.get_wallet(db, txn.sender_id, txn.send_currency)
    wallet_service.escrow_settle(
        db, wallet,
        Decimal(str(txn.send_amount)) + Decimal(str(txn.fee_amount)), txn)

    txn.status = TxnStatus.COMPLETED
    txn.pickup_agent_id = agent.id
    txn.paid_out_at = datetime.now(timezone.utc)
    txn.status_history = txn.status_history + [{
        "status": TxnStatus.COMPLETED.value,
        "at": txn.paid_out_at.isoformat(), "agent": agent.agent_name}]
    db.commit()

    _send_sms(txn.recipient_phone,
              f"CashGo: {txn.payout_amount} {txn.payout_currency} paid out "
              f"at {agent.agent_name}. Thank you.")
    return {"status": "COMPLETED", "paid_out_at": txn.paid_out_at.isoformat(),
            "agent": agent.agent_name}


class CashInRequest(BaseModel):
    agent_id: UUID
    client_phone: str = Field(min_length=7, max_length=20)
    currency: str = Field(min_length=3, max_length=3)
    amount: Decimal = Field(gt=0)


@router.post("/cash-in/")
def cash_in(body: CashInRequest, db: Session = Depends(get_db)):
    """Client hands cash to the agent → agent credits their wallet."""
    agent = db.get(PickupAgent, body.agent_id)
    if agent is None or not agent.is_active:
        raise HTTPException(404, "Agent not found or inactive")
    if body.currency.upper() not in (agent.supported_currencies or []):
        # not a hard block — agents can handle any currency they stock
        pass

    client = db.execute(
        select(User).where(User.phone == body.client_phone)).scalar_one_or_none()
    if client is None:
        raise HTTPException(404, "No CashGo account for that phone — "
                                 "client must register first")

    wallet = wallet_service.get_wallet(db, client.id, body.currency)
    if wallet is None:
        wallet = Wallet(user_id=client.id, currency=body.currency.upper())
        db.add(wallet)
        db.flush()
    wallet_service.topup(db, wallet, body.amount,
                         f"Agent cash-in @ {agent.agent_name}")

    # receipt code for the agent's records
    receipt = generate_voucher_code().replace("CG", "CI", 1)
    db.add(PaymentIntent(
        user_id=client.id, wallet_id=wallet.id, agent_id=agent.id,
        reference=receipt, currency=body.currency.upper(),
        amount=body.amount, provider="agent_cash_in", status="PAID",
        paid_at=datetime.now(timezone.utc)))
    db.commit()

    _send_sms(client.phone,
              f"CashGo: {body.amount} {body.currency.upper()} credited "
              f"by {agent.agent_name}, {agent.city}. "
              f"Ref {receipt}. Balance: {wallet.balance} {wallet.currency}.")

    return {"reference": receipt, "credited": str(body.amount),
            "currency": body.currency.upper(), "client": client.full_name,
            "new_balance": str(wallet.balance), "agent": agent.agent_name}


@router.get("/history/")
def agent_history(agent_id: UUID, db: Session = Depends(get_db)):
    """The booth's book: withdrawals paid out + cash-ins processed."""
    agent = db.get(PickupAgent, agent_id)
    if agent is None:
        raise HTTPException(404, "Agent not found")

    withdrawals = db.execute(
        select(Transaction)
        .where(Transaction.pickup_agent_id == agent.id)
        .order_by(Transaction.paid_out_at.desc()).limit(100)).scalars()

    topups = db.execute(
        select(PaymentIntent, User)
        .join(User, PaymentIntent.user_id == User.id)
        .where(PaymentIntent.agent_id == agent.id,
               PaymentIntent.provider == "agent_cash_in")
        .order_by(PaymentIntent.created_at.desc()).limit(100)).all()

    return {
        "agent": agent.agent_name,
        "withdrawals": [{
            "voucher": t.voucher_code,
            "amount": f"{t.payout_amount} {t.payout_currency}",
            "recipient": t.recipient_name,
            "paid_at": t.paid_out_at.isoformat() if t.paid_out_at else None,
        } for t in withdrawals],
        "topups": [{
            "reference": i.reference,
            "amount": f"{i.amount} {i.currency}",
            "client": u.full_name, "phone": u.phone,
            "at": i.created_at.isoformat(),
        } for i, u in topups],
    }


# ---- dashboard page (unprotected shell; API calls need the agent key) --------
pages = APIRouter(tags=["agent"])

_DASHBOARD = (Path(__file__).resolve().parents[2]
              / "static" / "agent_dashboard.html")


@pages.get("/agent/dashboard/", response_class=HTMLResponse)
def dashboard():
    return HTMLResponse(_DASHBOARD.read_text(encoding="utf-8"))
