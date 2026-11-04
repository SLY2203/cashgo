"""Wallet + escrow ledger operations. Every mutation writes a LedgerEntry."""
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import LedgerEntry, Transaction, Wallet


class InsufficientFunds(Exception):
    pass


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
