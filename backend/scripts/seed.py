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

for ccy, amt in (("USD", "2000.00"), ("ZAR", "10000.00"), ("ZWG", "5000.00")):
    wallet = db.execute(select(Wallet).where(
        Wallet.user_id == user.id, Wallet.currency == ccy)).scalar_one_or_none()
    if wallet is None:
        wallet = Wallet(user_id=user.id, currency=ccy)
        db.add(wallet)
        db.flush()
        wallet_service.topup(db, wallet, Decimal(amt), "Seed top-up")

# --- fee tiers: live corridors only {ZM, TZ, ZA, ZW} + US/UK senders ----------
LIVE_DESTS = {"ZM", "TZ", "ZA", "ZW"}
CCY = {"ZM": "ZMW", "TZ": "TZS", "ZA": "ZAR", "ZW": "ZWG",
       "US": "USD", "GB": "GBP"}
SOURCES = ["US", "GB", "ZM", "TZ", "ZA", "ZW"]

# deactivate corridors outside the live footprint or from removed senders
for cfg in db.execute(select(CorridorFeeConfig)).scalars():
    if cfg.dest_country not in LIVE_DESTS or cfg.source_country in ("US", "GB"):
        cfg.is_active = False

# payout currencies offered per destination — receiver's choice
PAYOUTS = {"ZW": ["ZWG", "USD"], "ZM": ["ZMW", "USD"],
           "ZA": ["ZAR", "USD"], "TZ": ["TZS", "USD"]}

def tier(src, dst, payout_ccy, lo, hi, flat, pct, mk):
    exists = db.execute(select(CorridorFeeConfig).where(
        CorridorFeeConfig.source_country == src,
        CorridorFeeConfig.dest_country == dst,
        CorridorFeeConfig.send_currency == CCY[src],
        CorridorFeeConfig.payout_currency == payout_ccy,
        CorridorFeeConfig.min_amount == lo)).scalar_one_or_none()
    if exists is None:
        db.add(CorridorFeeConfig(
            source_country=src, dest_country=dst,
            send_currency=CCY[src], payout_currency=payout_ccy,
            min_amount=lo, max_amount=hi,
            flat_fee=flat, percent_fee=pct, fx_margin_markup=mk, is_active=True))

for dst, payouts in PAYOUTS.items():
    for pc in payouts:
        for src in ("ZM", "TZ", "ZA", "ZW"):
            if src != dst:
                tier(src, dst, pc, 0, 5000, "10.00", "0.010", "0.008")

# --- agents (upsert by name so reseeding fixes stale coordinates) --------------
from geoalchemy2.elements import WKTElement

for a in db.execute(select(PickupAgent)).scalars():
    if a.country_code not in LIVE_DESTS:
        a.is_active = False
agents = [
    # Zambia
    ("Lusaka Cairo Rd Booth", "Lusaka", "ZM", 28.2830, -15.4167, ["ZMW"]),
    ("Kitwe Copperbelt Agent", "Kitwe", "ZM", 28.2130, -12.8024, ["ZMW"]),
    # Tanzania
    ("Dar es Salaam Kariakoo", "Dar es Salaam", "TZ", 39.2722, -6.8235, ["TZS"]),
    ("Arusha Clock Tower Booth", "Arusha", "TZ", 36.6828, -3.3869, ["TZS"]),
    # South Africa
    ("Joburg CBD CashPoint", "Johannesburg", "ZA", 28.0473, -26.2041, ["ZAR"]),
    ("Cape Town Long St Kiosk", "Cape Town", "ZA", 18.4099, -33.9217, ["ZAR"]),
    # Zimbabwe
    ("Harare CBD Agent", "Harare", "ZW", 31.0535, -17.8252, ["ZWG", "USD"]),
    ("Bulawayo Main St Booth", "Bulawayo", "ZW", 28.5823, -20.1486, ["ZWG"]),
]
for name, city, cc, lon, lat, currs in agents:
    existing = db.execute(
        select(PickupAgent).where(PickupAgent.agent_name == name)).scalar_one_or_none()
    if existing is None:
        db.add(PickupAgent(agent_name=name, city=city, country_code=cc,
                           supported_currencies=currs,
                           operating_hours={"mon-fri": "08:00-18:00", "sat": "09:00-15:00"},
                           location=WKTElement(f"POINT({lon} {lat})", srid=4326)))
    else:
        existing.location = WKTElement(f"POINT({lon} {lat})", srid=4326)

db.commit()
print(f"Seeded. Demo user id: {user.id}")
