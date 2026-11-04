from datetime import datetime, timezone
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query
from geoalchemy2 import Geometry, functions as geofunc
from sqlalchemy import cast, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.models import PickupAgent, Transaction, TxnStatus
from app.schemas import AgentResponse, RedeemRequest, TransactionResponse
from app.services import wallets as wallet_service

router = APIRouter(prefix="/agents", tags=["agents"])


@router.get("/nearest/", response_model=list[AgentResponse])
def nearest_agents(
    latitude: float = Query(ge=-90, le=90),
    longitude: float = Query(ge=-180, le=180),
    radius_meters: int = Query(default=None, gt=0, le=100000),
    dest_country: str = Query(min_length=2, max_length=2),
    db: Session = Depends(get_db),
):
    radius = radius_meters or settings.DEFAULT_AGENT_RADIUS_M
    ref_point = f"SRID=4326;POINT({longitude} {latitude})"
    agent_geom = cast(PickupAgent.location, Geometry)

    dist = geofunc.ST_Distance(
        PickupAgent.location, geofunc.ST_GeogFromText(ref_point)
    ).label("distance_m")

    stmt = (
        select(
            PickupAgent,
            dist,
            geofunc.ST_Y(agent_geom).label("lat"),
            geofunc.ST_X(agent_geom).label("lon"),
        )
        .where(
            PickupAgent.is_active.is_(True),
            PickupAgent.country_code == dest_country.upper(),
            geofunc.ST_DWithin(
                PickupAgent.location, geofunc.ST_GeogFromText(ref_point), radius
            ),
        )
        .order_by(dist)
        .limit(50)
    )

    return [
        AgentResponse(
            id=row.PickupAgent.id,
            agent_name=row.PickupAgent.agent_name,
            city=row.PickupAgent.city,
            country_code=row.PickupAgent.country_code,
            address=row.PickupAgent.address,
            supported_currencies=row.PickupAgent.supported_currencies,
            operating_hours=row.PickupAgent.operating_hours,
            latitude=row.lat,
            longitude=row.lon,
            distance_m=float(row.distance_m),
        )
        for row in db.execute(stmt)
    ]


@router.post("/redeem/", response_model=TransactionResponse)
def redeem_voucher(body: RedeemRequest, db: Session = Depends(get_db)):
    """Agent pays out cash against a voucher code.

    In production this sits behind agent auth; here we just verify the agent
    exists and is active.
    """
    agent = db.get(PickupAgent, body.agent_id)
    if agent is None or not agent.is_active:
        raise HTTPException(404, "Agent not found or inactive")

    txn = db.execute(
        select(Transaction)
        .where(Transaction.voucher_code == body.voucher_code.upper())
        .with_for_update()
    ).scalar_one_or_none()
    if txn is None:
        raise HTTPException(404, "Voucher not found")
    if txn.status != TxnStatus.READY_FOR_PICKUP:
        raise HTTPException(409, f"Voucher not redeemable (status: {txn.status.value})")

    # Settle sender escrow — funds leave the wallet permanently.
    wallet = wallet_service.get_wallet(db, txn.sender_id, txn.send_currency)
    wallet_service.escrow_settle(
        db, wallet,
        Decimal(str(txn.send_amount)) + Decimal(str(txn.fee_amount)), txn)

    txn.status = TxnStatus.COMPLETED
    txn.pickup_agent_id = agent.id
    txn.paid_out_at = datetime.now(timezone.utc)
    txn.status_history = txn.status_history + [{
        "status": TxnStatus.COMPLETED.value,
        "at": txn.paid_out_at.isoformat(), "agent_id": str(agent.id)}]
    db.commit()
    db.refresh(txn)

    return TransactionResponse(
        transaction_id=txn.id, voucher_code=txn.voucher_code,
        status=txn.status.value, send_amount=txn.send_amount,
        send_currency=txn.send_currency, fee_amount=txn.fee_amount,
        exchange_rate=txn.exchange_rate, payout_amount=txn.payout_amount,
        payout_currency=txn.payout_currency, recipient_name=txn.recipient_name,
        recipient_phone=txn.recipient_phone, created_at=txn.created_at,
    )
