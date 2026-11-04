"""Idempotent demo data: a verified user with a funded USD wallet, fee tiers,
and pickup agents. Safe to run repeatedly.

Run locally:  python -m scripts.seed
On Render:    set SEED_DEMO=true env var (runs once at startup; remove after)
"""
from decimal import Decimal

from sqlalchemy import select

from app.core.database import SessionLocal
from app.models import CorridorFeeConfig, PickupAgent, User, Wallet
from app.services import wallets as wallet_service

db = SessionLocal()

# --- user + funded wallet ---------------------------------------------------
user = db.execute(select(User).where(User.phone == "+2348012345678")).scalar_one_or_none()
if user is None:
    user = User(phone="+2348012345678", full_name="Ada Okafor",
                country_code="NG", kyc_status="VERIFIED")
    db.add(user)
    db.flush()

wallet = db.execute(select(Wallet).where(Wallet.user_id == user.id,
                                         Wallet.currency == "USD")).scalar_one_or_none()
if wallet is None:
    wallet = Wallet(user_id=user.id, currency="USD")
    db.add(wallet)
    db.flush()
    wallet_service.topup(db, wallet, Decimal("2000.00"), "Seed top-up")

# --- fee tiers ----------------------------------------------------------------
if not db.execute(select(CorridorFeeConfig).limit(1)).scalar():
    db.add_all([
        CorridorFeeConfig(source_country="US", dest_country="NG", send_currency="USD",
                          payout_currency="NGN", min_amount=0, max_amount=500,
                          flat_fee="3.99", percent_fee="0.015", fx_margin_markup="0.012"),
        CorridorFeeConfig(source_country="US", dest_country="NG", send_currency="USD",
                          payout_currency="NGN", min_amount=500, max_amount=5000,
                          flat_fee="4.99", percent_fee="0.010", fx_margin_markup="0.010"),
    ])

# --- agents -------------------------------------------------------------------
if not db.execute(select(PickupAgent).limit(1)).scalar():
    from geoalchemy2.elements import WKTElement
    agents = [
        ("Lekki CashPoint", "Lagos", "NG", 6.4478, 3.4723, ["NGN"]),
        ("Ikeja MoneyBooth", "Lagos", "NG", 6.6018, 3.3515, ["NGN", "USD"]),
        ("Victoria Island Kiosk", "Lagos", "NG", 6.4281, 3.4219, ["NGN"]),
        ("Accra Osu Agent", "Accra", "GH", -0.1870, 5.6037, ["GHS"]),
        ("Nairobi CBD Booth", "Nairobi", "KE", 36.8219, -1.2921, ["KES"]),
    ]
    for name, city, cc, lon, lat, currs in agents:
        db.add(PickupAgent(
            agent_name=name, city=city, country_code=cc,
            supported_currencies=currs,
            operating_hours={"mon-fri": "08:00-18:00", "sat": "09:00-15:00"},
            location=WKTElement(f"POINT({lon} {lat})", srid=4326),
        ))

db.commit()
print(f"Seeded. Demo user id: {user.id}")
