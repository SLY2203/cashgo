"""Wallet + escrow ledger operations. Every mutation writes a LedgerEntry."""
from decimal import Decimal

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import LedgerEntry, Transaction, Wallet


class InsufficientFunds(Exception):
    pass


def get_agent_float(db: Session, agent_id, currency: str):
    """Agent's cash position in a currency (row-locking safe)."""
    from app.models import AgentFloat
    f = db.execute(
        select(AgentFloat)
        .where(AgentFloat.agent_id == agent_id,
               AgentFloat.currency == currency.upper())
        .with_for_update()).scalar_one_or_none()
    if f is None:
        f = AgentFloat(agent_id=agent_id, currency=currency.upper(), balance=0)
        db.add(f)
        db.flush()
    return f


def float_adjust(db: Session, agent_id, currency: str, delta: Decimal,
                 memo: str) -> None:
    """+delta on cash-in (agent received cash), −delta on payout."""
    f = get_agent_float(db, agent_id, currency)
    new = Decimal(str(f.balance)) + delta
    if new < 0:
        raise HTTPException(409,
            f"Insufficient agent float in {currency} "
            f"(has {f.balance}, needs {-delta})")
    f.balance = new


def audit(db: Session, action: str, actor=None, ref=None,
          detail: dict | None = None, ip: str | None = None) -> None:
    from app.models import AuditEvent
    db.add(AuditEvent(action=action, actor=str(actor) if actor else None,
                      ref=str(ref) if ref else None,
                      detail=detail or {}, ip=ip))


def transfer_internal(db: Session, src: Wallet, dst: Wallet,
                      amount: Decimal, txn) -> None:
    """P2P wallet→wallet: debit src, credit dst, two ledger lines."""
    src = db.execute(select(Wallet).where(Wallet.id == src.id)
                     .with_for_update()).scalar_one()
    dst = db.execute(select(Wallet).where(Wallet.id == dst.id)
                     .with_for_update()).scalar_one()
    if Decimal(str(src.balance)) < amount:
        raise HTTPException(402,
            f"Insufficient {src.currency} balance "
            f"(has {src.balance}, needs {amount})")
    src.balance = Decimal(str(src.balance)) - amount
    dst.balance = Decimal(str(dst.balance)) + amount
    db.add(LedgerEntry(
        wallet_id=src.id, transaction_id=txn.id, entry_type="P2P_OUT",
        amount=-amount, currency=src.currency,
        balance_after=src.balance, escrowed_after=src.escrowed,
        memo=f"P2P to {txn.recipient_phone}"))
    db.add(LedgerEntry(
        wallet_id=dst.id, transaction_id=txn.id, entry_type="P2P_IN",
        amount=amount, currency=dst.currency,
        balance_after=dst.balance, escrowed_after=dst.escrowed,
        memo=f"P2P from sender {txn.sender_id}"))


def get_wallet(db: Session, user_id, currency: str) -> Wallet | None:
    return db.execute(
        select(Wallet).where(Wallet.user_id == user_id,
                             Wallet.currency == currency.upper())
        .with_for_update()
    ).scalar_one_or_none()


def _entry(db, wallet, txn_id, entry_type, amount, memo=None):
    db.add(LedgerEntry(
        wallet_id=wallet.id, transaction_id=txn_id, entry_type=entry_type,
        amount=amount, balance_after=wallet.balance,
        escrowed_after=wallet.escrowed, memo=memo,
    ))


def topup(db: Session, wallet: Wallet, amount: Decimal, memo="Top-up") -> None:
    wallet.balance = wallet.balance + amount
    _entry(db, wallet, None, "TOPUP", amount, memo)


def escrow_hold(db: Session, wallet: Wallet, amount: Decimal,
                txn: Transaction) -> None:
    """Move send_amount+fee from balance into escrow for a transfer."""
    if wallet.balance < amount:
        raise InsufficientFunds(
            f"Need {amount} {wallet.currency}, have {wallet.balance}")
    wallet.balance = wallet.balance - amount
    wallet.escrowed = wallet.escrowed + amount
    _entry(db, wallet, txn.id, "ESCROW_HOLD", -amount,
           f"Hold for {txn.voucher_code}")


def escrow_release(db: Session, wallet: Wallet, amount: Decimal,
                   txn: Transaction) -> None:
    """Cancelled/failed transfer — escrow returns to balance."""
    wallet.escrowed = wallet.escrowed - amount
    wallet.balance = wallet.balance + amount
    _entry(db, wallet, txn.id, "ESCROW_RELEASE", amount,
           f"Release {txn.voucher_code}")


def escrow_settle(db: Session, wallet: Wallet, amount: Decimal,
                  txn: Transaction) -> None:
    """Paid out — escrowed funds leave the wallet for good."""
    wallet.escrowed = wallet.escrowed - amount
    _entry(db, wallet, txn.id, "ESCROW_DEBIT", -amount,
           f"Settled {txn.voucher_code}")
