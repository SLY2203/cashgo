"""Corridor fee + quote calculation engine."""
from dataclasses import dataclass
from decimal import Decimal

from sqlalchemy import and_, select
from sqlalchemy.orm import Session

from app.models import CorridorFeeConfig
from app.services.fx import get_mid_rate


class CorridorNotSupported(Exception):
    pass


def find_fee_config(
    db: Session,
    source_country: str,
    dest_country: str,
    send_currency: str,
    payout_currency: str,
    send_amount: Decimal,
) -> CorridorFeeConfig:
    """Locate the active fee tier covering this corridor and amount."""
    stmt = (
        select(CorridorFeeConfig)
        .where(
            and_(
                CorridorFeeConfig.source_country == source_country.upper(),
                CorridorFeeConfig.dest_country == dest_country.upper(),
                CorridorFeeConfig.send_currency == send_currency.upper(),
                CorridorFeeConfig.payout_currency == payout_currency.upper(),
                CorridorFeeConfig.is_active.is_(True),
                CorridorFeeConfig.min_amount <= send_amount,
                CorridorFeeConfig.max_amount >= send_amount,
            )
        )
        .order_by(CorridorFeeConfig.min_amount.desc())  # tightest matching tier
        .limit(1)
    )
    cfg = db.execute(stmt).scalar_one_or_none()
    if cfg is None:
        raise CorridorNotSupported(
            f"No fee tier for {source_country}->{dest_country} "
            f"{send_currency}/{payout_currency} amount {send_amount}"
        )
    return cfg


@dataclass
class QuoteCalc:
    fee_amount: Decimal
    mid_rate: Decimal
    applied_rate: Decimal
    payout_amount: Decimal
    total_debit: Decimal
    fee_config_id: object


def calculate_quote(
    db: Session,
    source_country: str,
    dest_country: str,
    send_currency: str,
    payout_currency: str,
    send_amount: Decimal,
) -> QuoteCalc:
    cfg = find_fee_config(db, source_country, dest_country,
                          send_currency, payout_currency, send_amount)

    flat = Decimal(str(cfg.flat_fee))
    pct = Decimal(str(cfg.percent_fee))
    markup = Decimal(str(cfg.fx_margin_markup))

    fee = (flat + send_amount * pct).quantize(Decimal("0.0001"))
    principal = send_amount  # fee charged on top; use send_amount - fee if fee-inclusive
    mid_rate = get_mid_rate(send_currency, payout_currency)
    applied_rate = (mid_rate * (1 - markup)).quantize(Decimal("0.00000001"))
    payout = (principal * applied_rate).quantize(Decimal("0.01"))

    return QuoteCalc(
        fee_amount=fee,
        mid_rate=mid_rate,
        applied_rate=applied_rate,
        payout_amount=payout,
        total_debit=(send_amount + fee).quantize(Decimal("0.01")),
        fee_config_id=cfg.id,
    )
